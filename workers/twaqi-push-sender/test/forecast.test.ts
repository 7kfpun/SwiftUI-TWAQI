import assert from 'node:assert/strict'
import { afterEach, describe, it } from 'node:test'
import {
  badTomorrow, decideForecast, forecastDigest, forecastText, inWindow, matchArea, nextDay, pickDays, runForecast, taipei,
} from '../src/forecast.ts'

const row = (area: string, date: string, aqi: number | null, pollutant: string | null = '細懸浮微粒', publish = '2026-11-08 16:30:00') =>
  ({ area, forecast_date: date, aqi, major_pollutant: pollutant, publish_time: publish })
const T = '2026-11-08'
const M = '2026-11-09'
// 18:20 in Taiwan is 10:20 UTC.
const evening = new Date('2026-11-08T10:20:00Z')

describe('Taiwan time', () => {
  it('reads the Taiwan day and hour, not the UTC ones', () => {
    assert.deepEqual(taipei(new Date('2026-11-08T17:30:00Z')), { day: '2026-11-09', hour: 1 })
    assert.equal(nextDay('2026-12-31'), '2027-01-01')
  })
  it('sends only from 18:00 to 21:59', () => {
    assert.equal(inWindow(new Date('2026-11-08T09:59:00Z')), false) // 17:59
    assert.equal(inWindow(new Date('2026-11-08T10:00:00Z')), true)
    assert.equal(inWindow(new Date('2026-11-08T13:59:00Z')), true) // 21:59
    assert.equal(inWindow(new Date('2026-11-08T14:00:00Z')), false)
  })
})

describe('badTomorrow', () => {
  const bad = (rows: ReturnType<typeof row>[], level?: number) => badTomorrow(pickDays(rows, T, M), level)
  it('needs tomorrow above the level and worse than today', () => {
    assert.deepEqual([...bad([row('北部', T, 80), row('北部', M, 120)]).keys()], ['北部'])
    assert.equal(bad([row('北部', T, 80), row('北部', M, 100)]).size, 0) // 100 is not above 100
    assert.equal(bad([row('北部', T, 130), row('北部', M, 120)]).size, 0) // better than today
    assert.equal(bad([row('北部', T, 120), row('北部', M, 120)]).size, 0) // not worse
    assert.equal(bad([row('北部', T, 40), row('北部', M, 90)]).size, 0) // fine
  })
  it('sends nothing when a day is missing or has no AQI', () => {
    assert.equal(bad([row('北部', M, 150)]).size, 0)
    assert.equal(bad([row('北部', T, null), row('北部', M, 150)]).size, 0)
    assert.equal(bad([row('北部', T, 50), row('北部', M, null)]).size, 0)
  })
  it('takes the newest publish when a day has two rows, and names the pollutant', () => {
    const zones = bad([row('北部', T, 50), row('北部', M, 90, null, '2026-11-08 10:30:00'), row('北部', M, 130, '臭氧8小時', '2026-11-08 16:30:00')])
    assert.deepEqual(zones.get('北部'), { area: '北部', aqi: 130, pollutant: '臭氧8小時' })
    assert.equal(bad([row('北部', T, 50), row('北部', M, 130, '-')]).get('北部')?.pollutant, null)
  })
})

describe('matchArea', () => {
  const areas = ['北部', '雲嘉南', '金門']
  it('joins the station API name to the MOENV one', () => {
    assert.equal(matchArea('北部空品區', null, areas), '北部')
    assert.equal(matchArea('雲嘉南空品區', null, areas), '雲嘉南')
    assert.equal(matchArea('其他', '金門縣', areas), '金門')
    assert.equal(matchArea('其他', '花蓮縣', areas), null)
    assert.equal(matchArea(null, null, areas), null)
  })
})

describe('decideForecast', () => {
  const base = { quiet: false, lastSentAt: null, lastDigest: null, digest: 'a', now: evening }
  it('fires for a device with no earlier heads-up', () => assert.equal(decideForecast(base), 'fire'))
  it('drops it in quiet hours', () => assert.equal(decideForecast({ ...base, quiet: true }), 'quiet'))
  it('sends once per Taiwan day', () => {
    assert.equal(decideForecast({ ...base, lastSentAt: '2026-11-08T10:20:00Z', digest: 'b' }), 'already-sent')
    // 23:00 Taiwan the night before is another day.
    assert.equal(decideForecast({ ...base, lastSentAt: '2026-11-07T15:00:00Z', digest: 'b' }), 'fire')
  })
  it('does not repeat a forecast that has not changed', () => {
    assert.equal(decideForecast({ ...base, lastSentAt: '2026-11-07T10:20:00Z', lastDigest: 'a' }), 'unchanged')
    assert.equal(decideForecast({ ...base, lastSentAt: '2026-11-07T10:20:00Z', lastDigest: 'x' }), 'fire')
  })
  it('digests the day and zones, in any order', async () => {
    const a = { area: '北部', aqi: 120, pollutant: null }
    const b = { area: '中部', aqi: 110, pollutant: 'x' }
    assert.equal(await forecastDigest(M, [a, b]), await forecastDigest(M, [b, a]))
    assert.notEqual(await forecastDigest(M, [a]), await forecastDigest(M, [{ ...a, aqi: 121 }]))
    assert.notEqual(await forecastDigest(M, [a]), await forecastDigest('2026-11-10', [a]))
  })
})

describe('forecastText', () => {
  const north = { area: '北部', aqi: 120, pollutant: '細懸浮微粒' }
  it('names the zone, level and pollutant in zh-Hant and en', () => {
    const zh = forecastText('zh-Hant', M, [north])
    assert.equal(zh.title, '明天 北部空品區 空氣品質不佳')
    assert.match(zh.body, /11\/9 預報 AQI 120（對敏感族群不健康），主要污染物 細懸浮微粒/)
    const en = forecastText('en', M, [north])
    assert.equal(en.title, 'Poor air expected tomorrow: North')
    assert.match(en.body, /11\/09: AQI 120, unhealthy for sensitive groups, mainly PM2\.5/)
  })
  it('covers every zone in one push', () => {
    const text = forecastText('en', M, [north, { area: '中部', aqi: 160, pollutant: null }])
    assert.equal(text.title, 'Poor air expected tomorrow in 2 zones')
    assert.match(text.body, /Central: AQI 160, unhealthy; North: AQI 120/)
  })
})

describe('runForecast', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  async function account() {
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign'])
    const der = Buffer.from(new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))).toString('base64')
    const label = ['PRIVATE', 'KEY'].join(' ')
    return JSON.stringify({ project_id: 'p', client_email: `fc-${Math.random()}@p.iam.gserviceaccount.com`, private_key: `-----BEGIN ${label}-----\n${der}\n-----END ${label}-----\n` })
  }

  const device = (id: number, extra: Record<string, unknown> = {}) => ({
    id, fcm_token: `tok${id}`, locale: 'en', dnd_enabled: false, dnd_start: null, dnd_end: null, timezone: 'Asia/Taipei',
    forecast_sent_at: null, forecast_digest: null, ...extra,
  })
  const sub = (id: number, station: string, dev: ReturnType<typeof device>) => ({ id, station_id: station, device: dev })

  async function setup(forecast: ReturnType<typeof row>[], subs: ReturnType<typeof sub>[]) {
    const fcm: Array<Record<string, unknown>> = []
    const marks: Array<Record<string, unknown>> = []
    let subReads = 0
    globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
      const url = new URL(String(input))
      if (url.hostname === 'aqi.test') {
        return Response.json({ success: true, data: [
          { station_id: 105, aqi: 50, name: { en: 'Zhongshan' }, area: { zh: '北部空品區' }, publish_time: null },
          { station_id: 7, aqi: 50, name: { en: 'Other' }, area: { zh: '中部空品區' }, publish_time: null },
        ] })
      }
      if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 't', expires_in: 3600 })
      if (url.hostname === 'fcm.googleapis.com') {
        fcm.push(JSON.parse(String(init.body)).message)
        return Response.json({ name: 'projects/p/messages/1' })
      }
      if (url.pathname.endsWith('/twaqi_aqi_forecast')) return Response.json({ data: forecast })
      if (url.pathname.endsWith('/twaqi_push_subscriptions')) {
        subReads++
        return Response.json({ data: subs })
      }
      if (url.pathname.endsWith('/twaqi_push_devices') && init.method === 'PATCH') {
        marks.push(...JSON.parse(String(init.body)))
        return Response.json({ data: [] })
      }
      return Response.json({ data: [] })
    }) as typeof fetch
    const env = { FCM_SERVICE_ACCOUNT: await account(), DIRECTUS_URL: 'https://cms.test', DIRECTUS_PUSH_TOKEN: 'w', AQI_API_BASE: 'https://aqi.test/api', SYNC_TOKEN: 'x' } as never
    return { env, fcm, marks, reads: () => subReads }
  }

  const badNorth = [row('北部', T, 80), row('北部', M, 130), row('中部', T, 50), row('中部', M, 60)]

  it('sends exactly one push for a favourite in a bad zone, and marks the device', async () => {
    const s = await setup(badNorth, [sub(1, '105', device(5))])
    const result = await runForecast(s.env, { now: evening })
    assert.equal(result.counts.sent, 1)
    assert.equal(s.fcm.length, 1)
    assert.match(String((s.fcm[0].notification as { body: string }).body), /AQI 130/)
    assert.equal(s.marks.length, 1)
    assert.equal(s.marks[0].id, 5)
  })

  it('covers all of a device\'s zones in one push, not one per station', async () => {
    const rows = [...badNorth.slice(0, 2), row('中部', T, 50), row('中部', M, 140)]
    const dev = device(5)
    const s = await setup(rows, [sub(1, '105', dev), sub(2, '7', dev)])
    await runForecast(s.env, { now: evening })
    assert.equal(s.fcm.length, 1)
    assert.match(String((s.fcm[0].notification as { title: string }).title), /2 zones/)
  })

  it('sends nothing, and reads no subscriptions, when the forecast is fine', async () => {
    const s = await setup([row('北部', T, 50), row('北部', M, 60)], [sub(1, '105', device(5))])
    const result = await runForecast(s.env, { now: evening })
    assert.equal(result.skipped, 'fine')
    assert.equal(s.fcm.length, 0)
    assert.equal(s.reads(), 0)
  })

  it('sends nothing outside the evening window', async () => {
    const s = await setup(badNorth, [sub(1, '105', device(5))])
    const result = await runForecast(s.env, { now: new Date('2026-11-08T02:00:00Z') })
    assert.equal(result.skipped, 'window')
    assert.equal(s.fcm.length, 0)
  })

  it('does not send twice when re-run: a device already sent today is skipped', async () => {
    const s = await setup(badNorth, [sub(1, '105', device(5, { forecast_sent_at: '2026-11-08T10:20:00Z', forecast_digest: 'old' }))])
    const result = await runForecast(s.env, { now: new Date('2026-11-08T12:20:00Z') })
    assert.equal(result.counts['already-sent'], 1)
    assert.equal(s.fcm.length, 0)
  })

  it('skips a device in do-not-disturb and leaves it unmarked', async () => {
    const quiet = device(5, { dnd_enabled: true, dnd_start: '18:00', dnd_end: '22:00' })
    const s = await setup(badNorth, [sub(1, '105', quiet)])
    const result = await runForecast(s.env, { now: evening })
    assert.equal(result.counts.quiet, 1)
    assert.equal(s.fcm.length, 0)
    assert.equal(s.marks.length, 0)
  })

  it('writes nothing in a dry run', async () => {
    const s = await setup(badNorth, [sub(1, '105', device(5))])
    const result = await runForecast(s.env, { now: evening, dryRun: true })
    assert.equal(result.counts.fire, 1)
    assert.equal(s.fcm.length, 0)
    assert.equal(s.marks.length, 0)
  })
})
