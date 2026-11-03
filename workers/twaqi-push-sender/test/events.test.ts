import assert from 'node:assert/strict'
import { timingSafeEqual } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { afterEach, describe, it } from 'node:test'
import { pushEventPoint } from '../src/events.ts'
import worker, { run } from '../src/index.ts'
import { eventCollector, forwardEvents, nodeEnv } from '../scripts/run.ts'

// Per-send analytics from the GitHub Actions run (FOX-71): run() writes to a
// collector, scripts/run.ts forwards to POST /internal/events, and the Worker
// writes the same data points to Analytics Engine.

// The Workers runtime adds crypto.subtle.timingSafeEqual; Node doesn't.
const subtle = crypto.subtle as SubtleCrypto & { timingSafeEqual?: (a: ArrayBufferView, b: ArrayBufferView) => boolean }
if (!subtle.timingSafeEqual) {
  Object.defineProperty(subtle, 'timingSafeEqual', { value: (a: ArrayBufferView, b: ArrayBufferView) => timingSafeEqual(a, b) })
}

const point = (station = '105', status = 'sent') => pushEventPoint({
  token_suffix: 'abc123', status: status as 'sent', station, trigger: 'pollution', device: 5, aqi: 180, fcm_message_id: null, error_code: null,
})

function fakeDataset() {
  const points: unknown[] = []
  return { points, dataset: { writeDataPoint: (p?: unknown) => void points.push(p) } as AnalyticsEngineDataset }
}

async function post(body: unknown, { token = 'secret', method = 'POST', binding = true } = {}) {
  const { points, dataset } = fakeDataset()
  const env = { SYNC_TOKEN: 'secret', ...(binding ? { PUSH_EVENTS: dataset } : {}) } as never
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  const request = new Request('https://worker.test/internal/events', {
    method, headers, body: method === 'POST' ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined,
  })
  const res = await worker.fetch(request as never, env, {} as never)
  return { status: res.status, body: (await res.json()) as Record<string, unknown>, points }
}

describe('POST /internal/events', () => {
  it('refuses a missing or wrong token', async () => {
    assert.equal((await post({ events: [point()] }, { token: '' })).status, 401)
    const wrong = await post({ events: [point()] }, { token: 'secreT' })
    assert.equal(wrong.status, 401)
    assert.equal(wrong.points.length, 0)
  })

  it('is POST only', async () => {
    assert.equal((await post(undefined, { method: 'GET' })).status, 405)
  })

  it('refuses more than 250 events', async () => {
    const res = await post({ events: Array.from({ length: 251 }, () => point()) })
    assert.equal(res.status, 400)
    assert.match(String(res.body.error), /at most 250/)
    assert.equal(res.points.length, 0)
  })

  it('refuses a bad shape, writing nothing', async () => {
    const good = point()
    for (const bad of [
      'not json',
      {},
      { events: 'x' },
      { events: [good, null] },
      { events: [{ ...good, extra: 1 }] },
      { events: [{ ...good, blobs: good.blobs!.slice(0, 5) }] },
      { events: [{ ...good, blobs: ['nope', ...good.blobs!.slice(1)] }] },
      { events: [{ ...good, blobs: [good.blobs![0], 'nope', ...good.blobs!.slice(2)] }] },
      { events: [{ ...good, indexes: ['x'.repeat(97)] }] },
      { events: [{ ...good, doubles: ['180'] }] },
    ]) {
      const res = await post(bad)
      assert.equal(res.status, 400, JSON.stringify(bad))
      assert.equal(res.points.length, 0)
    }
  })

  it('writes a valid batch as is', async () => {
    const events = [point('105'), point('12', 'failed'), point('7', 'unregistered')]
    const res = await post({ events })
    assert.equal(res.status, 200)
    assert.deepEqual(res.body, { received: 3, written: 3 })
    assert.deepEqual(res.points, events)
  })

  it('says so when the Worker has no binding', async () => {
    assert.equal((await post({ events: [point()] }, { binding: false })).status, 503)
  })
})

describe('run() events without a binding', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  it('collects the same data points the binding gets, and the route accepts them', async () => {
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign'],
    )
    const der = Buffer.from(new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))).toString('base64')
    const label = ['PRIVATE', 'KEY'].join(' ')
    const account = JSON.stringify({ project_id: 'p', client_email: `events-${Date.now()}@p.iam.gserviceaccount.com`, private_key: `-----BEGIN ${label}-----\n${der}\n-----END ${label}-----\n` })

    globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
      const url = new URL(String(input))
      if (url.hostname === 'aqi.test') {
        return Response.json({ success: true, data: [{ station_id: 105, aqi: 180, name: { en: 'Zhongshan' }, publish_time: null }] })
      }
      if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 't', expires_in: 3600 })
      if (url.hostname === 'fcm.googleapis.com') {
        const token = JSON.parse(String(init.body)).message.token
        if (token === 'tok2') return new Response('{"error":{"status":"PERMISSION_DENIED"}}', { status: 403 })
        return Response.json({ name: `m/${token}` })
      }
      if (url.pathname.endsWith('/twaqi_push_subscriptions') && (init.method ?? 'GET') === 'GET') {
        return Response.json({ data: [1, 2, 3].map((k) => ({
          id: k, station_id: '105', site_id: null, metric: 'aqi', direction: 'above', threshold: 120,
          last_value: null, in_zone: false, last_fired_at: null,
          device: { id: 1000 + k, fcm_token: `token-${k}`.replace('token-2', 'tok2'), locale: 'en', dnd_enabled: false, dnd_start: null, dnd_end: null, timezone: 'Asia/Taipei' },
        })) })
      }
      return Response.json({ data: [] })
    }) as typeof fetch

    const config = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8')
    const base = nodeEnv(config, { FCM_SERVICE_ACCOUNT: account, DIRECTUS_PUSH_TOKEN: 'w', AQI_API_BASE: 'https://aqi.test/api', SYNC_TOKEN: 's' })

    // The Worker's path: a real binding.
    const binding = fakeDataset()
    const viaBinding = await run({ ...base, PUSH_EVENTS: binding.dataset }, {})
    // The GitHub Actions path: the collector.
    const collector = eventCollector()
    const viaCollector = await run({ ...base, PUSH_EVENTS: collector.dataset }, {})

    const sorted = (points: unknown[]) => points.map((p) => JSON.stringify(p)).sort()
    assert.equal(viaBinding.events, 3)
    assert.equal(viaCollector.events, 3)
    assert.deepEqual(sorted(collector.points), sorted(binding.points))
    assert.deepEqual(collector.points.find((p) => p.blobs?.[0] === 'failed'), {
      indexes: ['105'], blobs: ['failed', 'pollution', '105', 'PERMISSION_DENIED', 'tok2', '1002'], doubles: [180],
    })

    const res = await post({ events: collector.points })
    assert.equal(res.status, 200)
    assert.deepEqual(sorted(res.points), sorted(binding.points))
  })
})

describe('forwardEvents', () => {
  const points = Array.from({ length: 600 }, (_, k) => point(String(k)))

  it('posts 600 events as 250, 250 and 100 to the ingest route with the token', async () => {
    const calls: { url: string; auth: string | null; size: number }[] = []
    const fake = (async (url: string, init: RequestInit) => {
      const size = JSON.parse(String(init.body)).events.length
      calls.push({ url, auth: new Headers(init.headers).get('Authorization'), size })
      return Response.json({ received: size, written: size })
    }) as typeof fetch
    const result = await forwardEvents(points, { url: 'https://worker.test/', token: 'secret', fetch: fake, retryDelayMs: 0 })
    assert.deepEqual(calls.map((c) => c.size), [250, 250, 100])
    assert.ok(calls.every((c) => c.url === 'https://worker.test/internal/events' && c.auth === 'Bearer secret'))
    assert.deepEqual(result, { events: 600, forwarded: 600, written: 600, failed: 0 })
  })

  it('retries a failed post once, then counts it and moves on without throwing', async () => {
    const urls: string[] = []
    let n = 0
    const fake = (async (url: string, init: RequestInit) => {
      urls.push(url)
      n++
      const size = JSON.parse(String(init.body)).events.length
      if (n === 1) throw new TypeError('fetch failed') // first chunk: network, then OK
      if (n === 3 || n === 4) return new Response('{}', { status: 503 }) // second chunk: twice 503
      return Response.json({ received: size, written: size })
    }) as typeof fetch
    const result = await forwardEvents(points, { url: 'https://worker.test', token: 'secret', fetch: fake, retryDelayMs: 0 })
    assert.equal(n, 5) // 2 + 2 + 1: one retry each, never more
    assert.ok(urls.every((u) => u === 'https://worker.test/internal/events')) // nothing but the ingest route: no alert re-sent
    assert.deepEqual(result, { events: 600, forwarded: 350, written: 350, failed: 250, lastError: 'HTTP 503' })
  })

  it('never throws, even when every post fails', async () => {
    const fake = (async () => {
      throw new Error('down')
    }) as unknown as typeof fetch
    const result = await forwardEvents(points.slice(0, 10), { url: 'https://worker.test', token: 'secret', fetch: fake, retryDelayMs: 0 })
    assert.deepEqual(result, { events: 10, forwarded: 0, written: 0, failed: 10, lastError: 'network' })
  })
})
