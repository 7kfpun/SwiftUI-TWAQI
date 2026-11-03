// Directus REST for the two push collections. Rows are never deleted:
// a dead device gets archived=true (the app sets it back to false the next
// time it writes its row).

import type { Direction } from './rules.ts'

export interface DirectusConfig {
  DIRECTUS_URL: string
  /** Static token of the TWAQI Push Worker user. */
  DIRECTUS_PUSH_TOKEN: string
}

export interface Device {
  id: number
  /** What FCM addresses. Builds before FOX-13 have none: OneSignal serves them. */
  fcm_token: string | null
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

const DEVICE_FIELDS = ['id', 'fcm_token', 'locale', 'dnd_enabled', 'dnd_start', 'dnd_end', 'timezone']
const SUBSCRIPTION_FIELDS = [
  'id', 'station_id', 'site_id', 'metric', 'direction', 'threshold', 'last_value', 'in_zone', 'last_fired_at',
  ...DEVICE_FIELDS.map((f) => `device.${f}`),
]
const PAGE_SIZE = 500
/** Stations per request: keeps the filter, sent in the URL, a few KB. */
const STATIONS_PER_REQUEST = 10

type Filter = Record<string, unknown>

const notInZone: Filter = { _or: [{ in_zone: { _eq: false } }, { in_zone: { _null: true } }] }

/** Live subscriptions on devices FCM can reach. */
const LIVE: Filter[] = [
  { enabled: { _eq: true } },
  { archived: { _eq: false } },
  { _or: [{ metric: { _eq: 'aqi' } }, { metric: { _null: true } }] },
  { device: { archived: { _eq: false } } },
  { device: { fcm_token: { _nnull: true } } },
]

/** The Directus filter for the subscriptions whose zone changes at these
 * readings, and only those: at AQI `a`, an "above" one is in its zone when
 * threshold ≤ a, a "below" one when threshold ≥ a (inclusive, see isInZone).
 * A row comes back when that disagrees with its stored `in_zone`, so a run
 * reads only alerts to send and alerts to re-arm, never the rest. */
export function crossingFilter(readings: Array<{ stationId: number; aqi: number }>): Filter {
  const aqiOf = (r: { aqi: number }) => Math.round(r.aqi)
  const station = (r: { stationId: number; aqi: number }): Filter => ({
    _and: [
      { station_id: { _eq: String(r.stationId) } },
      {
        _or: [
          {
            _and: [
              { direction: { _eq: 'above' } },
              {
                _or: [
                  { _and: [{ threshold: { _lte: aqiOf(r) } }, notInZone] },
                  { _and: [{ threshold: { _gt: aqiOf(r) } }, { in_zone: { _eq: true } }] },
                ],
              },
            ],
          },
          {
            _and: [
              { direction: { _eq: 'below' } },
              {
                _or: [
                  { _and: [{ threshold: { _gte: aqiOf(r) } }, notInZone] },
                  { _and: [{ threshold: { _lt: aqiOf(r) } }, { in_zone: { _eq: true } }] },
                ],
              },
            ],
          },
        ],
      },
    ],
  })
  return { _and: [...LIVE, { _or: readings.map(station) }] }
}

/** Subscriptions whose zone changed at these readings (see `crossingFilter`),
 * with their device. Ten stations per request, paged. */
export async function crossingSubscriptions(
  env: DirectusConfig,
  readings: Array<{ stationId: number; aqi: number }>,
): Promise<Subscription[]> {
  const all: Subscription[] = []
  for (let i = 0; i < readings.length; i += STATIONS_PER_REQUEST) {
    const filter = JSON.stringify(crossingFilter(readings.slice(i, i + STATIONS_PER_REQUEST)))
    for (let page = 1; ; page++) {
      const params = new URLSearchParams({
        fields: SUBSCRIPTION_FIELDS.join(','),
        filter,
        sort: 'id',
        limit: String(PAGE_SIZE),
        page: String(page),
      })
      const { data } = await request<{ data: Subscription[] }>(env, 'GET', `/items/twaqi_push_subscriptions?${params}`)
      // A device the token can't read comes back as null; nothing to send to.
      for (const s of data) {
        if (!s.device?.fcm_token) continue
        const stationId = Number(s.station_id)
        all.push({ ...s, station_id: s.station_id != null && Number.isInteger(stationId) ? stationId : null })
      }
      if (data.length < PAGE_SIZE) break
    }
  }
  return all
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

/** FCM said the token is dead. Its subscriptions stop matching because the
 * subscription query requires an unarchived device. */
export async function archiveDevices(env: DirectusConfig, ids: number[]): Promise<void> {
  if (!ids.length) return
  await request(env, 'PATCH', '/items/twaqi_push_devices?fields=id', { keys: ids, data: { archived: true } })
}

/** One row in `twaqi_push_logs` (FOX-66): a send attempt, never the full token. */
export interface PushLog {
  token_suffix: string
  status: 'sent' | 'failed' | 'unregistered'
  /** AQI API station id, as a string like `twaqi_push_subscriptions.station_id`. */
  station: string | null
  /** `pollution` (an "above" alert), `cleanliness` ("below") or `test`. */
  trigger: 'pollution' | 'cleanliness' | 'test'
  device: number
  aqi: number | null
  fcm_message_id: string | null
  error_code: string | null
}

/** The last few characters of an FCM token: enough to tell rows apart,
 * useless for sending. */
export function tokenSuffix(token: string, length = 6): string {
  return token.slice(-length)
}

/** Best effort: a log that can't be written never holds up or undoes a send. */
export async function writeLogs(env: DirectusConfig, logs: PushLog[]): Promise<void> {
  for (let i = 0; i < logs.length; i += 100) {
    const rows = logs.slice(i, i + 100).map((log) => ({ ...log, archived: false }))
    await request(env, 'POST', '/items/twaqi_push_logs?fields=id', rows)
  }
}

export class DirectusError extends Error {
  // A plain field, not a parameter property: node --test only strips types.
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

/** Directus REST with the push worker's token. `path` starts with `/`. */
export async function request<T = unknown>(env: DirectusConfig, method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${env.DIRECTUS_URL.replace(/\/+$/, '')}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${env.DIRECTUS_PUSH_TOKEN}`,
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
