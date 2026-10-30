// TWAQI AQI alerts: every 10 minutes, match the current AQI against each
// enabled subscription in Directus and send APNs alerts straight from here.
// No OneSignal. See README.md for the rules and the secrets it needs.
import { readings, type AqiConfig, type Reading } from './aqi.ts'
import { sendAlert, type ApnsConfig } from './apns.ts'
import {
  activeSubscriptions,
  archiveDevices,
  device as getDevice,
  updateSubscriptions,
  type DirectusConfig,
  type Subscription,
  type SubscriptionUpdate,
} from './directus.ts'
import { decide, isQuiet, publishedAt, type Outcome } from './rules.ts'

interface Env extends ApnsConfig, DirectusConfig, AqiConfig {
  /** Bearer token for the manual POST routes. */
  ADMIN_TOKEN: string
  COOLDOWN_MINUTES?: string
  MAX_DATA_AGE_MINUTES?: string
}

interface RunOptions {
  now?: Date
  /** Don't send or write anything; report what would happen. */
  dryRun?: boolean
  /** Station id → AQI, replacing the live reading. For testing a crossing. */
  aqi?: Record<string, number>
}

interface RunResult {
  subscriptions: number
  stations: number
  counts: Partial<Record<Outcome | 'no-data' | 'stale' | 'sent' | 'failed' | 'dead-token', number>>
  archivedDevices: number[]
  updated: number
  dryRun: boolean
  decisions?: { subscription: number; device: number; station: number | null; aqi: number; outcome: string }[]
}

const SEND_CONCURRENCY = 10
/** An AQI alert an hour late is noise; let APNs drop it. */
const ALERT_EXPIRY_SECONDS = 60 * 60

export default {
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(
      run(env, { now: new Date(controller.scheduledTime) }).then(
        (r) => console.log('run ok', JSON.stringify(r)),
        (e) => {
          console.error('run failed', e)
          throw e
        },
      ),
    )
  },

  async fetch(request, env) {
    const url = new URL(request.url)

    if (url.pathname === '/' && (request.method === 'GET' || request.method === 'HEAD')) {
      return json({ ok: true, service: 'twaqi-push-sender', apnsConfigured: apnsConfigured(env) })
    }

    if (url.pathname === '/run' || url.pathname === '/test') {
      if (request.method !== 'POST') return json({ error: 'method not allowed' }, 405, { Allow: 'POST' })
      if (!(await authorized(request, env))) return json({ error: 'unauthorized' }, 401)
      const body = await readJson(request)
      try {
        if (url.pathname === '/run') {
          return json(await run(env, { dryRun: url.searchParams.has('dry'), aqi: body.aqi as Record<string, number> }))
        }
        return json(await sendTest(env, body))
      } catch (e) {
        return json({ error: String(e) }, 502)
      }
    }

    return json({ error: 'not found' }, 404)
  },
} satisfies ExportedHandler<Env>

async function run(env: Env, options: RunOptions = {}): Promise<RunResult> {
  const now = options.now ?? new Date()
  const dryRun = options.dryRun ?? false
  // Without a key every crossing would be recorded as handled and never sent.
  if (!dryRun && !apnsConfigured(env)) throw new Error('APNs secrets are not set (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8)')

  const cooldownMinutes = Number(env.COOLDOWN_MINUTES ?? 180)
  const maxAgeMs = Number(env.MAX_DATA_AGE_MINUTES ?? 180) * 60_000

  const subs = (await activeSubscriptions(env)).filter(
    (s) => (s.metric ?? 'aqi') === 'aqi' && typeof s.station_id === 'number',
  )
  const live = await readings(env, new Set(subs.map((s) => s.station_id as number)))
  for (const [id, aqi] of Object.entries(options.aqi ?? {})) {
    const stationId = Number(id)
    const reading = live.get(stationId)
    live.set(stationId, {
      stationId,
      aqi: Number(aqi),
      nameZh: reading?.nameZh ?? null,
      nameEn: reading?.nameEn ?? null,
      // An override stands in for a fresh reading.
      publishTime: null,
    })
  }

  const result: RunResult = {
    subscriptions: subs.length,
    stations: live.size,
    counts: {},
    archivedDevices: [],
    updated: 0,
    dryRun,
    decisions: dryRun ? [] : undefined,
  }
  const count = (key: keyof RunResult['counts']) => (result.counts[key] = (result.counts[key] ?? 0) + 1)

  const updates = new Map<number, SubscriptionUpdate>()
  const update = (id: number, fields: Omit<SubscriptionUpdate, 'id'>) =>
    updates.set(id, { ...(updates.get(id) ?? { id }), ...fields })
  const toSend: { sub: Subscription; reading: Reading }[] = []

  for (const sub of subs) {
    const reading = live.get(sub.station_id as number)
    if (!reading || !Number.isFinite(reading.aqi) || reading.aqi <= 0) {
      count('no-data')
      continue
    }
    const published = publishedAt(reading.publishTime)
    if (published && now.getTime() - published.getTime() > maxAgeMs) {
      // The station has stopped reporting; don't alert on an old number.
      count('stale')
      continue
    }

    const decision = decide({
      direction: sub.direction,
      threshold: sub.threshold,
      value: reading.aqi,
      wasInZone: sub.in_zone,
      lastFiredAt: sub.last_fired_at,
      quiet: isQuiet(sub.device, now),
      now,
      cooldownMinutes,
    })
    count(decision.outcome)
    result.decisions?.push({
      subscription: sub.id,
      device: sub.device.id,
      station: sub.station_id,
      aqi: reading.aqi,
      outcome: decision.outcome,
    })

    if (sub.last_value !== reading.aqi) update(sub.id, { last_value: reading.aqi })
    if (decision.outcome === 'fire') {
      toSend.push({ sub, reading })
    } else if (sub.in_zone !== decision.inZone) {
      update(sub.id, { in_zone: decision.inZone })
    }
  }

  if (dryRun) return result

  const dead = new Set<number>()
  for (let i = 0; i < toSend.length; i += SEND_CONCURRENCY) {
    await Promise.all(
      toSend.slice(i, i + SEND_CONCURRENCY).map(async ({ sub, reading }) => {
        if (dead.has(sub.device.id)) return
        try {
          const res = await sendAlert(env, sub.device.environment, sub.device.device_token, alertPayload(sub, reading), {
            collapseId: `aqi-${sub.id}`,
            expiresInSeconds: ALERT_EXPIRY_SECONDS,
          })
          if (res.ok) {
            count('sent')
            update(sub.id, { in_zone: true, last_fired_at: now.toISOString() })
          } else if (res.deadToken) {
            count('dead-token')
            dead.add(sub.device.id)
          } else {
            // Leave in_zone as it was, so the next run tries again.
            count('failed')
            console.warn('apns failed', sub.id, res.status, res.reason)
          }
        } catch (e) {
          count('failed')
          console.warn('apns error', sub.id, String(e))
        }
      }),
    )
  }

  result.archivedDevices = [...dead]
  await archiveDevices(env, result.archivedDevices)
  const changed = [...updates.values()].filter((u) => Object.keys(u).length > 1)
  await updateSubscriptions(env, changed)
  result.updated = changed.length
  return result
}

/** Localized on the device from the app's Localizable.strings, so the text
 * follows the app's language. Only the station name is chosen here. */
function alertPayload(sub: Subscription, reading: Reading) {
  const zh = (sub.device.locale ?? '').toLowerCase().startsWith('zh')
  const name = (zh ? reading.nameZh ?? reading.nameEn : reading.nameEn ?? reading.nameZh) ?? `#${sub.station_id}`
  return {
    aps: {
      alert: {
        'title-loc-key': `Push.aqi_${sub.direction}_title`,
        'title-loc-args': [name],
        'loc-key': `Push.aqi_${sub.direction}_body`,
        'loc-args': [name, formatNumber(reading.aqi), formatNumber(sub.threshold)],
      },
      sound: 'default',
      'thread-id': `station-${sub.station_id}`,
    },
    // Read by the app when the alert is tapped.
    station_id: sub.station_id,
    site_id: sub.site_id,
    subscription_id: sub.id,
    direction: sub.direction,
    threshold: sub.threshold,
    aqi: reading.aqi,
  }
}

/** POST /test {"device_id": 1, "station_id": 91}: one alert to one device,
 * ignoring quiet hours, to check the APNs key and the tap-through. */
async function sendTest(env: Env, body: Record<string, unknown>) {
  if (!apnsConfigured(env)) throw new Error('APNs secrets are not set')
  const deviceId = Number(body.device_id)
  if (!Number.isInteger(deviceId)) return { error: 'device_id is required' }
  const device = await getDevice(env, deviceId)
  if (!device) return { error: `device ${deviceId} not found or archived` }

  const stationId = Number.isInteger(Number(body.station_id)) ? Number(body.station_id) : null
  const res = await sendAlert(env, device.environment, device.device_token, {
    aps: { alert: { 'title-loc-key': 'Push.test_title', 'loc-key': 'Push.test_body' }, sound: 'default' },
    station_id: stationId,
  })
  if (res.deadToken) await archiveDevices(env, [device.id])
  return { device: device.id, environment: device.environment, ...res }
}

function formatNumber(n: number): string {
  return String(Math.round(n))
}

function apnsConfigured(env: Env): boolean {
  return Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_KEY_P8 && env.APNS_BUNDLE_ID)
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json()
    return body && typeof body === 'object' ? (body as Record<string, unknown>) : {}
  } catch {
    return {}
  }
}

async function authorized(request: Request, env: Env): Promise<boolean> {
  if (!env.ADMIN_TOKEN) return false
  const got = request.headers.get('Authorization') ?? ''
  const enc = new TextEncoder()
  const a = enc.encode(got)
  const b = enc.encode(`Bearer ${env.ADMIN_TOKEN}`)
  return a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b)
}

function json(data: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...extra },
  })
}
