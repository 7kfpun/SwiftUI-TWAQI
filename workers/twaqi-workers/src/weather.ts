// CWA weather sync (FOX-11): two Central Weather Administration open-data sets
// -> one compact R2 object, `weather/latest.json`, served from the webcam host
// like the cam manifest.
//
//   F-C0032-001  county (縣市) 36-hour forecast: Wx, PoP, MinT, MaxT per 12 h period
//   O-A0003-001  observations from CWA's staffed stations: temperature,
//                humidity, rain since midnight, wind, observation time
//
// Each set is fetched and parsed on its own. A set that fails (HTTP error,
// non-JSON body, nothing usable) keeps its section from the last good file;
// the file is written only when at least one set is new. Nothing is deleted.
//
// Only the fields the app shows are kept. Free text (the Wx description and
// station names) stays zh-Hant as CWA publishes it; the app maps the Wx code
// to its own strings for English. Self-contained (no imports) so `node --test`
// can load it directly.

export interface WeatherEnv {
  CAMS: R2Bucket
  /** CWA open-data 授權碼. Server-side only; never sent to the app. */
  CWA_API_KEY: string
  /** Local testing only: base URL standing in for CWA's datastore API. */
  CWA_API_BASE?: string
}

export const WEATHER_KEY = 'weather/latest.json'
export const WEATHER_STATUS_KEY = 'weather/last-sync.json'
/** CWA refreshes observations every 10 minutes and the forecast every 6 hours; the app re-reads at most every 30 min. */
export const WEATHER_CACHE_CONTROL = 'public, max-age=300'

const CWA_API = 'https://opendata.cwa.gov.tw/api/v1/rest/datastore'
export const FORECAST_DATASET = 'F-C0032-001'
export const OBSERVATION_DATASET = 'O-A0003-001'

/**
 * CWA's forecast weather codes (預報產品天氣描述代碼表, 2018-12-20): 1–42, no 40.
 * The app maps each to its own strings and SF Symbol; a code outside this
 * table is still stored, and counted in the sync status so a new one is noticed.
 */
export const WX_CODES: ReadonlySet<number> = new Set([
  ...Array.from({ length: 39 }, (_, i) => i + 1),
  41,
  42,
])

/** One 12-hour (or shorter, for the first) forecast period. */
export interface ForecastPeriod {
  /** ISO 8601 with the Taiwan offset, e.g. `2026-11-05T18:00:00+08:00`. */
  start: string
  end: string
  /** CWA weather code (Wx parameterValue), null if absent. */
  wx: number | null
  /** CWA's own description (Wx parameterName), zh-Hant. */
  text: string | null
  /** Chance of rain, %. */
  pop: number | null
  minT: number | null
  maxT: number | null
}

export interface Observation {
  /** CWA station id, e.g. `466920`. Not a MOENV SiteId. */
  id: string
  /** zh-Hant, e.g. `臺北`. */
  name: string
  /** zh-Hant county, e.g. `臺北市`. */
  county: string | null
  /** WGS84. */
  lat: number
  lon: number
  /** ISO 8601 with offset, as CWA publishes it. */
  time: string
  /** °C */
  temp: number | null
  /** % */
  humidity: number | null
  /** mm since local midnight. */
  rain: number | null
  /** m/s, 10-minute mean. */
  wind: number | null
}

export interface WeatherFile {
  version: 1
  /** When this file was written (UTC). */
  updatedAt: string
  forecast: {
    /** When the forecast section was last refreshed (UTC). */
    fetchedAt: string
    /** County name (zh-Hant, 臺 not 台) -> its periods, oldest first. */
    counties: Record<string, ForecastPeriod[]>
  } | null
  observations: {
    fetchedAt: string
    stations: Observation[]
  } | null
}

export interface WeatherSyncResult {
  forecast: 'updated' | 'kept' | 'missing'
  observations: 'updated' | 'kept' | 'missing'
  counties: number
  stations: number
  /** Wx codes outside `WX_CODES`, if any. */
  unknownWx: number[]
  /** Why a set was not updated. */
  forecastError?: string
  observationsError?: string
}

// MARK: - Sync

export async function syncWeather(env: WeatherEnv, now: Date = new Date(), fetchImpl: typeof fetch = fetch): Promise<WeatherSyncResult> {
  if (!env.CWA_API_KEY) throw new Error('CWA_API_KEY is not set')

  const [forecastRaw, observationsRaw] = await Promise.allSettled([
    fetchDataset(env, FORECAST_DATASET, fetchImpl),
    fetchDataset(env, OBSERVATION_DATASET, fetchImpl),
  ])

  const forecast = forecastRaw.status === 'fulfilled' ? safely(() => parseForecast(forecastRaw.value)) : { error: errorText(forecastRaw.reason) }
  const observations = observationsRaw.status === 'fulfilled' ? safely(() => parseObservations(observationsRaw.value)) : { error: errorText(observationsRaw.reason) }

  const prev = await readWeather(env)
  const { file, result } = mergeWeather(prev, forecast, observations, now)

  if (result.forecast === 'updated' || result.observations === 'updated') {
    await env.CAMS.put(WEATHER_KEY, JSON.stringify(file), {
      httpMetadata: { contentType: 'application/json; charset=utf-8', cacheControl: WEATHER_CACHE_CONTROL },
    })
  } else {
    // Both sets failed: the last good file stays as it is.
    throw new Error(`CWA weather: nothing usable (forecast: ${result.forecastError}; observations: ${result.observationsError})`)
  }
  return result
}

type Parsed<T> = { value: T } | { error: string }

function safely<T>(run: () => T): Parsed<T> {
  try {
    return { value: run() }
  } catch (e) {
    return { error: errorText(e) }
  }
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e)
}

/**
 * Builds the next file from the last good one and this run's parses. A set that
 * failed keeps its previous section; one that never succeeded is null.
 */
export function mergeWeather(
  prev: WeatherFile | null,
  forecast: Parsed<Record<string, ForecastPeriod[]>>,
  observations: Parsed<Observation[]>,
  now: Date,
): { file: WeatherFile; result: WeatherSyncResult } {
  const at = now.toISOString()
  const file: WeatherFile = {
    version: 1,
    updatedAt: at,
    forecast: 'value' in forecast ? { fetchedAt: at, counties: forecast.value } : prev?.forecast ?? null,
    observations: 'value' in observations ? { fetchedAt: at, stations: observations.value } : prev?.observations ?? null,
  }
  const result: WeatherSyncResult = {
    forecast: 'value' in forecast ? 'updated' : file.forecast ? 'kept' : 'missing',
    observations: 'value' in observations ? 'updated' : file.observations ? 'kept' : 'missing',
    counties: Object.keys(file.forecast?.counties ?? {}).length,
    stations: file.observations?.stations.length ?? 0,
    unknownWx: 'value' in forecast ? unknownWxCodes(forecast.value) : [],
  }
  if ('error' in forecast) result.forecastError = forecast.error
  if ('error' in observations) result.observationsError = observations.error
  return { file, result }
}

export function unknownWxCodes(counties: Record<string, ForecastPeriod[]>): number[] {
  const unknown = new Set<number>()
  for (const periods of Object.values(counties)) {
    for (const p of periods) if (p.wx !== null && !WX_CODES.has(p.wx)) unknown.add(p.wx)
  }
  return [...unknown].sort((a, b) => a - b)
}

async function fetchDataset(env: WeatherEnv, dataset: string, fetchImpl: typeof fetch): Promise<unknown> {
  const base = env.CWA_API_BASE || CWA_API
  // The key goes in the query string, as CWA documents it. The URL is never logged.
  const url = `${base}/${dataset}?format=JSON&Authorization=${encodeURIComponent(env.CWA_API_KEY)}`
  const res = await fetchImpl(url, { headers: { Accept: 'application/json' } })
  if (!res.ok) throw new Error(`${dataset} HTTP ${res.status}`)
  const text = await res.text()
  let body: unknown
  try {
    body = JSON.parse(text)
  } catch {
    throw new Error(`${dataset} answered with a non-JSON body`)
  }
  const success = (body as { success?: unknown })?.success
  if (success !== true && success !== 'true') throw new Error(`${dataset} answered success=${String(success)}`)
  return body
}

async function readWeather(env: WeatherEnv): Promise<WeatherFile | null> {
  try {
    const obj = await env.CAMS.get(WEATHER_KEY)
    if (!obj) return null
    const file = (await obj.json()) as WeatherFile
    return file?.version === 1 ? file : null
  } catch (e) {
    console.error('weather: last file unreadable', e)
    return null
  }
}

// MARK: - F-C0032-001

/**
 * `records.location[]` -> county -> periods. Throws when nothing usable is in
 * the body, so the caller keeps the last good forecast.
 *
 *   { records: { location: [ { locationName: "臺北市", weatherElement: [
 *       { elementName: "Wx", time: [ { startTime: "2026-11-05 18:00:00", endTime: "2026-11-06 06:00:00",
 *           parameter: { parameterName: "多雲", parameterValue: "4" } }, … ] },
 *       { elementName: "PoP", time: [ { …, parameter: { parameterName: "20", parameterUnit: "百分比" } } ] },
 *       { elementName: "MinT", … }, { elementName: "MaxT", … }, { elementName: "CI", … } ] } ] } }
 */
export function parseForecast(body: unknown): Record<string, ForecastPeriod[]> {
  const records = (body as { records?: Record<string, unknown> })?.records
  const locations = asArray(records?.location ?? records?.Location)
  const counties: Record<string, ForecastPeriod[]> = {}

  for (const location of locations) {
    const name = countyName(str(get(location, 'locationName', 'LocationName')))
    if (!name) continue
    const elements = asArray(get(location, 'weatherElement', 'WeatherElement'))
    const byElement = new Map<string, unknown[]>()
    for (const element of elements) {
      const elementName = str(get(element, 'elementName', 'ElementName'))
      if (elementName) byElement.set(elementName, asArray(get(element, 'time', 'Time')))
    }

    // Periods are keyed by start time; Wx defines which periods exist.
    const periods = new Map<string, ForecastPeriod>()
    for (const slot of byElement.get('Wx') ?? []) {
      const start = taiwanIso(str(get(slot, 'startTime', 'StartTime')))
      const end = taiwanIso(str(get(slot, 'endTime', 'EndTime')))
      if (!start || !end) continue
      const parameter = get(slot, 'parameter', 'Parameter')
      periods.set(start, {
        start,
        end,
        wx: int(get(parameter, 'parameterValue', 'ParameterValue')),
        text: str(get(parameter, 'parameterName', 'ParameterName')),
        pop: null,
        minT: null,
        maxT: null,
      })
    }

    const fill = (elementName: string, field: 'pop' | 'minT' | 'maxT', valid: (n: number) => boolean) => {
      for (const slot of byElement.get(elementName) ?? []) {
        const start = taiwanIso(str(get(slot, 'startTime', 'StartTime')))
        const period = start ? periods.get(start) : undefined
        if (!period) continue
        const n = num(get(get(slot, 'parameter', 'Parameter'), 'parameterName', 'ParameterName'))
        period[field] = n !== null && valid(n) ? n : null
      }
    }
    fill('PoP', 'pop', (n) => n >= 0 && n <= 100)
    fill('MinT', 'minT', plausibleTemp)
    fill('MaxT', 'maxT', plausibleTemp)

    const list = [...periods.values()].sort((a, b) => a.start.localeCompare(b.start))
    if (list.length > 0) counties[name] = list
  }

  if (Object.keys(counties).length === 0) throw new Error(`${FORECAST_DATASET} had no usable county forecast`)
  return counties
}

// MARK: - O-A0003-001

/**
 * `records.Station[]` -> observations with WGS84 coordinates. Throws when no
 * station is usable. CWA marks a missing reading with -99 / -990 / -999 and
 * the like; those become null, and a station with no reading left is dropped.
 *
 *   { records: { Station: [ { StationName: "臺北", StationId: "466920",
 *       ObsTime: { DateTime: "2026-11-05T12:00:00+08:00" },
 *       GeoInfo: { CountyName: "臺北市", Coordinates: [ { CoordinateName: "TWD67", … },
 *         { CoordinateName: "WGS84", StationLatitude: 25.037658, StationLongitude: 121.514853 } ] },
 *       WeatherElement: { AirTemperature: 24.3, RelativeHumidity: 75, Now: { Precipitation: 0.5 },
 *         WindSpeed: 3.2, … } } ] } }
 */
export function parseObservations(body: unknown): Observation[] {
  const records = (body as { records?: Record<string, unknown> })?.records
  const stations = asArray(records?.Station ?? records?.station)
  const out: Observation[] = []

  for (const station of stations) {
    const id = str(get(station, 'StationId', 'stationId'))
    const name = str(get(station, 'StationName', 'stationName'))
    const time = str(get(get(station, 'ObsTime', 'obsTime'), 'DateTime', 'dateTime'))
    if (!id || !name || !time || Number.isNaN(Date.parse(time))) continue

    const geo = get(station, 'GeoInfo', 'geoInfo')
    const coordinates = asArray(get(geo, 'Coordinates', 'coordinates'))
    const wgs84 = coordinates.find((c) => str(get(c, 'CoordinateName', 'coordinateName')) === 'WGS84') ?? coordinates[coordinates.length - 1]
    const lat = num(get(wgs84, 'StationLatitude', 'stationLatitude'))
    const lon = num(get(wgs84, 'StationLongitude', 'stationLongitude'))
    // Taiwan and its outlying islands (Kinmen, Matsu, Pratas, Penghu): anything else is a bad row.
    if (lat === null || lon === null || lat < 20 || lat > 27 || lon < 116 || lon > 123) continue

    const element = get(station, 'WeatherElement', 'weatherElement')
    const temp = valid(num(get(element, 'AirTemperature', 'airTemperature')), plausibleTemp)
    let humidity = valid(num(get(element, 'RelativeHumidity', 'relativeHumidity')), (n) => n >= 0 && n <= 100)
    // Older CWA formats sent humidity as a fraction (0.75). A real reading of
    // 1% or less never happens in Taiwan, so (0, 1] is read as a fraction.
    if (humidity !== null && humidity > 0 && humidity <= 1) humidity = Math.round(humidity * 100)
    const rain = valid(num(get(get(element, 'Now', 'now'), 'Precipitation', 'precipitation')), (n) => n >= 0 && n < 3000)
    const wind = valid(num(get(element, 'WindSpeed', 'windSpeed')), (n) => n >= 0 && n < 100)
    if (temp === null && humidity === null && rain === null && wind === null) continue

    out.push({
      id,
      name,
      county: countyName(str(get(geo, 'CountyName', 'countyName'))),
      lat: round(lat, 5),
      lon: round(lon, 5),
      time,
      temp,
      humidity,
      rain,
      wind,
    })
  }

  if (out.length === 0) throw new Error(`${OBSERVATION_DATASET} had no usable station`)
  return out.sort((a, b) => a.id.localeCompare(b.id))
}

// MARK: - Helpers

/** `台` -> `臺`, trimmed: CWA writes 臺北市, MOENV and users sometimes 台北市. */
export function countyName(name: string | null): string | null {
  const trimmed = name?.trim().replace(/台/g, '臺')
  return trimmed ? trimmed : null
}

/** `2026-11-05 18:00:00` (Taiwan wall clock) -> `2026-11-05T18:00:00+08:00`; an ISO value with an offset passes through. */
export function taiwanIso(value: string | null): string | null {
  if (!value) return null
  const m = value.trim().match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?$/)
  if (!m) return null
  const [, day, hm, sec, zone] = m
  const offset = zone ? (zone === 'Z' ? 'Z' : zone.length === 5 ? `${zone.slice(0, 3)}:${zone.slice(3)}` : zone) : '+08:00'
  return `${day}T${hm}:${sec ?? '00'}${offset}`
}

function plausibleTemp(n: number): boolean {
  // Taiwan's record low is around -18 °C on Yushan; CWA's missing markers are -99 and below.
  return n > -50 && n < 60
}

function valid(n: number | null, ok: (n: number) => boolean): number | null {
  return n !== null && ok(n) ? n : null
}

function round(n: number, places: number): number {
  const f = 10 ** places
  return Math.round(n * f) / f
}

function get(obj: unknown, ...keys: string[]): unknown {
  if (!obj || typeof obj !== 'object') return undefined
  for (const key of keys) {
    const value = (obj as Record<string, unknown>)[key]
    if (value !== undefined) return value
  }
  return undefined
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function str(value: unknown): string | null {
  if (typeof value === 'string') return value.trim() || null
  if (typeof value === 'number' && Number.isFinite(value)) return String(value)
  return null
}

function num(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value)
    return Number.isFinite(n) ? n : null
  }
  return null
}

function int(value: unknown): number | null {
  const n = num(value)
  return n !== null && Number.isInteger(n) ? n : null
}
