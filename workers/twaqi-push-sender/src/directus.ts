// Directus REST for the two push collections. Rows are never deleted:
// a dead device or subscription gets archived=true.

import type { Direction } from './rules.ts'

export interface DirectusConfig {
  DIRECTUS_URL: string
  DIRECTUS_TOKEN: string
}

export interface Device {
  id: number
  device_token: string
  environment: 'sandbox' | 'production'
  locale: string | null
  dnd_enabled: boolean | null
  dnd_start: string | null
  dnd_end: string | null
  timezone: string | null
}

export interface Subscription {
  id: number
  /** A string column in Directus ("91"); parsed to a number here. */
  station_id: number | null
  site_id: string | null
  metric: string | null
  direction: Direction
  threshold: number
  last_value: number | null
  in_zone: boolean | null
  last_fired_at: string | null
  device: Device
}

export type SubscriptionUpdate = { id: number } & Partial<
  Pick<Subscription, 'last_value' | 'in_zone' | 'last_fired_at'>
>

const DEVICE_FIELDS = ['id', 'device_token', 'environment', 'locale', 'dnd_enabled', 'dnd_start', 'dnd_end', 'timezone']
const SUBSCRIPTION_FIELDS = [
  'id', 'station_id', 'site_id', 'metric', 'direction', 'threshold', 'last_value', 'in_zone', 'last_fired_at',
  ...DEVICE_FIELDS.map((f) => `device.${f}`),
]
const PAGE_SIZE = 500

/** Enabled, unarchived subscriptions on unarchived devices, with their device. */
export async function activeSubscriptions(env: DirectusConfig): Promise<Subscription[]> {
  const all: Subscription[] = []
  for (let page = 1; ; page++) {
    const params = new URLSearchParams({
      fields: SUBSCRIPTION_FIELDS.join(','),
      'filter[enabled][_eq]': 'true',
      'filter[archived][_eq]': 'false',
      'filter[device][archived][_eq]': 'false',
      sort: 'id',
      limit: String(PAGE_SIZE),
      page: String(page),
    })
    const { data } = await request<{ data: Subscription[] }>(env, 'GET', `/items/twaqi_push_subscriptions?${params}`)
    // A device the token can't read comes back as null; nothing to send to.
    for (const s of data) {
      if (!s.device?.device_token) continue
      const stationId = Number(s.station_id)
      all.push({ ...s, station_id: s.station_id != null && Number.isInteger(stationId) ? stationId : null })
    }
    if (data.length < PAGE_SIZE) return all
  }
}

export async function device(env: DirectusConfig, id: number): Promise<Device | null> {
  const params = new URLSearchParams({ fields: DEVICE_FIELDS.join(','), 'filter[archived][_eq]': 'false' })
  try {
    const { data } = await request<{ data: Device }>(env, 'GET', `/items/twaqi_push_devices/${id}?${params}`)
    return data ?? null
  } catch (e) {
    if (e instanceof DirectusError && (e.status === 403 || e.status === 404)) return null
    throw e
  }
}

/** One batch PATCH per 100 rows, each row with its own values. */
export async function updateSubscriptions(env: DirectusConfig, updates: SubscriptionUpdate[]): Promise<void> {
  for (let i = 0; i < updates.length; i += 100) {
    await request(env, 'PATCH', '/items/twaqi_push_subscriptions?fields=id', updates.slice(i, i + 100))
  }
}

/** APNs said the token is dead. Its subscriptions stop matching because the
 * subscription query requires an unarchived device. */
export async function archiveDevices(env: DirectusConfig, ids: number[]): Promise<void> {
  if (!ids.length) return
  await request(env, 'PATCH', '/items/twaqi_push_devices?fields=id', { keys: ids, data: { archived: true } })
}

export class DirectusError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message)
  }
}

async function request<T = unknown>(env: DirectusConfig, method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${env.DIRECTUS_URL.replace(/\/+$/, '')}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${env.DIRECTUS_TOKEN}`,
      Accept: 'application/json',
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (!res.ok) {
    throw new DirectusError(res.status, `Directus ${method} ${path.split('?')[0]}: ${res.status} ${(await res.text()).slice(0, 300)}`)
  }
  // 204 when the token may write but not read the result back.
  return (res.status === 204 ? {} : await res.json()) as T
}
