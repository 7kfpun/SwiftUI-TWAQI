// TWAQI AQI alerts through Firebase Cloud Messaging. Every 10 minutes, match
// the current AQI against each enabled subscription in Directus and send an
// FCM alert to each device whose station just crossed its threshold. Only
// devices with an FCM token are sent to; older builds stay on OneSignal,
// whose sender is untouched. See README.md for the rules and secrets.
import { readings, type AqiConfig, type Reading } from './aqi.ts'
import {
  activeSubscriptions,
  archiveDevices,
  device as getDevice,
  tokenSuffix,
  updateSubscriptions,
  writeLogs,
  type DirectusConfig,
  type PushLog,
  type Subscription,
  type SubscriptionUpdate,
} from './directus.ts'
import { isConfigured as fcmConfigured, send, type FcmConfig } from './fcm.ts'
import { alertText, stationName, testText } from './message.ts'
import { decide, isQuiet, publishedAt, type Outcome } from './rules.ts'

interface Env extends FcmConfig, DirectusConfig, AqiConfig {
  /** Bearer token for the manual POST routes, shared with twaqi-workers. */
  SYNC_TOKEN: string
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

type Count = Outcome | 'no-data' | 'stale' | 'sent' | 'failed' | 'dead-token'

interface RunResult {
  subscriptions: number
  stations: number
  counts: Partial<Record<Count, number>>
  archivedDevices: number[]
  updated: number
  logged: number
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
      return json({ ok: true, service: 'twaqi-push-sender', fcmConfigured: fcmConfigured(env) })
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
  if (!dryRun && !fcmConfigured(env)) throw new Error('FCM_SERVICE_ACCOUNT is not set or not a service-account key')

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
    logged: 0,
    dryRun,
    decisions: dryRun ? [] : undefined,
  }
  const count = (key: Count) => (result.counts[key] = (result.counts[key] ?? 0) + 1)

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
  const logs: PushLog[] = []
  for (let i = 0; i < toSend.length; i += SEND_CONCURRENCY) {
    await Promise.all(
      toSend.slice(i, i + SEND_CONCURRENCY).map(async ({ sub, reading }) => {
        if (dead.has(sub.device.id)) return
        const token = sub.device.fcm_token as string
        const name = stationName(sub.device.locale, reading, sub.station_id)
        const log: PushLog = {
          token_suffix: tokenSuffix(token),
          status: 'failed',
          station: String(sub.station_id),
          trigger: sub.direction === 'above' ? 'pollution' : 'cleanliness',
          device: sub.device.id,
          aqi: Math.round(reading.aqi),
          fcm_message_id: null,
          error_code: null,
        }
        try {
          const res = await send(env, {
            token,
            ...alertText(sub.direction, sub.device.locale, name, reading.aqi, sub.threshold),
            data: alertData(sub, reading),
            collapseId: `aqi-${sub.id}`,
            threadId: `station-${sub.station_id}`,
            expiresInSeconds: ALERT_EXPIRY_SECONDS,
          })
          if (res.ok) {
            count('sent')
            log.status = 'sent'
            log.fcm_message_id = res.messageId ?? null
            update(sub.id, { in_zone: true, last_fired_at: now.toISOString() })
          } else if (res.deadToken) {
            count('dead-token')
            log.status = 'unregistered'
            log.error_code = res.errorCode ?? null
            dead.add(sub.device.id)
          } else {
            // Leave in_zone as it was, so the next run tries again.
            count('failed')
            log.error_code = res.errorCode ?? `HTTP_${res.status}`
            console.warn('fcm failed', sub.id, res.status, res.errorCode)
          }
        } catch (e) {
          count('failed')
          log.error_code = 'EXCEPTION'
          console.warn('fcm error', sub.id, String(e))
        }
        logs.push(log)
      }),
    )
  }

  result.archivedDevices = [...dead]
  await archiveDevices(env, result.archivedDevices)
  const changed = [...updates.values()].filter((u) => Object.keys(u).length > 1)
  await updateSubscriptions(env, changed)
  result.updated = changed.length
  result.logged = await logQuietly(env, logs)
  return result
}

/** Strings only (FCM's rule). Lets the app open the station when it learns to. */
function alertData(sub: Subscription, reading: Reading): Record<string, string> {
  return {
    station_id: String(sub.station_id),
    ...(sub.site_id ? { site_id: sub.site_id } : {}),
    subscription_id: String(sub.id),
    direction: sub.direction,
    threshold: String(sub.threshold),
    aqi: String(Math.round(reading.aqi)),
  }
}

/** POST /test {"device_id": 5}: one test alert to one device, ignoring quiet
 * hours, to check the service account and the APNs key in Firebase. */
async function sendTest(env: Env, body: Record<string, unknown>) {
  if (!fcmConfigured(env)) throw new Error('FCM_SERVICE_ACCOUNT is not set')
  const deviceId = Number(body.device_id)
  if (!Number.isInteger(deviceId)) return { error: 'device_id is required' }
  const device = await getDevice(env, deviceId)
  if (!device) return { error: `device ${deviceId} not found or archived` }
  if (!device.fcm_token) return { error: `device ${deviceId} has no FCM token (a build before FOX-13)` }

  const stationId = Number.isInteger(Number(body.station_id)) ? Number(body.station_id) : null
  const res = await send(env, {
    token: device.fcm_token,
    ...testText(device.locale),
    data: stationId === null ? {} : { station_id: String(stationId) },
  })
  if (res.deadToken) await archiveDevices(env, [device.id])
  await logQuietly(env, [
    {
      token_suffix: tokenSuffix(device.fcm_token),
      status: res.ok ? 'sent' : res.deadToken ? 'unregistered' : 'failed',
      station: stationId === null ? null : String(stationId),
      trigger: 'test',
      device: device.id,
      aqi: null,
      fcm_message_id: res.messageId ?? null,
      error_code: res.ok ? null : res.errorCode ?? `HTTP_${res.status}`,
    },
  ])
  return { device: device.id, ...res }
}

/** Writes the send log; a failure is logged and counted as 0, never thrown. */
async function logQuietly(env: Env, logs: PushLog[]): Promise<number> {
  if (!logs.length) return 0
  try {
    await writeLogs(env, logs)
    return logs.length
  } catch (e) {
    console.warn('push log write failed', String(e))
    return 0
  }
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
  if (!env.SYNC_TOKEN) return false
  const got = request.headers.get('Authorization') ?? ''
  const enc = new TextEncoder()
  const a = enc.encode(got)
  const b = enc.encode(`Bearer ${env.SYNC_TOKEN}`)
  return a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b)
}

function json(data: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...extra },
  })
}
