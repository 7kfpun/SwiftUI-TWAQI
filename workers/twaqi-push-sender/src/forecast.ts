// Tomorrow's forecast heads-up (FOX-191). One push per device, in the evening
// Taiwan time, when tomorrow's 空品區 forecast for a zone the device has an
// alert on reaches the level and is worse than today's. Pure rules first
// (testable with `node --test`), then runForecast(), which the GitHub Actions
// run calls after run() (scripts/run.ts).
import { allReadings } from './aqi.ts'
import {
  archiveDevices,
  forecastRows,
  lastAlerts,
  markForecastSent,
  stationSubscriptions,
  tokenSuffix,
  type ForecastRow,
  type PushLog,
  type Subscription,
} from './directus.ts'
import { send } from './fcm.ts'
import { logQuietly, type Env } from './index.ts'
import { isChinese } from './message.ts'
import { isQuiet } from './rules.ts'

/** Tomorrow's forecast must be above this AQI (unhealthy for sensitive groups
 * starts at 101). A per-device level arrives with the settings (FOX-192). */
export const DEFAULT_LEVEL = 100
/** The heads-up goes out from 18:00 to 21:59 Taiwan time. The job runs every
 * two hours, so this covers the 18:20 run and, if it was late, skipped or
 * failed, the 20:20 one. */
export const WINDOW_START_HOUR = 18
export const WINDOW_END_HOUR = 22
const EXPIRY_SECONDS = 3 * 60 * 60
const ZONE_WORDS = /空品區|空品|地區|\s/g

export interface ZoneForecast {
  /** MOENV's short area name, "北部". */
  area: string
  aqi: number
  pollutant: string | null
}

/** Taiwan calendar day (`YYYY-MM-DD`) and hour of `now`. */
export function taipei(now: Date): { day: string; hour: number } {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Taipei', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23',
  }).formatToParts(now)
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00'
  return { day: `${get('year')}-${get('month')}-${get('day')}`, hour: Number(get('hour')) }
}

export function nextDay(day: string): string {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10)
}

export function inWindow(now: Date): boolean {
  const { hour } = taipei(now)
  return hour >= WINDOW_START_HOUR && hour < WINDOW_END_HOUR
}

const fold = (name: string) => name.replace(/臺/g, '台').replace(ZONE_WORDS, '')

/** The forecast area a station belongs to (the app's AqiForecastMatcher): by
 * its 空品區 name, else by county for the outlying islands. */
export function matchArea(areaZh: string | null | undefined, countyZh: string | null | undefined, areas: string[]): string | null {
  const byKey = new Map(areas.map((a) => [fold(a), a]))
  const key = fold(areaZh ?? '')
  if (key) {
    const exact = byKey.get(key)
    if (exact) return exact
    for (const [k, v] of byKey) if (key.startsWith(k) || k.startsWith(key)) return v
  }
  const county = fold(countyZh ?? '')
  for (const [needle, area] of [['連江', '馬祖'], ['金門', '金門'], ['澎湖', '澎湖']]) {
    if (county.includes(needle)) return byKey.get(area) ?? null
  }
  return null
}

/** Per area, the newest-published row for each of the two days. */
export function pickDays(rows: ForecastRow[], today: string, tomorrow: string): Map<string, { today?: ForecastRow; tomorrow?: ForecastRow }> {
  const out = new Map<string, { today?: ForecastRow; tomorrow?: ForecastRow }>()
  for (const row of rows) {
    const key = row.forecast_date === today ? 'today' : row.forecast_date === tomorrow ? 'tomorrow' : null
    if (!key) continue
    const entry = out.get(row.area) ?? {}
    const have = entry[key]
    if (!have || (row.publish_time ?? '') > (have.publish_time ?? '')) entry[key] = row
    out.set(row.area, entry)
  }
  return out
}

/** Areas where tomorrow is above `level` and worse than today. A missing
 * today (or tomorrow) AQI can't be compared, so it sends nothing. */
export function badTomorrow(days: ReturnType<typeof pickDays>, level = DEFAULT_LEVEL): Map<string, ZoneForecast> {
  const out = new Map<string, ZoneForecast>()
  for (const [area, { today, tomorrow }] of days) {
    if (typeof tomorrow?.aqi !== 'number' || typeof today?.aqi !== 'number') continue
    if (tomorrow.aqi > level && tomorrow.aqi > today.aqi) {
      out.set(area, { area, aqi: tomorrow.aqi, pollutant: cleanPollutant(tomorrow.major_pollutant) })
    }
  }
  return out
}

function cleanPollutant(raw: string | null | undefined): string | null {
  const value = (raw ?? '').trim()
  return value && value !== '-' ? value : null
}

/** Whether the AQI cool-down may hold the heads-up back at `now`: only while a
 * later scheduled run (two hours on) still falls inside the window. The last
 * run of the window sends regardless, so an alert from the same run, or from
 * just before, can't cost the day's heads-up. */
export function holdApplies(now: Date): boolean {
  const { hour } = taipei(now)
  const minutes = hour * 60 + Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Taipei', minute: '2-digit' }).format(now))
  return minutes + 120 < WINDOW_END_HOUR * 60
}

export type ForecastOutcome = 'fire' | 'quiet' | 'cooldown' | 'already-sent' | 'unchanged'

/** Whether a device gets its heads-up now. Quiet hours drop it for this run
 * (a later run in the window may still send it); one per Taiwan day; and not
 * again for a forecast that says the same thing. A recent AQI alert
 * (within COOLDOWN_MINUTES) holds it back too, except on the window's last run. */
export function decideForecast(input: {
  quiet: boolean
  lastSentAt: string | null | undefined
  lastDigest: string | null | undefined
  digest: string
  now: Date
  /** The device's latest AQI alert (max `last_fired_at` of its subscriptions). */
  lastAlertAt?: string | null
  cooldownMinutes?: number
}): ForecastOutcome {
  if (input.quiet) return 'quiet'
  // The AQI alerts' cool-down: not right after one. Unmarked, so a later run in the window retries.
  const alert = input.lastAlertAt ? Date.parse(input.lastAlertAt) : NaN
  if (holdApplies(input.now) && Number.isFinite(alert) && input.now.getTime() - alert < (input.cooldownMinutes ?? 180) * 60_000) return 'cooldown'
  const last = input.lastSentAt ? new Date(input.lastSentAt) : null
  if (last && Number.isFinite(last.getTime()) && taipei(last).day === taipei(input.now).day) return 'already-sent'
  if (input.lastDigest && input.lastDigest === input.digest) return 'unchanged'
  return 'fire'
}

/** What the push says, as a stable string: the day and each zone's AQI and
 * pollutant, hashed to fit a Directus string field. */
export async function forecastDigest(day: string, zones: ZoneForecast[]): Promise<string> {
  const text = [day, ...[...zones].sort((a, b) => a.area.localeCompare(b.area)).map((z) => `${z.area}:${z.aqi}:${z.pollutant ?? ''}`)].join('|')
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(hash)].slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('')
}

const ENGLISH_AREAS: Record<string, string> = {
  北部: 'North', 竹苗: 'Chu-Miao', 中部: 'Central', 雲嘉南: 'Yun-Chia-Nan', 高屏: 'Kao-Ping',
  宜蘭: 'Yilan', 花東: 'Hua-Tung', 澎湖: 'Penghu', 金門: 'Kinmen', 馬祖: 'Matsu',
}
const ISLANDS = new Set(['澎湖', '金門', '馬祖'])
const POLLUTANTS: Array<[string, string]> = [
  ['細懸浮微粒', 'PM2.5'], ['懸浮微粒', 'PM10'], ['臭氧', 'O₃'], ['二氧化氮', 'NO₂'], ['二氧化硫', 'SO₂'], ['一氧化碳', 'CO'],
]

function zoneName(area: string, chinese: boolean): string {
  const key = fold(area)
  if (chinese) return ISLANDS.has(key) ? key : `${key}空品區`
  return ENGLISH_AREAS[key] ?? area
}

function pollutantName(raw: string | null, chinese: boolean): string | null {
  if (!raw) return null
  return chinese ? raw : POLLUTANTS.find(([zh]) => raw.includes(zh))?.[1] ?? raw
}

function levelName(aqi: number, chinese: boolean): string {
  const i = aqi > 300 ? 3 : aqi > 200 ? 2 : aqi > 150 ? 1 : 0
  return (chinese
    ? ['對敏感族群不健康', '對所有族群不健康', '非常不健康', '危害']
    : ['unhealthy for sensitive groups', 'unhealthy', 'very unhealthy', 'hazardous'])[i]
}

/** The heads-up, in the app's language. One zone names it in the title; several
 * list each in the body. `day` is tomorrow, `YYYY-MM-DD`. */
export function forecastText(locale: string | null | undefined, day: string, zones: ZoneForecast[]): { title: string; body: string } {
  const chinese = isChinese(locale)
  const sorted = [...zones].sort((a, b) => b.aqi - a.aqi || a.area.localeCompare(b.area))
  const date = chinese ? `${Number(day.slice(5, 7))}/${Number(day.slice(8, 10))}` : day.slice(5).replace('-', '/')
  const line = (z: ZoneForecast) => {
    const pollutant = pollutantName(z.pollutant, chinese)
    return chinese
      ? `${zoneName(z.area, true)}預報 AQI ${z.aqi}（${levelName(z.aqi, true)}）${pollutant ? `，主要污染物 ${pollutant}` : ''}`
      : `${zoneName(z.area, false)}: AQI ${z.aqi}, ${levelName(z.aqi, false)}${pollutant ? `, mainly ${pollutant}` : ''}`
  }
  if (sorted.length === 1) {
    const z = sorted[0]
    const pollutant = pollutantName(z.pollutant, chinese)
    return chinese
      ? { title: `明天 ${zoneName(z.area, true)} 空氣品質不佳`, body: `${date} 預報 AQI ${z.aqi}（${levelName(z.aqi, true)}）${pollutant ? `，主要污染物 ${pollutant}` : ''}，外出請留意。` }
      : { title: `Poor air expected tomorrow: ${zoneName(z.area, false)}`, body: `Forecast for ${date}: AQI ${z.aqi}, ${levelName(z.aqi, false)}${pollutant ? `, mainly ${pollutant}` : ''}. Plan outdoor time with care.` }
  }
  return chinese
    ? { title: `明天 ${sorted.length} 個空品區空氣品質不佳`, body: `${date} 預報：${sorted.map(line).join('；')}。` }
    : { title: `Poor air expected tomorrow in ${sorted.length} zones`, body: `Forecast for ${date}: ${sorted.map(line).join('; ')}.` }
}

export interface ForecastResult {
  /** Why nothing was looked at, when that is so. */
  skipped?: 'window' | 'fine'
  /** Zones forecast above the level and worse than today. */
  zones: number
  devices: number
  counts: Partial<Record<ForecastOutcome | 'sent' | 'failed' | 'dead-token', number>>
  logged: number
  events: number
  dryRun: boolean
}

/** The evening heads-up. Reads the forecast first and the subscriptions only
 * when some zone qualifies, so a fine forecast costs one request. State
 * (`forecast_sent_at`, `forecast_digest` on the device) is saved after every
 * hundred sends; a failed send leaves it alone so the next run in the window
 * retries. */
export async function runForecast(env: Env, options: { now?: Date; dryRun?: boolean } = {}): Promise<ForecastResult> {
  const now = options.now ?? new Date()
  const dryRun = options.dryRun ?? false
  const result: ForecastResult = { zones: 0, devices: 0, counts: {}, logged: 0, events: 0, dryRun }
  const count = (key: keyof ForecastResult['counts']) => (result.counts[key] = (result.counts[key] ?? 0) + 1)
  if (!inWindow(now)) return { ...result, skipped: 'window' }

  const { day: today } = taipei(now)
  const tomorrow = nextDay(today)
  const days = pickDays(await forecastRows(env, [today, tomorrow]), today, tomorrow)
  const bad = badTomorrow(days)
  result.zones = bad.size
  if (!bad.size) return { ...result, skipped: 'fine' }

  // Stations in a qualifying zone, by their own 空品區.
  const areas = [...days.keys()]
  const zoneOf = new Map<number, string>()
  for (const reading of (await allReadings(env)).values()) {
    const area = matchArea(reading.areaZh, reading.countyZh, areas)
    if (area && bad.has(area)) zoneOf.set(reading.stationId, area)
  }
  const subs = zoneOf.size ? await stationSubscriptions(env, [...zoneOf.keys()]) : []

  // One push per device, covering every qualifying zone it has a favourite in.
  const byDevice = new Map<number, { device: Subscription['device']; zones: Map<string, ZoneForecast>; station: number }>()
  for (const sub of subs) {
    const area = sub.station_id === null ? undefined : zoneOf.get(sub.station_id)
    if (!area || sub.station_id === null) continue
    const entry = byDevice.get(sub.device.id) ?? { device: sub.device, zones: new Map(), station: sub.station_id }
    entry.zones.set(area, bad.get(area) as ZoneForecast)
    byDevice.set(sub.device.id, entry)
  }
  result.devices = byDevice.size

  // Every alert the device has fired, at any station, counts for the cool-down
  // (read for all its subscriptions, not just those in a qualifying zone).
  const lastAlert = holdApplies(now) && byDevice.size ? await lastAlerts(env, [...byDevice.keys()]) : new Map<number, string>()
  const toSend: Array<{ id: number; device: Subscription['device']; zones: ZoneForecast[]; station: number; digest: string }> = []
  for (const [id, { device, zones, station }] of byDevice) {
    const list = [...zones.values()]
    const digest = await forecastDigest(tomorrow, list)
    const outcome = decideForecast({ quiet: isQuiet(device, now), lastSentAt: device.forecast_sent_at, lastDigest: device.forecast_digest, digest, now, lastAlertAt: lastAlert.get(id), cooldownMinutes: Number(env.COOLDOWN_MINUTES ?? 180) })
    count(outcome)
    if (outcome === 'fire') toSend.push({ id, device, zones: list, station, digest })
  }
  if (dryRun) return result

  for (let i = 0; i < toSend.length; i += 100) {
    const logs: PushLog[] = []
    const marks: Array<{ id: number; forecast_sent_at: string; forecast_digest: string }> = []
    const dead: number[] = []
    await Promise.all(toSend.slice(i, i + 100).map(async ({ id, device, zones, station, digest }) => {
      const token = device.fcm_token as string
      const log: PushLog = {
        token_suffix: tokenSuffix(token), status: 'failed', station: String(station), trigger: 'forecast',
        device: id, aqi: Math.max(...zones.map((z) => z.aqi)), fcm_message_id: null, error_code: null,
      }
      try {
        const res = await send(env, {
          token,
          ...forecastText(device.locale, tomorrow, zones),
          data: { type: 'forecast', forecast_date: tomorrow, areas: zones.map((z) => z.area).sort().join(',') },
          collapseId: `forecast-${id}`,
          threadId: 'forecast',
          expiresInSeconds: EXPIRY_SECONDS,
        })
        if (res.ok) {
          count('sent')
          log.status = 'sent'
          log.fcm_message_id = res.messageId ?? null
          marks.push({ id, forecast_sent_at: now.toISOString(), forecast_digest: digest })
        } else if (res.deadToken) {
          count('dead-token')
          log.status = 'unregistered'
          log.error_code = res.errorCode ?? null
          dead.push(id)
        } else {
          count('failed')
          log.error_code = res.errorCode ?? `HTTP_${res.status}`
        }
      } catch (e) {
        count('failed')
        log.error_code = 'EXCEPTION'
        console.warn('forecast fcm error', id, String(e))
      }
      logs.push(log)
    }))
    // Saved per chunk, retried, before the next chunk: what went out is marked.
    await archiveDevices(env, dead)
    for (let attempt = 1; ; attempt++) {
      try {
        await markForecastSent(env, marks)
        break
      } catch (e) {
        if (attempt >= 3) throw e
        await new Promise((resolve) => setTimeout(resolve, 1000 * attempt * attempt))
      }
    }
    const written = await logQuietly(env, logs)
    result.logged += written.rows
    result.events += written.events
  }
  return result
}
