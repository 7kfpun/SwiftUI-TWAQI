// Current AQI from the same API the app reads (`ApiDomain` +
// `/v1/current-pollutants`), so an alert never disagrees with the station
// screen it opens.

export interface AqiConfig {
  /** The app's API_DOMAIN, e.g. https://….execute-api.us-west-2.amazonaws.com/api */
  AQI_API_BASE: string
  /** Countries fetched whole each run, comma separated. Default "twn". */
  AQI_COUNTRIES?: string
}

export interface Reading {
  stationId: number
  aqi: number
  nameZh: string | null
  nameEn: string | null
  publishTime: string | null
}

interface ApiPollutant {
  station_id: number
  code?: string
  aqi?: number | null
  name?: { zh?: string; en?: string; th?: string }
  publish_time?: string
}

/** Stations not in a fetched country are looked up one by one, up to this
 * many, to stay inside the Worker's subrequest budget. */
const MAX_SINGLE_LOOKUPS = 20

/** Readings for `stationIds`, keyed by station id. Missing stations are left out. */
export async function readings(env: AqiConfig, stationIds: Iterable<number>): Promise<Map<number, Reading>> {
  const wanted = new Set(stationIds)
  const out = new Map<number, Reading>()
  if (!wanted.size) return out

  const countries = (env.AQI_COUNTRIES || 'twn').split(',').map((c) => c.trim()).filter(Boolean)
  for (const country of countries) {
    for (const p of await fetchPollutants(env, { country })) {
      if (wanted.has(p.station_id)) out.set(p.station_id, toReading(p))
    }
  }

  const missing = [...wanted].filter((id) => !out.has(id)).slice(0, MAX_SINGLE_LOOKUPS)
  await Promise.all(
    missing.map(async (id) => {
      try {
        const p = (await fetchPollutants(env, { station_id: String(id) })).find((x) => x.station_id === id)
        if (p) out.set(id, toReading(p))
      } catch (e) {
        console.warn('aqi lookup failed', id, String(e))
      }
    }),
  )
  return out
}

async function fetchPollutants(env: AqiConfig, query: Record<string, string>): Promise<ApiPollutant[]> {
  const url = `${env.AQI_API_BASE.replace(/\/+$/, '')}/v1/current-pollutants?${new URLSearchParams(query)}`
  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!res.ok) throw new Error(`AQI API ${res.status} for ${JSON.stringify(query)}`)
  const body = (await res.json()) as { success?: boolean; data?: ApiPollutant[] }
  if (!body.success || !Array.isArray(body.data)) throw new Error(`AQI API returned no data for ${JSON.stringify(query)}`)
  return body.data
}

function toReading(p: ApiPollutant): Reading {
  return {
    stationId: p.station_id,
    aqi: typeof p.aqi === 'number' ? p.aqi : NaN,
    nameZh: p.name?.zh || null,
    nameEn: p.name?.en || p.name?.th || p.code || null,
    publishTime: p.publish_time ?? null,
  }
}
