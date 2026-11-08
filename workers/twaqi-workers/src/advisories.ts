// MOENV sand/dust advisories (FOX-10): SANDST_P_01 -> Directus `twaqi_sandstorm_advisories`.
//
// One row per advisory, keyed by its PublishTime (Taiwan local, as MOENV publishes it):
// a new PublishTime is created, a stored one is updated only if MOENV changed its text. MOENV only lists an
// advisory while it is relevant, so an empty feed is normal ("no advisory") and is not an
// error; a failed or unparseable response throws, leaving Directus as it was. Nothing is
// deleted; rows published more than ARCHIVE_AFTER_DAYS ago are soft-archived.
//
// Directus collection (create by hand, like `twaqi_aqi_forecast`; the forecast token needs
// read/create/update on it): id, publish_time (string), subject (string), content (text),
// source (string), archived (boolean, default false).

export interface AdvisoryEnv {
  MOENV_API_KEY: string
  DIRECTUS_URL: string
  DIRECTUS_FORECAST_TOKEN: string
  /** Local testing only: point the sync at a mock instead of MOENV. */
  MOENV_ADVISORY_URL?: string
}

export interface AdvisoryRow {
  publish_time: string // YYYY-MM-DD HH:mm:ss, Taiwan local time
  subject: string | null
  content: string | null
  source: 'SANDST_P_01'
}

export interface AdvisorySyncResult {
  fetched: number
  rows: number
  created: number
  /** Stored advisories whose text MOENV changed under the same PublishTime. */
  updated: number
  unchanged: number
  archived: number
  latestPublishTime: string | null
}

const MOENV_ADVISORY = 'https://data.moenv.gov.tw/api/v2/sandst_p_01?format=JSON&limit=1000'
const COLLECTION = 'twaqi_sandstorm_advisories'
const ARCHIVE_AFTER_DAYS = 7

export async function syncAdvisories(env: AdvisoryEnv): Promise<AdvisorySyncResult> {
  if (!env.DIRECTUS_URL || !env.DIRECTUS_FORECAST_TOKEN) throw new Error('Directus is not configured')

  const raw = await fetchMoenv(env)
  const rows = normalizeAdvisories(raw)
  const directus = new Directus(env.DIRECTUS_URL, env.DIRECTUS_FORECAST_TOKEN)

  let created = 0
  let updated = 0
  if (rows.length) {
    const existing = await directus.list<{ id: number; publish_time: string | null; subject: string | null; content: string | null }>({
      'filter[publish_time][_in]': rows.map((r) => r.publish_time).join(','),
      fields: 'id,publish_time,subject,content',
      limit: '-1',
    })
    const known = new Map(existing.map((e) => [toLocalDateTime(e.publish_time) ?? '', e]))
    const fresh = rows.filter((r) => !known.has(r.publish_time))
    if (fresh.length) await directus.create(fresh)
    created = fresh.length
    // MOENV may correct the text of an advisory without a new PublishTime.
    for (const row of rows) {
      const cur = known.get(row.publish_time)
      if (cur && ((cur.subject ?? null) !== row.subject || (cur.content ?? null) !== row.content)) {
        await directus.update([cur.id], { subject: row.subject, content: row.content, archived: false })
        updated++
      }
    }
  }

  const archived = await archiveOld(directus)
  return {
    fetched: raw.length,
    rows: rows.length,
    created,
    updated,
    unchanged: rows.length - created - updated,
    archived,
    latestPublishTime: rows.reduce<string | null>((max, r) => (max === null || r.publish_time > max ? r.publish_time : max), null),
  }
}

async function fetchMoenv(env: AdvisoryEnv): Promise<Record<string, unknown>[]> {
  const base = env.MOENV_ADVISORY_URL || MOENV_ADVISORY
  const url = env.MOENV_ADVISORY_URL ? base : `${base}&api_key=${encodeURIComponent(env.MOENV_API_KEY)}`
  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  // MOENV answers a bad key with 200 and plain text.
  const text = await res.text()
  if (!res.ok) throw new Error(`MOENV sandst_p_01 ${res.status}: ${text.slice(0, 120)}`)
  let body: unknown
  try {
    body = JSON.parse(text)
  } catch {
    throw new Error(`MOENV sandst_p_01 not JSON: ${text.slice(0, 120)}`)
  }
  const records = Array.isArray(body) ? body : (body as { records?: unknown })?.records
  if (!Array.isArray(records)) throw new Error('MOENV sandst_p_01: no records array')
  return records.filter((r): r is Record<string, unknown> => !!r && typeof r === 'object')
}

/** MOENV fields (case varies): PublishTime, Subject, Content. A record needs a PublishTime and some text. */
export function normalizeAdvisories(records: Record<string, unknown>[]): AdvisoryRow[] {
  const out = new Map<string, AdvisoryRow>()
  for (const record of records) {
    const map = new Map(Object.entries(record).map(([k, v]) => [k.toLowerCase(), v]))
    const publishTime = toLocalDateTime(text(map.get('publishtime')))
    const subject = text(map.get('subject'))
    const content = text(map.get('content'))
    if (!publishTime || (!subject && !content)) continue
    out.set(publishTime, { publish_time: publishTime, subject, content, source: 'SANDST_P_01' })
  }
  return [...out.values()].sort((a, b) => a.publish_time.localeCompare(b.publish_time))
}

async function archiveOld(directus: Directus): Promise<number> {
  const cutoff = taipeiDateTime(-ARCHIVE_AFTER_DAYS)
  const old = await directus.list<{ id: number }>({
    'filter[publish_time][_lt]': cutoff,
    'filter[archived][_neq]': 'true',
    fields: 'id',
    limit: '200',
  })
  if (old.length === 0) return 0
  await directus.update(old.map((o) => o.id), { archived: true })
  return old.length
}

class Directus {
  private base: string
  private token: string

  // No parameter properties: node's type stripping (npm test) can't run them.
  constructor(base: string, token: string) {
    this.base = base
    this.token = token
  }

  async list<T>(params: Record<string, string>): Promise<T[]> {
    const url = this.itemsUrl()
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v)
    const body = (await this.request('GET', url)) as { data?: T[] }
    return body.data ?? []
  }

  create(items: AdvisoryRow[]) {
    return this.request('POST', this.itemsUrl(), items.map((item) => ({ ...item, archived: false })))
  }

  update(keys: number[], data: Record<string, unknown>) {
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
    return text ? JSON.parse(text) : {}
  }
}

function text(v: unknown): string | null {
  if (v === null || v === undefined) return null
  const s = String(v).trim()
  return s === '' || s === '-' ? null : s
}

/** Now in Asia/Taipei (UTC+8, no DST), shifted by `days`, as "YYYY-MM-DD HH:mm:ss". */
function taipeiDateTime(days = 0, now = Date.now()): string {
  return new Date(now + 8 * 3600_000 + days * 86_400_000).toISOString().slice(0, 19).replace('T', ' ')
}

/** "2026-10-31 16:30", "2026/10/31 16:30:00", "2026-10-31T16:30" -> "2026-10-31 16:30:00" (Taiwan local) */
export function toLocalDateTime(s: string | null): string | null {
  const m = s?.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?/)
  const pad = (v: string) => v.padStart(2, '0')
  return m ? `${m[1]}-${pad(m[2])}-${pad(m[3])} ${pad(m[4])}:${m[5]}:${m[6] ?? '00'}` : null
}
