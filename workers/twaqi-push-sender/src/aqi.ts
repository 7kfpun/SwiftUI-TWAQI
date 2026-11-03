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

/** Every station in `AQI_COUNTRIES`, keyed by station id: one request per
 * country. The sender works from these to pick the subscriptions to read. */
export async function allReadings(env: AqiConfig): Promise<Map<number, Reading>> {
  const out = new Map<number, Reading>()
  const countries = (env.AQI_COUNTRIES || 'twn').split(',').map((c) => c.trim()).filter(Boolean)
  for (const country of countries) {
    for (const p of await fetchPollutants(env, { country })) out.set(p.station_id, toReading(p))
  }
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
