// Run with `npm test` (Node 23.6+ strips the types; no extra dependencies).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { ORIGIN_TOKEN_HEADER, canonicalQuery, handleApi, isApiPath, type ApiEnv } from '../src/api.ts'

const env: ApiEnv = {
  TWAQI_API_ORIGIN_URL: 'https://origin.example/',
  TWAQI_API_CACHE_SECONDS: '600',
  TWAQI_API_ORIGIN_TOKEN: 'tok',
}

function harness(originStatus = 200, originBody: BodyInit = '{"success":true,"data":[]}') {
  const store = new Map<string, Response>()
  const calls: { url: string; token: string | null }[] = []
  const waits: Promise<unknown>[] = []
  const deps = {
    cache: {
      match: async (req: RequestInfo | URL) => store.get(new Request(req as RequestInfo).url)?.clone(),
      put: async (req: RequestInfo | URL, res: Response) => void store.set(new Request(req as RequestInfo).url, res),
    },
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push({ url: String(input), token: new Headers(init?.headers).get(ORIGIN_TOKEN_HEADER) })
      return new Response(originBody, { status: originStatus })
    }) as typeof fetch,
  }
  const ctx = { waitUntil: (p: Promise<unknown>) => void waits.push(p) }
  const get = async (path: string, method = 'GET') => {
    const res = await handleApi(new Request(`https://twaqi.app.example${path}`, { method }), env, ctx, deps as never)
    await Promise.all(waits)
    return res
  }
  return { get, calls, store }
}

test('isApiPath takes /v1/ only, leaving the webcam paths to R2', () => {
  assert.equal(isApiPath('/v1/countries'), true)
  assert.equal(isApiPath('/v1/anything'), true)
  assert.equal(isApiPath('/stations/001.jpg'), false)
  assert.equal(isApiPath('/manifest.json'), false)
  assert.equal(isApiPath('/station-cams'), false)
  assert.equal(isApiPath('/v1'), false)
})

test('forwards with the origin token, passes the body through, then serves from cache', async () => {
  const h = harness(200, '{"success":true,"data":[{"id":1}]}')
  const first = await h.get('/v1/current-pollutants?country=twn')
  assert.equal(first.status, 200)
  assert.equal(first.headers.get('x-twaqi-cache'), 'MISS')
  assert.equal(first.headers.get('content-type'), 'application/json')
  assert.equal(await first.text(), '{"success":true,"data":[{"id":1}]}')
  assert.deepEqual(h.calls, [{ url: 'https://origin.example/v1/current-pollutants?country=twn', token: 'tok' }])

  const second = await h.get('/v1/current-pollutants?country=twn')
  assert.equal(second.headers.get('x-twaqi-cache'), 'HIT')
  assert.equal(await second.text(), '{"success":true,"data":[{"id":1}]}')
  assert.equal(h.calls.length, 1)
})

test('origin errors become a JSON error and are not cached', async () => {
  const h = harness(403, '<html>Forbidden</html>')
  const res = await h.get('/v1/countries')
  assert.equal(res.status, 502)
  assert.equal(await res.text(), '{"success":false,"error":"Upstream error"}')
  assert.equal(h.store.size, 0)
  const h5 = harness(500, '{"success":false,"error":"Internal error"}')
  assert.equal((await h5.get('/v1/countries')).status, 500)
})

test('404 for other /v1 paths, 405 for writes, HEAD has no body', async () => {
  const h = harness()
  assert.equal((await h.get('/v1/clients?id=1')).status, 404)
  assert.equal((await h.get('/v1/success-ads?position=x')).status, 404)
  assert.equal((await h.get('/v1/countries', 'POST')).status, 405)
  const head = await h.get('/v1/countries', 'HEAD')
  assert.equal(head.status, 200)
  assert.equal(await head.text(), '')
  assert.equal(h.calls.length, 1)
})

test('canonicalQuery keeps the route params only, first value each, in a fixed order', () => {
  const q = (path: string, search: string) => canonicalQuery(path, new URLSearchParams(search))
  assert.equal(q('/v1/countries', '_=1'), '')
  assert.equal(q('/v1/stations', 'country_id=3&_=1&country=twn&country=hkg'), '?country=twn&country_id=3')
  assert.equal(q('/v1/current-pollutants', 'station_id=91,92&x=y'), '?station_id=91%2C92')
  assert.equal(q('/v1/historical-pollutants', 'station_id=91&limit=&station=x'), '?limit=&station=x&station_id=91')
  assert.equal(q('/v1/nope', 'a=b'), '')
})

test('extra or reordered params share one cache entry and one origin call', async () => {
  const h = harness()
  for (const search of ['country=twn', 'country=twn&_=1', '_=2&country=twn', 'country=twn&country=hkg']) {
    assert.equal((await h.get(`/v1/stations?${search}`)).status, 200)
  }
  assert.deepEqual(h.calls.map((c) => c.url), ['https://origin.example/v1/stations?country=twn'])
  assert.equal(h.store.size, 1)
})

test('a body that fails mid-stream answers the JSON 502 and is not cached', async () => {
  const broken = new ReadableStream({
    start(controller) {
      controller.enqueue(new TextEncoder().encode('{"success":tr'))
      controller.error(new Error('connection reset'))
    },
  })
  const h = harness(200, broken)
  const res = await h.get('/v1/countries')
  assert.equal(res.status, 502)
  assert.equal(await res.text(), '{"success":false,"error":"Upstream unavailable"}')
  assert.equal(h.store.size, 0)
})

test('cache-control is ours on every 200: 600 on a MISS, what is left of it on a HIT', async () => {
  const h = harness()
  const miss = await h.get('/v1/countries')
  assert.equal(miss.headers.get('cache-control'), 'public, max-age=600')
  assert.equal(h.store.get('https://twaqi.app.example/v1/countries')?.headers.get('cache-control'), 'public, max-age=600')

  // What Cloudflare's cache hands back: the zone's 4-hour browser TTL and an age.
  const cachedAs = (age: string | null) => {
    const headers: Record<string, string> = { 'content-type': 'application/json', 'cache-control': 'public, max-age=14400' }
    if (age !== null) headers.age = age
    h.store.set('https://twaqi.app.example/v1/countries', new Response('{"success":true,"data":[]}', { headers }))
  }
  for (const [age, expected] of [['120', 480], ['900', 0], [null, 600], ['abc', 600]] as const) {
    cachedAs(age)
    const hit = await h.get('/v1/countries')
    assert.equal(hit.headers.get('x-twaqi-cache'), 'HIT')
    assert.equal(hit.headers.get('cache-control'), `public, max-age=${expected}`, `age ${age}`)
  }
  assert.equal(h.calls.length, 1)
})
