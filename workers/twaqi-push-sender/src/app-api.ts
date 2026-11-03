// The app's push API (FOX-13 / FOX-37 M5). The app no longer holds a
// Directus token for the push collections: each install proves who it is
// with its Keychain `device_id` and a random secret made next to it, and this
// Worker, the only holder of a Directus token, reads and writes that device's
// rows and no one else's.
//
//   X-Device-Id: <device_id>          Authorization: Bearer <secret>
//
//   PUT  /app/v1/device                  upsert this device's row → { id }
//   GET  /app/v1/device?device_token=…   { device, subscriptions } for a restore
//   PUT  /app/v1/stations/:stationId     { site_id, above, below } → one station's alerts
//   POST /app/v1/archive-all             Help's "cancel all"
//
// Only a SHA-256 of the secret is stored (`secret_hash`). A row made before
// the secret existed is claimed by the first request that names its
// device_id (or, on a restore, its APNs token), then needs that secret.

import { request, DirectusError, type DirectusConfig } from './directus.ts'

/** Alerts may be on for at most this many stations per device, as in the
 * app (`FavouriteAlerts.maxAlertedStations`). */
export const MAX_STATIONS = 3

export interface AppApiEnv extends DirectusConfig {
  /** Optional Workers rate limiter keyed by client IP. */
  APP_LIMITER?: { limit(options: { key: string }): Promise<{ success: boolean }> }
}

type Direction = 'above' | 'below'

export interface SubscriptionRow {
  id: number
  station_id: string
  site_id: string | null
  metric: string | null
  direction: Direction
  threshold: number
  enabled: boolean
}

interface DeviceRow {
  id: number
  device_id: string | null
  secret_hash: string | null
}

/** The fields the app may set on its own row. Anything else in the body is
 * dropped, so a device can't touch the sender's state or another row. */
const DEVICE_FIELDS = [
  'device_token', 'fcm_token', 'environment', 'app_version', 'locale', 'is_pro',
  'last_seen_at', 'dnd_enabled', 'dnd_start', 'dnd_end', 'timezone',
] as const

const SUBSCRIPTION_FIELDS = 'id,station_id,site_id,metric,direction,threshold,enabled'

export class ApiError extends Error {
  readonly status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

/** Handles `/app/v1/*`, or returns null for any other path. */
export async function handleApp(request_: Request, env: AppApiEnv): Promise<Response | null> {
  const url = new URL(request_.url)
  if (!url.pathname.startsWith('/app/v1/')) return null
  try {
    if (env.APP_LIMITER) {
      const key = request_.headers.get('CF-Connecting-IP') ?? 'unknown'
      if (!(await env.APP_LIMITER.limit({ key })).success) throw new ApiError(429, 'too many requests')
    }
    const auth = await credentials(request_)
    const route = url.pathname.slice('/app/v1/'.length)

    if (route === 'device' && request_.method === 'PUT') {
      return json(await putDevice(env, auth, await body(request_)))
    }
    if (route === 'device' && request_.method === 'GET') {
      return json(await getDevice(env, auth, url.searchParams.get('device_token')))
    }
    const station = /^stations\/([0-9]{1,9})$/.exec(route)
    if (station && request_.method === 'PUT') {
      return json(await putStation(env, auth, station[1], await body(request_)))
    }
    if (route === 'archive-all' && request_.method === 'POST') {
      return json(await archiveAll(env, auth))
    }
    throw new ApiError(404, 'not found')
  } catch (e) {
    if (e instanceof ApiError) return json({ error: e.message }, e.status)
    console.error('app api failed', String(e))
    return json({ error: 'upstream error' }, 502)
  }
}

// MARK: - Auth

export interface Credentials {
  deviceId: string
  secretHash: string
}

const DEVICE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const SECRET = /^[A-Za-z0-9_-]{32,128}$/

export async function credentials(request_: Request): Promise<Credentials> {
  const deviceId = (request_.headers.get('X-Device-Id') ?? '').toLowerCase()
  const secret = /^Bearer (.+)$/.exec(request_.headers.get('Authorization') ?? '')?.[1] ?? ''
  if (!DEVICE_ID.test(deviceId) || !SECRET.test(secret)) throw new ApiError(401, 'device credentials required')
  return { deviceId, secretHash: await sha256(secret) }
}

export async function sha256(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))
  return [...digest].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function sameHash(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

/** This device's row id, or null when it has none. A row with another secret
 * is refused (403); one with no secret yet is claimed. With `deviceToken`, a
 * row that only knows this APNs token (from a build before the device id) is
 * adopted the same way. */
export async function ownDevice(env: DirectusConfig, auth: Credentials, deviceToken?: string | null): Promise<number | null> {
  let row = await findDevice(env, 'device_id', auth.deviceId)
  if (!row && deviceToken && /^[0-9a-f]{16,200}$/i.test(deviceToken)) {
    row = await findDevice(env, 'device_token', deviceToken)
    // A token row that already belongs to another install isn't this one's.
    if (row && (row.secret_hash || (row.device_id && row.device_id !== auth.deviceId))) row = null
  }
  if (!row) return null
  if (row.secret_hash) {
    if (!sameHash(row.secret_hash, auth.secretHash)) throw new ApiError(403, 'device credentials do not match')
    return row.id
  }
  await request(env, 'PATCH', `/items/twaqi_push_devices/${row.id}?fields=id`, {
    device_id: auth.deviceId,
    secret_hash: auth.secretHash,
  })
  return row.id
}

async function findDevice(env: DirectusConfig, field: string, value: string): Promise<DeviceRow | null> {
  const params = new URLSearchParams({
    fields: 'id,device_id,secret_hash',
    [`filter[${field}][_eq]`]: value,
    sort: 'id',
    limit: '1',
  })
  const { data } = await request<{ data: DeviceRow[] }>(env, 'GET', `/items/twaqi_push_devices?${params}`)
  return data[0] ?? null
}

// MARK: - Routes

export function deviceFields(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const key of DEVICE_FIELDS) {
    if (input[key] !== undefined) out[key] = input[key]
  }
  if (typeof out.device_token !== 'string' || !/^[0-9a-f]{16,200}$/i.test(out.device_token)) {
    throw new ApiError(400, 'device_token is required')
  }
  if (out.environment !== 'sandbox' && out.environment !== 'production') throw new ApiError(400, 'environment is required')
  for (const key of ['fcm_token', 'app_version', 'locale', 'last_seen_at', 'dnd_start', 'dnd_end', 'timezone']) {
    if (out[key] !== undefined && out[key] !== null && (typeof out[key] !== 'string' || (out[key] as string).length > 512)) {
      throw new ApiError(400, `${key} must be a short string`)
    }
  }
  for (const key of ['is_pro', 'dnd_enabled']) {
    if (out[key] !== undefined && typeof out[key] !== 'boolean') throw new ApiError(400, `${key} must be true or false`)
  }
  return out
}

async function putDevice(env: DirectusConfig, auth: Credentials, input: Record<string, unknown>) {
  const fields = deviceFields(input)
  const existing = await ownDevice(env, auth, fields.device_token as string)
  // A device seen again is alive, even if FCM once rejected its token.
  const row = { ...fields, archived: false }
  if (existing !== null) {
    await request(env, 'PATCH', `/items/twaqi_push_devices/${existing}?fields=id`, row)
    return { id: existing }
  }
  try {
    const { data } = await request<{ data: { id: number } }>(env, 'POST', '/items/twaqi_push_devices?fields=id', {
      ...row,
      device_id: auth.deviceId,
      secret_hash: auth.secretHash,
    })
    return { id: data.id }
  } catch (e) {
    // Lost a race to create (unique device_id or device_token): use the row
    // the other request made, if it's ours.
    if (e instanceof DirectusError && e.status === 400) {
      const id = await ownDevice(env, auth, fields.device_token as string)
      if (id !== null) {
        await request(env, 'PATCH', `/items/twaqi_push_devices/${id}?fields=id`, row)
        return { id }
      }
    }
    throw e
  }
}

async function getDevice(env: DirectusConfig, auth: Credentials, deviceToken: string | null) {
  const id = await ownDevice(env, auth, deviceToken)
  if (id === null) return { device: null, subscriptions: [] }
  const params = new URLSearchParams({ fields: 'id,dnd_enabled,dnd_start,dnd_end' })
  const { data: device } = await request<{ data: unknown }>(env, 'GET', `/items/twaqi_push_devices/${id}?${params}`)
  return { device, subscriptions: await liveSubscriptions(env, id) }
}

async function liveSubscriptions(env: DirectusConfig, device: number, stationId?: string): Promise<SubscriptionRow[]> {
  const params = new URLSearchParams({
    fields: SUBSCRIPTION_FIELDS,
    'filter[device][_eq]': String(device),
    'filter[archived][_eq]': 'false',
    sort: 'id',
    limit: '-1',
  })
  if (stationId) params.set('filter[station_id][_eq]', stationId)
  const { data } = await request<{ data: SubscriptionRow[] }>(env, 'GET', `/items/twaqi_push_subscriptions?${params}`)
  return data
}

function threshold(value: unknown, name: string): number | null {
  if (value === null || value === undefined) return null
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 500) {
    throw new ApiError(400, `${name} must be a whole AQI from 0 to 500, or null`)
  }
  return value
}

async function putStation(env: DirectusConfig, auth: Credentials, stationId: string, input: Record<string, unknown>) {
  const alerts = { above: threshold(input.above, 'above'), below: threshold(input.below, 'below') }
  const siteId = typeof input.site_id === 'string' && input.site_id.length <= 32 ? input.site_id : null
  const device = await ownDevice(env, auth)
  // The app writes its row before any alert, so there is one by now.
  if (device === null) throw new ApiError(404, 'register the device first')

  const all = await liveSubscriptions(env, device)
  const existing = all.filter((s) => s.station_id === stationId)
  const turningOn = alerts.above !== null || alerts.below !== null
  const others = new Set(all.filter((s) => s.station_id !== stationId && s.enabled).map((s) => s.station_id))
  if (turningOn && !existing.some((s) => s.enabled) && others.size >= MAX_STATIONS) {
    throw new ApiError(409, `alerts are already on for ${MAX_STATIONS} stations`)
  }

  const { save, archive } = plan(existing, stationId, siteId, alerts)
  for (const item of save) {
    if (item.id) {
      await request(env, 'PATCH', `/items/twaqi_push_subscriptions/${item.id}?fields=id`, {
        ...(item.site_id ? { site_id: item.site_id } : {}),
        threshold: item.threshold,
        enabled: true,
      })
    } else {
      await request(env, 'POST', '/items/twaqi_push_subscriptions?fields=id', {
        device,
        station_id: stationId,
        ...(item.site_id ? { site_id: item.site_id } : {}),
        metric: 'aqi',
        direction: item.direction,
        threshold: item.threshold,
        enabled: true,
        archived: false,
      })
    }
  }
  await archiveRows(env, archive)
  return { saved: save.length, archived: archive.length }
}

async function archiveAll(env: DirectusConfig, auth: Credentials) {
  const device = await ownDevice(env, auth)
  if (device === null) return { archived: 0 }
  const ids = (await liveSubscriptions(env, device)).map((s) => s.id)
  await archiveRows(env, ids)
  return { archived: ids.length }
}

/** Soft delete: the rows stay, archived and switched off. */
async function archiveRows(env: DirectusConfig, ids: number[]) {
  if (!ids.length) return
  await request(env, 'PATCH', '/items/twaqi_push_subscriptions?fields=id', { keys: ids, data: { archived: true, enabled: false } })
}

/** One station's writes, as the app's reconcile did: an alert that is on
 * updates its row (or makes one); one that is off archives its rows; extra
 * rows for a direction, from an earlier race, are archived. A matching row is
 * left alone. */
export function plan(
  existing: SubscriptionRow[],
  stationId: string,
  siteId: string | null,
  alerts: { above: number | null; below: number | null },
): { save: Array<{ id?: number; station_id: string; site_id: string | null; direction: Direction; threshold: number }>; archive: number[] } {
  const save: Array<{ id?: number; station_id: string; site_id: string | null; direction: Direction; threshold: number }> = []
  const archive: number[] = []
  for (const direction of ['above', 'below'] as const) {
    const rows = existing.filter((s) => s.direction === direction)
    const wanted = alerts[direction]
    if (wanted === null) {
      archive.push(...rows.map((r) => r.id))
      continue
    }
    const [keep, ...extra] = rows
    archive.push(...extra.map((r) => r.id))
    if (keep && keep.threshold === wanted && keep.enabled && (siteId === null || keep.site_id === siteId)) continue
    save.push({ id: keep?.id, station_id: stationId, site_id: siteId, direction, threshold: wanted })
  }
  return { save, archive }
}

async function body(request_: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request_.json()
    if (value && typeof value === 'object' && !Array.isArray(value)) return value as Record<string, unknown>
  } catch {
    // Fall through.
  }
  throw new ApiError(400, 'JSON object body required')
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}
