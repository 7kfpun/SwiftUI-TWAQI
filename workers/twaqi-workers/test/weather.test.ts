// Run with `npm test` (Node 23.6+ strips the types; no extra dependencies).
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import {
  FORECAST_DATASET,
  OBSERVATION_DATASET,
  WEATHER_CACHE_CONTROL,
  WEATHER_KEY,
  WX_CODES,
  countyName,
  mergeWeather,
  parseForecast,
  parseObservations,
  rainfall,
  redactSecrets,
  syncWeather,
  taiwanIso,
  unknownWxCodes,
  type WeatherEnv,
  type WeatherFile,
} from '../src/weather.ts'

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8'))
const FORECAST = fixture(FORECAST_DATASET)
const OBSERVATIONS = fixture(OBSERVATION_DATASET)
const NOW = new Date('2026-11-05T04:35:00Z')

// MARK: F-C0032-001

test('forecast: three periods per county with Wx code, text, PoP and min–max °C', () => {
  const counties = parseForecast(FORECAST)
  assert.deepEqual(Object.keys(counties).sort(), ['嘉義縣', '臺北市', '花蓮縣'].sort())
  assert.deepEqual(counties['臺北市'], [
    { start: '2026-11-05T12:00:00+08:00', end: '2026-11-05T18:00:00+08:00', wx: 4, text: '多雲', pop: 10, minT: 23, maxT: 27 },
    { start: '2026-11-05T18:00:00+08:00', end: '2026-11-06T06:00:00+08:00', wx: 8, text: '多雲短暫雨', pop: 30, minT: 21, maxT: 24 },
    { start: '2026-11-06T06:00:00+08:00', end: '2026-11-06T18:00:00+08:00', wx: 11, text: '陰短暫雨', pop: 60, minT: 20, maxT: 23 },
  ])
})

test('forecast: CI (comfort) is not kept, missing values become null, a county without Wx is dropped', () => {
  const counties = parseForecast(FORECAST)
  assert.equal(JSON.stringify(counties).includes('舒適'), false)
  assert.equal(counties['嘉義縣'][1].minT, null) // -99
  assert.equal(counties['嘉義縣'][2].maxT, null) // "-"
  assert.equal(counties['無資料縣'], undefined)
})

test('forecast: nothing usable throws, so the last good forecast is kept', () => {
  assert.throws(() => parseForecast({ success: 'true', records: { location: [] } }), /no usable county/)
  assert.throws(() => parseForecast({ success: 'true' }), /no usable county/)
  assert.throws(() => parseForecast(null), /no usable county/)
})

test('forecast: accepts the capitalised keys CWA uses in its newer datasets', () => {
  const counties = parseForecast({
    records: {
      Location: [
        {
          LocationName: '台中市',
          WeatherElement: [
            { ElementName: 'Wx', Time: [{ StartTime: '2026-11-05T18:00:00+08:00', EndTime: '2026-11-06T06:00:00+08:00', Parameter: { ParameterName: '晴天', ParameterValue: '1' } }] },
            { ElementName: 'PoP', Time: [{ StartTime: '2026-11-05T18:00:00+08:00', EndTime: '2026-11-06T06:00:00+08:00', Parameter: { ParameterName: '0' } }] },
          ],
        },
      ],
    },
  })
  assert.deepEqual(counties, {
    臺中市: [{ start: '2026-11-05T18:00:00+08:00', end: '2026-11-06T06:00:00+08:00', wx: 1, text: '晴天', pop: 0, minT: null, maxT: null }],
  })
})

// MARK: Wx codes

test('Wx codes: CWA table is 1–42 without 40, and every code in it is known', () => {
  assert.equal(WX_CODES.size, 41)
  for (let code = 1; code <= 42; code++) assert.equal(WX_CODES.has(code), code !== 40, `code ${code}`)
  assert.equal(WX_CODES.has(0), false)
  assert.equal(WX_CODES.has(43), false)
})

test('Wx codes: codes outside the table are kept and reported', () => {
  const period = (wx: number | null) => ({ start: 's', end: 'e', wx, text: null, pop: null, minT: null, maxT: null })
  assert.deepEqual(unknownWxCodes({ a: [period(1), period(40)], b: [period(99), period(null), period(42), period(40)] }), [40, 99])
  assert.deepEqual(unknownWxCodes(parseForecast(FORECAST)), [])
})

// MARK: O-A0003-001

test('observations: WGS84 position, county, readings and time per station', () => {
  const stations = parseObservations(OBSERVATIONS)
  const taipei = stations.find((s) => s.id === '466920')
  assert.deepEqual(taipei, {
    id: '466920',
    name: '臺北',
    county: '臺北市',
    lat: 25.03766,
    lon: 121.51485,
    time: '2026-11-05T12:00:00+08:00',
    temp: 24.3,
    humidity: 75,
    rain: 0.5,
    wind: 3.2,
  })
  // Only the fields the app shows.
  assert.deepEqual(Object.keys(taipei!).sort(), ['county', 'humidity', 'id', 'lat', 'lon', 'name', 'rain', 'temp', 'time', 'wind'])
})

test('observations: -99 style markers are null, a station with no reading left is dropped, a bad time is dropped', () => {
  const stations = parseObservations(OBSERVATIONS)
  assert.deepEqual(stations.map((s) => s.id), ['466920', '466990', '467410', '467440', '467480', '467490'])
  const chiayi = stations.find((s) => s.id === '467480')!
  assert.equal(chiayi.rain, null) // -99
  assert.equal(chiayi.humidity, 81) // 0.81 in the old fractional form
})

test('observations: rain T (trace) and -98 (no rain for 6 h) are 0; X and other negatives stay null', () => {
  const stations = parseObservations(OBSERVATIONS)
  const rain = (id: string) => stations.find((s) => s.id === id)!.rain
  assert.equal(rain('467490'), 0) // "T"
  assert.equal(rain('467410'), 0) // -98
  assert.equal(rain('467440'), null) // "X"
  assert.equal(rain('467480'), null) // -99
  assert.equal(rainfall('t'), 0)
  assert.equal(rainfall(' T '), 0)
  assert.equal(rainfall('-98'), 0)
  assert.equal(rainfall(-99), null)
  assert.equal(rainfall(-998), null)
  assert.equal(rainfall(-1), null)
  assert.equal(rainfall('X'), null)
  assert.equal(rainfall(null), null)
  assert.equal(rainfall('12.5'), 12.5)
})

test('observations: nothing usable throws', () => {
  assert.throws(() => parseObservations({ records: { Station: [] } }), /no usable station/)
  assert.throws(() => parseObservations({}), /no usable station/)
})

// MARK: Helpers

test('county names use 臺, as CWA writes them', () => {
  assert.equal(countyName(' 台北市 '), '臺北市')
  assert.equal(countyName('臺東縣'), '臺東縣')
  assert.equal(countyName(''), null)
  assert.equal(countyName(null), null)
})

test('times: CWA wall-clock times are Taiwan time; an offset is kept', () => {
  assert.equal(taiwanIso('2026-11-05 18:00:00'), '2026-11-05T18:00:00+08:00')
  assert.equal(taiwanIso('2026-11-05T18:00:00+08:00'), '2026-11-05T18:00:00+08:00')
  assert.equal(taiwanIso('2026-11-05 18:00'), '2026-11-05T18:00:00+08:00')
  assert.equal(taiwanIso('2026-11-05T10:00:00Z'), '2026-11-05T10:00:00Z')
  assert.equal(taiwanIso('tomorrow'), null)
})

// MARK: Keep last good

const PREV: WeatherFile = {
  version: 1,
  updatedAt: '2026-11-05T03:35:00.000Z',
  forecast: { fetchedAt: '2026-11-05T03:35:00.000Z', counties: { 臺北市: [] } },
  observations: { fetchedAt: '2026-11-05T03:35:00.000Z', stations: [] },
}

test('merge: a failed set keeps its last good section, a new one replaces it', () => {
  const counties = parseForecast(FORECAST)
  const { file, result } = mergeWeather(PREV, { value: counties }, { error: 'O-A0003-001 HTTP 500' }, NOW)
  assert.equal(file.forecast?.fetchedAt, NOW.toISOString())
  assert.equal(file.forecast?.counties, counties)
  assert.deepEqual(file.observations, PREV.observations)
  assert.equal(result.forecast, 'updated')
  assert.equal(result.observations, 'kept')
  assert.equal(result.observationsError, 'O-A0003-001 HTTP 500')
})

test('merge: a set that never loaded is null, not empty', () => {
  const { file, result } = mergeWeather(null, { error: 'x' }, { value: parseObservations(OBSERVATIONS) }, NOW)
  assert.equal(file.forecast, null)
  assert.equal(result.forecast, 'missing')
  assert.equal(result.stations, 6)
})

/** In-memory stand-in for the R2 bucket. */
function bucket(initial: Record<string, string> = {}) {
  const store = new Map(Object.entries(initial))
  const puts: Array<{ key: string; options: unknown }> = []
  return {
    store,
    puts,
    binding: {
      async get(key: string) {
        const body = store.get(key)
        return body === undefined ? null : { json: async () => JSON.parse(body) }
      },
      async put(key: string, body: string, options: unknown) {
        store.set(key, body)
        puts.push({ key, options })
      },
    } as unknown as R2Bucket,
  }
}

function cwa(answers: Record<string, () => Response>): { fetch: typeof fetch; urls: string[] } {
  const urls: string[] = []
  return {
    urls,
    fetch: (async (input: string) => {
      urls.push(input)
      const dataset = Object.keys(answers).find((d) => input.includes(`/${d}?`))
      return dataset ? answers[dataset]() : new Response('not found', { status: 404 })
    }) as unknown as typeof fetch,
  }
}

const ok = (body: unknown) => () => new Response(JSON.stringify(body), { status: 200 })

test('sync: writes weather/latest.json with both sets and the cam cache rule', async () => {
  const r2 = bucket()
  const api = cwa({ [FORECAST_DATASET]: ok(FORECAST), [OBSERVATION_DATASET]: ok(OBSERVATIONS) })
  const env: WeatherEnv = { CAMS: r2.binding, CWA_API_KEY: 'test-key' }

  const result = await syncWeather(env, NOW, api.fetch)
  assert.equal(result.forecast, 'updated')
  assert.equal(result.observations, 'updated')
  assert.equal(result.counties, 3)
  assert.equal(result.stations, 6)

  const file = JSON.parse(r2.store.get(WEATHER_KEY)!) as WeatherFile
  assert.equal(file.version, 1)
  assert.equal(file.updatedAt, NOW.toISOString())
  assert.equal(file.forecast?.counties['花蓮縣'].length, 3)
  assert.deepEqual(r2.puts[0].options, {
    httpMetadata: { contentType: 'application/json; charset=utf-8', cacheControl: WEATHER_CACHE_CONTROL },
  })
  // The key is sent to CWA only.
  assert.ok(api.urls.every((u) => u.startsWith('https://opendata.cwa.gov.tw/') && u.includes('Authorization=test-key')))
  assert.equal(JSON.stringify(file).includes('test-key'), false)
})

test('sync: one set down keeps its last good section', async () => {
  const r2 = bucket({ [WEATHER_KEY]: JSON.stringify(PREV) })
  const api = cwa({ [FORECAST_DATASET]: () => new Response('<html>busy</html>', { status: 200 }), [OBSERVATION_DATASET]: ok(OBSERVATIONS) })

  const result = await syncWeather({ CAMS: r2.binding, CWA_API_KEY: 'k' }, NOW, api.fetch)
  assert.equal(result.forecast, 'kept')
  assert.match(result.forecastError!, /non-JSON/)
  const file = JSON.parse(r2.store.get(WEATHER_KEY)!) as WeatherFile
  assert.deepEqual(file.forecast, PREV.forecast)
  assert.equal(file.observations?.stations.length, 6)
})

test('sync: both sets down leaves the last good file untouched and throws', async () => {
  const before = JSON.stringify(PREV)
  const r2 = bucket({ [WEATHER_KEY]: before })
  const api = cwa({
    [FORECAST_DATASET]: () => new Response('{"success":"false"}', { status: 200 }),
    [OBSERVATION_DATASET]: () => new Response('', { status: 503 }),
  })

  await assert.rejects(syncWeather({ CAMS: r2.binding, CWA_API_KEY: 'k' }, NOW, api.fetch), /nothing usable/)
  assert.equal(r2.store.get(WEATHER_KEY), before)
  assert.equal(r2.puts.length, 0)
})

test('sync: a fetch error that names the request URL keeps the key out of the result', async () => {
  const r2 = bucket({ [WEATHER_KEY]: JSON.stringify(PREV) })
  const failing = (async (input: string) => {
    if (input.includes(`/${FORECAST_DATASET}?`)) throw new TypeError(`fetch failed: ${input}`)
    return new Response(JSON.stringify(OBSERVATIONS), { status: 200 })
  }) as unknown as typeof fetch

  const result = await syncWeather({ CAMS: r2.binding, CWA_API_KEY: 'secret-key' }, NOW, failing)
  assert.equal(result.forecast, 'kept')
  assert.match(result.forecastError!, /fetch failed: https:\/\/opendata\.cwa\.gov\.tw\/.+F-C0032-001$/)
  assert.equal(JSON.stringify(result).includes('secret-key'), false)
})

test('errors: Authorization values and URL query strings are redacted', () => {
  assert.equal(redactSecrets('GET https://host.example/api/X?format=JSON&Authorization=abc-123 failed'), 'GET https://host.example/api/X failed')
  assert.equal(redactSecrets('bad Authorization=abc-123&format=JSON'), 'bad Authorization=[redacted]&format=JSON')
  assert.equal(redactSecrets('header Authorization: Bearer abc.def'), 'header Authorization: [redacted]')
  assert.equal(redactSecrets('F-C0032-001 HTTP 503'), 'F-C0032-001 HTTP 503')
})

test('sync: a missing key fails before calling CWA', async () => {
  const r2 = bucket()
  const api = cwa({})
  await assert.rejects(syncWeather({ CAMS: r2.binding, CWA_API_KEY: '' }, NOW, api.fetch), /CWA_API_KEY/)
  assert.equal(api.urls.length, 0)
})
