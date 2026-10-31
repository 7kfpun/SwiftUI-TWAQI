// MOENV air-quality forecast sync: aqf_p_01 -> Directus `twaqi_aqi_forecast`.
//
// One row per (area, forecast_date), latest publish only: a newer PublishTime
// replaces the row, an older or equal one is skipped. Nothing is ever deleted;
// rows whose forecast_date is more than ARCHIVE_AFTER_DAYS old are soft-archived.
// If MOENV is down or returns nothing usable, Directus is left untouched so the
// app keeps showing the last good forecast.

export interface ForecastEnv {
  MOENV_API_KEY: string
  DIRECTUS_URL: string
  DIRECTUS_FORECAST_TOKEN: string
  /** Local testing only: point the sync at a mock instead of MOENV. */
  MOENV_FORECAST_URL?: string
}

/** A forecast row as stored in Directus. */
export interface ForecastRow {
  area: string
  forecast_date: string // YYYY-MM-DD
  aqi: number | null
  major_pollutant: string | null
  minor_pollutant: string | null
  minor_pollutant_aqi: number | null
  content: string | null
  publish_time: string // YYYY-MM-DD HH:mm:ss, Taiwan local time (as MOENV publishes it)
  source: 'AQF_P_01'
}

export interface ForecastSyncResult {
  fetched: number
  rows: number
  created: number
  updated: number
  unchanged: number
  archived: number
  latestPublishTime: string | null
}

const MOENV_FORECAST = 'https://data.moenv.gov.tw/api/v2/aqf_p_01?format=JSON&limit=1000'
const COLLECTION = 'twaqi_aqi_forecast'
const ARCHIVE_AFTER_DAYS = 14

export async function syncForecast(env: ForecastEnv): Promise<ForecastSyncResult> {
  if (!env.DIRECTUS_URL || !env.DIRECTUS_FORECAST_TOKEN) throw new Error('Directus is not configured')

  const raw = await fetchMoenv(env)
  const rows = normalize(raw)
  // An empty or unparseable feed is an error, not "no forecast": keep the last
  // good rows rather than letting the app go blank.
  if (rows.length === 0) throw new Error(`MOENV aqf_p_01 returned ${raw.length} records, none usable`)

  const directus = new Directus(env.DIRECTUS_URL, env.DIRECTUS_FORECAST_TOKEN)

  // Existing rows for the dates in this feed, in one request.
  const dates = [...new Set(rows.map((r) => r.forecast_date))]
  const existing = await directus.list<{ id: number; area: string; forecast_date: string; publish_time: string | null; archived: boolean | null }>({
    'filter[forecast_date][_in]': dates.join(','),
    fields: 'id,area,forecast_date,publish_time,archived',
    limit: '-1',
  })
  const byKey = new Map<string, (typeof existing)[number]>()
  for (const item of existing) {
    const key = rowKey(item.area, String(item.forecast_date).slice(0, 10))
    const cur = byKey.get(key)
    // Should be unique, but there is no DB index: if duplicates exist, upsert
    // onto the newest and leave the rest alone.
    if (!cur || comparePublish(item.publish_time, cur.publish_time) > 0) byKey.set(key, item)
  }

  const creates: ForecastRow[] = []
  const updates: Array<ForecastRow & { id: number; archived: false }> = []
  let unchanged = 0
  for (const row of rows) {
    const cur = byKey.get(rowKey(row.area, row.forecast_date))
    if (!cur) creates.push(row)
    // An archived row for a date still in the feed (e.g. a manual test row) is
    // overwritten whatever its publish_time, so the live forecast shows.
    else if (cur.archived || comparePublish(row.publish_time, cur.publish_time) > 0) updates.push({ ...row, id: cur.id, archived: false })
    else unchanged++
  }

  if (creates.length) await directus.create(creates)
  // Directus updates an array of partial items (each with its primary key) in one PATCH.
  if (updates.length) await directus.updateBatch(updates)

  const archived = await archiveOld(directus)

  return {
    fetched: raw.length,
    rows: rows.length,
    created: creates.length,
    updated: updates.length,
    unchanged,
    archived,
    latestPublishTime: rows.reduce<string | null>((max, r) => (comparePublish(r.publish_time, max) > 0 ? r.publish_time : max), null),
  }
}

async function fetchMoenv(env: ForecastEnv): Promise<Record<string, unknown>[]> {
  const base = env.MOENV_FORECAST_URL || MOENV_FORECAST
  const url = env.MOENV_FORECAST_URL ? base : `${base}&api_key=${encodeURIComponent(env.MOENV_API_KEY)}`
  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  // MOENV answers a bad key with 200 and plain text ("api_key 不存在。").
  const text = await res.text()
  if (!res.ok) throw new Error(`MOENV aqf_p_01 ${res.status}: ${text.slice(0, 120)}`)
  let body: unknown
  try {
    body = JSON.parse(text)
  } catch {
    throw new Error(`MOENV aqf_p_01 not JSON: ${text.slice(0, 120)}`)
  }
  // v2 returns a bare array; older shapes wrap it in { records }.
  const records = Array.isArray(body) ? body : (body as { records?: unknown })?.records
  if (!Array.isArray(records)) throw new Error('MOENV aqf_p_01: no records array')
  return records.filter((r): r is Record<string, unknown> => !!r && typeof r === 'object')
}

/**
 * MOENV fields (case varies by API version): Content, PublishTime, Area,
 * MajorPollutant, ForecastDate, AQI, MinorPollutant, MinorPollutantAQI.
 * Keeps the newest PublishTime per (Area, ForecastDate).
 */
export function normalize(records: Record<string, unknown>[]): ForecastRow[] {
  const out = new Map<string, ForecastRow>()
  for (const record of records) {
    const get = lowerKeys(record)
    const area = text(get('area'))
    const forecastDate = toDate(text(get('forecastdate')))
    const publishTime = toLocalDateTime(text(get('publishtime')))
    if (!area || !forecastDate || !publishTime) continue

    const row: ForecastRow = {
      area,
      forecast_date: forecastDate,
      aqi: int(get('aqi')),
      major_pollutant: text(get('majorpollutant')),
      minor_pollutant: text(get('minorpollutant')),
      minor_pollutant_aqi: int(get('minorpollutantaqi')),
      content: text(get('content')),
      publish_time: publishTime,
      source: 'AQF_P_01',
    }
    const key = rowKey(area, forecastDate)
    const cur = out.get(key)
    if (!cur || comparePublish(row.publish_time, cur.publish_time) > 0) out.set(key, row)
  }
  return [...out.values()].sort((a, b) => a.forecast_date.localeCompare(b.forecast_date) || a.area.localeCompare(b.area))
}

async function archiveOld(directus: Directus): Promise<number> {
  const cutoff = taipeiDate(-ARCHIVE_AFTER_DAYS)
  const old = await directus.list<{ id: number }>({
    'filter[forecast_date][_lt]': cutoff,
    'filter[archived][_neq]': 'true',
    fields: 'id',
    limit: '200',
  })
  if (old.length === 0) return 0
  await directus.updateKeys(old.map((o) => o.id), { archived: true })
  return old.length
}

class Directus {
  constructor(private base: string, private token: string) {}

  async list<T>(params: Record<string, string>): Promise<T[]> {
    const url = new URL(`items/${COLLECTION}`, this.base.endsWith('/') ? this.base : `${this.base}/`)
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v)
    const body = (await this.request('GET', url)) as { data?: T[] }
    return body.data ?? []
  }

  create(items: ForecastRow[]) {
    return this.request('POST', this.itemsUrl(), items.map((item) => ({ ...item, archived: false })))
  }

  updateBatch(items: Array<{ id: number }>) {
    return this.request('PATCH', this.itemsUrl(), items)
  }

  updateKeys(keys: number[], data: Record<string, unknown>) {
    return this.request('PATCH', this.itemsUrl(), { keys, data })
  }

  private itemsUrl() {
    return new URL(`items/${COLLECTION}`, this.base.endsWith('/') ? this.base : `${this.base}/`)
  }

  private async request(method: string, url: URL, body?: unknown): Promise<unknown> {
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${this.token}`,
        Accept: 'application/json',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    const text = await res.text()
    if (!res.ok) throw new Error(`Directus ${method} ${url.pathname} ${res.status}: ${text.slice(0, 200)}`)
    // 204 when the token may write but not read the result back.
    return text ? JSON.parse(text) : {}
  }
}

function rowKey(area: string, date: string) {
  return `${area}|${date}`
}

/** Both sides are Taiwan-local "YYYY-MM-DD HH:mm:ss"; tolerate a "T" and missing seconds. */
function comparePublish(a: string | null | undefined, b: string | null | undefined): number {
  const na = a ? toLocalDateTime(a) ?? '' : ''
  const nb = b ? toLocalDateTime(b) ?? '' : ''
  return na < nb ? -1 : na > nb ? 1 : 0
}

function lowerKeys(record: Record<string, unknown>) {
  const map = new Map(Object.entries(record).map(([k, v]) => [k.toLowerCase(), v]))
  return (key: string) => map.get(key)
}

function text(v: unknown): string | null {
  if (v === null || v === undefined) return null
  const s = String(v).trim()
  return s === '' || s === '-' ? null : s
}

function int(v: unknown): number | null {
  const s = text(v)
  if (!s) return null
  const n = Number(s)
  return Number.isFinite(n) ? Math.round(n) : null
}

/** "2026-11-01", "2026/11/1", "2026-11-01 00:00:00" -> "2026-11-01" */
export function toDate(s: string | null): string | null {
  const m = s?.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/)
  return m ? `${m[1]}-${pad(m[2])}-${pad(m[3])}` : null
}

/** "2026-10-31 16:30", "2026/10/31 16:30:00", "2026-10-31T16:30" -> "2026-10-31 16:30:00" (Taiwan local) */
export function toLocalDateTime(s: string | null): string | null {
  const m = s?.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?/)
  return m ? `${m[1]}-${pad(m[2])}-${pad(m[3])} ${pad(m[4])}:${m[5]}:${m[6] ?? '00'}` : null
}

function pad(s: string) {
  return s.padStart(2, '0')
}

/** Today in Asia/Taipei (UTC+8, no DST), shifted by `days`, as YYYY-MM-DD. */
function taipeiDate(days = 0): string {
  return new Date(Date.now() + 8 * 3600_000 + days * 86_400_000).toISOString().slice(0, 10)
}
