// Run with `npm test` (Node 23.6+ strips the types; no extra dependencies).
import assert from 'node:assert/strict'
import { afterEach, test } from 'node:test'
import { normalizeAdvisories, syncAdvisories, type AdvisoryEnv } from '../src/advisories.ts'

const realFetch = globalThis.fetch
afterEach(() => {
  globalThis.fetch = realFetch
})

const ENV: AdvisoryEnv = {
  MOENV_API_KEY: 'k',
  DIRECTUS_URL: 'https://directus.test',
  DIRECTUS_FORECAST_TOKEN: 't',
  MOENV_ADVISORY_URL: 'https://moenv.test/sandst',
}

test('normalize: needs a PublishTime and text; case-insensitive keys; slashes become Taiwan-local datetimes', () => {
  const rows = normalizeAdvisories([
    { PublishTime: '2026/11/08 09:30', Subject: '沙塵暴預報', Content: '東北季風挾帶沙塵' },
    { publishtime: '2026-11-07 08:00:00', subject: '-', content: '較早的公告' },
    { PublishTime: '', Subject: 'no time', Content: 'x' },
    { PublishTime: '2026-11-06 08:00:00', Subject: ' ', Content: '' },
    { PublishTime: '2026-11-08 09:30:00', Subject: '重複', Content: '同一時間' },
  ])
  assert.deepEqual(rows, [
    { publish_time: '2026-11-07 08:00:00', subject: null, content: '較早的公告', source: 'SANDST_P_01' },
    { publish_time: '2026-11-08 09:30:00', subject: '重複', content: '同一時間', source: 'SANDST_P_01' },
  ])
})

test('sync: creates only unseen publish times, archives old rows', async () => {
  const calls: { method: string; url: string; body?: unknown }[] = []
  globalThis.fetch = (async (input: URL | string, init?: RequestInit) => {
    const url = String(input)
    const method = init?.method ?? 'GET'
    calls.push({ method, url, body: init?.body ? JSON.parse(String(init.body)) : undefined })
    if (url.startsWith('https://moenv.test')) {
      return new Response(
        JSON.stringify([
          { PublishTime: '2026-11-08 09:30:00', Subject: 'A', Content: 'a' },
          { PublishTime: '2026-11-08 12:00:00', Subject: 'B', Content: 'b' },
        ]),
      )
    }
    if (method === 'GET' && url.includes('fields=publish_time')) return new Response(JSON.stringify({ data: [{ publish_time: '2026-11-08 09:30:00' }] }))
    if (method === 'GET') return new Response(JSON.stringify({ data: [{ id: 4 }] }))
    return new Response('{}')
  }) as typeof fetch

  const result = await syncAdvisories(ENV)
  assert.equal(result.created, 1)
  assert.equal(result.unchanged, 1)
  assert.equal(result.archived, 1)
  assert.equal(result.latestPublishTime, '2026-11-08 12:00:00')
  const post = calls.find((c) => c.method === 'POST')!
  assert.deepEqual(post.body, [{ publish_time: '2026-11-08 12:00:00', subject: 'B', content: 'b', source: 'SANDST_P_01', archived: false }])
  assert.deepEqual(calls.find((c) => c.method === 'PATCH')!.body, { keys: [4], data: { archived: true } })
})

test('sync: an empty feed is "no advisory", not an error, and creates nothing', async () => {
  const methods: string[] = []
  globalThis.fetch = (async (input: URL | string, init?: RequestInit) => {
    methods.push(init?.method ?? 'GET')
    return String(input).startsWith('https://moenv.test') ? new Response('[]') : new Response(JSON.stringify({ data: [] }))
  }) as typeof fetch
  const result = await syncAdvisories(ENV)
  assert.equal(result.rows, 0)
  assert.equal(result.created, 0)
  assert.ok(!methods.includes('POST'))
})

test('sync: a MOENV failure throws and touches nothing in Directus', async () => {
  const urls: string[] = []
  globalThis.fetch = (async (input: URL | string) => {
    urls.push(String(input))
    return new Response('api_key 不存在。')
  }) as typeof fetch
  await assert.rejects(() => syncAdvisories(ENV), /not JSON/)
  assert.deepEqual(urls, ['https://moenv.test/sandst'])
})
