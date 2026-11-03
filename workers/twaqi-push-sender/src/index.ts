// TWAQI AQI alerts through Firebase Cloud Messaging. Every 2 hours, read the
// current AQI of every station, ask Directus for only the subscriptions whose
// zone that changes, and send an FCM alert to each one that just crossed in. Only
// devices with an FCM token are sent to; older builds stay on OneSignal,
// whose sender is untouched. See README.md for the rules and secrets.
import { allReadings, type AqiConfig, type Reading } from './aqi.ts'
import { handleApp, type AppApiEnv } from './app-api.ts'
import {
  archiveDevices,
  crossingSubscriptions,
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

export interface Env extends FcmConfig, DirectusConfig, AqiConfig, AppApiEnv {
  /** Workers Analytics Engine dataset for every send (twaqi_push_events). */
  PUSH_EVENTS?: AnalyticsEngineDataset
  /** Bearer token for the manual POST routes, shared with twaqi-workers. */
  SYNC_TOKEN: string
  COOLDOWN_MINUTES?: string
  MAX_DATA_AGE_MINUTES?: string
  /** Sends per run; the rest wait for the next run. */
  MAX_SENDS_PER_RUN?: string
}

interface RunOptions {
  now?: Date
  /** Don't send or write anything; report what would happen. */
  dryRun?: boolean
  /** Station id → AQI, replacing the live reading. For testing a crossing. */
  aqi?: Record<string, number>
}

type Count = Outcome | 'sent' | 'failed' | 'dead-token' | 'deferred'

export interface RunResult {
  /** Stations with a fresh reading, each one filtered for in Directus. */
  stations: number
  /** Subscriptions whose zone changed: to send, drop, or re-arm. */
  subscriptions: number
  counts: Partial<Record<Count, number>>
  archivedDevices: number[]
  updated: number
  /** Rows written to Directus twaqi_push_logs: failures, dead tokens, tests. */
  logged: number
  /** Sends recorded in Analytics Engine (every one). */
  events: number
  dryRun: boolean
  decisions?: { subscription: number; device: number; station: number | null; aqi: number; outcome: string }[]
}

/** FCM sends in flight at once. 40k alerts at ~100 ms each take ~3 min. */
const SEND_CONCURRENCY = 25
/** State and logs are saved after every this many sends. */
const SAVE_EVERY = 100
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

    // The app's own push API, authenticated per device (app-api.ts).
    const app = await handleApp(request, env)
    if (app) return app

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

export async function run(env: Env, options: RunOptions = {}): Promise<RunResult> {
  const now = options.now ?? new Date()
  const dryRun = options.dryRun ?? false
  // Without a key every crossing would be recorded as handled and never sent.
  if (!dryRun && !fcmConfigured(env)) throw new Error('FCM_SERVICE_ACCOUNT is not set or not a service-account key')

  const cooldownMinutes = Number(env.COOLDOWN_MINUTES ?? 180)
  const maxAgeMs = Number(env.MAX_DATA_AGE_MINUTES ?? 180) * 60_000

  const live = await allReadings(env)
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

  // Only fresh, real readings move a subscription. A station that stopped
  // reporting, or reads 0, leaves every subscription on it as it was.
  const fresh = new Map<number, Reading>()
  for (const [stationId, reading] of live) {
    if (!Number.isFinite(reading.aqi) || reading.aqi <= 0) continue
    const published = publishedAt(reading.publishTime)
    if (published && now.getTime() - published.getTime() > maxAgeMs) continue
    fresh.set(stationId, reading)
  }

  // Directus does the matching: only rows whose zone disagrees with this AQI.
  const subs = (await crossingSubscriptions(env, [...fresh.values()].map((r) => ({ stationId: r.stationId, aqi: r.aqi })))).filter(
    (s) => typeof s.station_id === 'number' && fresh.has(s.station_id),
  )

  const result: RunResult = {
    stations: fresh.size,
    subscriptions: subs.length,
    counts: {},
    archivedDevices: [],
    updated: 0,
    logged: 0,
    events: 0,
    dryRun,
    decisions: dryRun ? [] : undefined,
  }
  const count = (key: Count) => (result.counts[key] = (result.counts[key] ?? 0) + 1)

  const updates = new Map<number, SubscriptionUpdate>()
  const update = (id: number, fields: Omit<SubscriptionUpdate, 'id'>) =>
    updates.set(id, { ...(updates.get(id) ?? { id }), ...fields })
  const toSend: { sub: Subscription; reading: Reading }[] = []

  for (const sub of subs) {
    const reading = fresh.get(sub.station_id as number) as Reading

    const decision = decide({
      direction: sub.direction,
      threshold: sub.threshold,
      // Rounded as in the Directus filter, so both agree on the zone.
      value: Math.round(reading.aqi),
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

    // Only rows whose state changes are written; last_value rides along.
    if (decision.outcome === 'fire') {
      toSend.push({ sub, reading })
    } else if (sub.in_zone !== decision.inZone) {
      update(sub.id, { in_zone: decision.inZone, last_value: Math.round(reading.aqi) })
    }
  }

  if (dryRun) return result

  // Re-arms and skipped crossings first, so they're saved even if sending
  // runs out of budget later.
  await saveUpdates()

  // A run sends at most this many; the rest stay unsent (in_zone false) and
  // go out on the next run. Keeps every run inside the Worker's subrequest
  // limit, so state is always written for what was sent: no repeat alerts.
  const maxSends = Number(env.MAX_SENDS_PER_RUN ?? 45000)
  const deferred = toSend.splice(maxSends)
  if (deferred.length) {
    result.counts.deferred = deferred.length
    console.warn('sends deferred to the next run', deferred.length)
  }

  const dead = new Set<number>()
  for (let i = 0; i < toSend.length; i += SAVE_EVERY) {
    const logs: PushLog[] = []
    const chunk = toSend.slice(i, i + SAVE_EVERY)
    await pool(chunk, SEND_CONCURRENCY, async ({ sub, reading }) => {
      if (dead.has(sub.device.id)) return
      logs.push(await sendOne(sub, reading))
    })
    // Saved per chunk: what was sent is marked sent before the next chunk.
    const newlyDead = [...dead].filter((id) => !result.archivedDevices.includes(id))
    await archiveDevices(env, newlyDead)
    result.archivedDevices.push(...newlyDead)
    await saveUpdates()
    const written = await logQuietly(env, logs)
    result.logged += written.rows
    result.events += written.events
  }
  return result

  async function saveUpdates() {
    const changed = [...updates.values()].filter((u) => Object.keys(u).length > 1)
    updates.clear()
    await updateSubscriptions(env, changed)
    result.updated += changed.length
  }

  async function sendOne(sub: Subscription, reading: Reading): Promise<PushLog> {
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
        update(sub.id, { in_zone: true, last_fired_at: now.toISOString(), last_value: Math.round(reading.aqi) })
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
    return log
  }
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

/** Every send goes to Analytics Engine (cheap, kept ~3 months); only the
 * ones worth a row of their own reach Directus: failures, dead tokens and
 * tests. At 40k alerts a run, a Directus row per send would be ~14M rows a
 * month. Never throws. */
export async function logQuietly(env: Env, logs: PushLog[]): Promise<{ rows: number; events: number }> {
  if (!logs.length) return { rows: 0, events: 0 }
  let events = 0
  if (env.PUSH_EVENTS) {
    for (const log of logs) {
      try {
        env.PUSH_EVENTS.writeDataPoint({
          indexes: [log.station ?? ''],
          blobs: [log.status, log.trigger, log.station ?? '', log.error_code ?? '', log.token_suffix, String(log.device)],
          doubles: [log.aqi ?? 0],
        })
        events++
      } catch (e) {
        console.warn('push event write failed', String(e))
      }
    }
  }
  const rows = logs.filter((log) => log.status !== 'sent' || log.trigger === 'test')
  if (!rows.length) return { rows: 0, events }
  try {
    await writeLogs(env, rows)
    return { rows: rows.length, events }
  } catch (e) {
    console.warn('push log write failed', String(e))
    return { rows: 0, events }
  }
}

/** Runs `work` over `items`, at most `limit` at a time. */
async function pool<T>(items: T[], limit: number, work: (item: T) => Promise<void>): Promise<void> {
  let next = 0
  const lanes = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) await work(items[next++])
  })
  await Promise.all(lanes)
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
