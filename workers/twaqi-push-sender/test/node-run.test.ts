import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { afterEach, describe, it } from 'node:test'
import { run } from '../src/index.ts'
import { failure, nodeEnv, parseArgs, parseJsonc } from '../scripts/run.ts'

// The GitHub Actions runner (FOX-71): run() with a plain env object built from
// wrangler.jsonc's vars and three secrets, no Worker bindings.
const config = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8')
const secrets = { FCM_SERVICE_ACCOUNT: '{}', DIRECTUS_PUSH_TOKEN: 'w', AQI_API_BASE: 'https://aqi.test/api', SYNC_TOKEN: 's' }

describe('nodeEnv', () => {
  it('is the wrangler vars plus the secrets, with no bindings and no subrequest cap', () => {
    const env = nodeEnv(config, { ...secrets, UNRELATED: 'x' }) as unknown as Record<string, unknown>
    const vars = parseJsonc(config).vars as Record<string, string>
    assert.equal(env.DIRECTUS_URL, vars.DIRECTUS_URL)
    assert.equal(env.MAX_SENDS_PER_RUN, '45000') // the cap stays
    assert.equal(env.DIRECTUS_PUSH_TOKEN, 'w')
    assert.equal(Number(env.SUBREQUEST_LIMIT), Infinity)
    assert.equal(env.PUSH_EVENTS, undefined)
    assert.equal(env.APP_LIMITER, undefined)
    assert.equal(env.UNRELATED, undefined)
  })

  it('refuses to run with a secret missing', () => {
    assert.throws(() => nodeEnv(config, { ...secrets, AQI_API_BASE: '' }), /Missing secrets: AQI_API_BASE/)
  })

  it('fails the job on a failed send, not on dead tokens or deferred sends (Codex review)', () => {
    const result = (counts: Record<string, number>) => ({ counts }) as unknown as Parameters<typeof failure>[0]
    assert.equal(failure(result({ sent: 10 })), null)
    assert.equal(failure(result({ sent: 10, 'dead-token': 2, deferred: 5 })), null)
    assert.match(failure(result({ sent: 10, failed: 3 })) ?? '', /^3 alert\(s\) failed to send/)
    // A failed forecast heads-up counts too (FOX-191).
    assert.match(failure(result({ sent: 1 }), { counts: { failed: 2 } }) ?? '', /^2 alert\(s\) failed to send/)
  })

  it('takes only --dry-run', () => {
    assert.deepEqual(parseArgs([]), { dryRun: false })
    assert.deepEqual(parseArgs(['--dry-run']), { dryRun: true })
    assert.throws(() => parseArgs(['--dry']), /Unknown arguments: --dry/)
  })
})

describe('run under Node', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  it('sends every alert with a plain env: no Analytics Engine, not stopped by the Worker limit', async () => {
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign'],
    )
    const der = Buffer.from(new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))).toString('base64')
    const label = ['PRIVATE', 'KEY'].join(' ')
    const account = JSON.stringify({ project_id: 'p', client_email: `node-${Date.now()}@p.iam.gserviceaccount.com`, private_key: `-----BEGIN ${label}-----\n${der}\n-----END ${label}-----\n` })

    const marked = new Set<number>()
    const logged: unknown[] = []
    let fcm = 0
    globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
      const url = new URL(String(input))
      if (url.hostname === 'aqi.test') {
        return Response.json({ success: true, data: [{ station_id: 105, aqi: 180, name: { en: 'Zhongshan' }, publish_time: null }] })
      }
      if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 't', expires_in: 3600 })
      if (url.hostname === 'fcm.googleapis.com') {
        fcm++
        // One dead token, so a Directus log row is written too.
        if (JSON.parse(String(init.body)).message.token === 'tok0') {
          return new Response('{"error":{"status":"NOT_FOUND","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}', { status: 404 })
        }
        return Response.json({ name: `m/${fcm}` })
      }
      if (url.pathname.endsWith('/twaqi_push_subscriptions') && (init.method ?? 'GET') === 'GET') {
        return Response.json({ data: Array.from({ length: 300 }, (_, k) => ({
          id: k + 1, station_id: '105', site_id: null, metric: 'aqi', direction: 'above', threshold: 120,
          last_value: null, in_zone: false, last_fired_at: null,
          device: { id: 1000 + k, fcm_token: `tok${k}`, locale: 'en', dnd_enabled: false, dnd_start: null, dnd_end: null, timezone: 'Asia/Taipei' },
        })) })
      }
      if (url.pathname.endsWith('/twaqi_push_subscriptions') && init.method === 'PATCH') {
        for (const row of JSON.parse(String(init.body))) marked.add(row.id)
      }
      if (url.pathname.endsWith('/twaqi_push_logs') && init.method === 'POST') {
        logged.push(...[JSON.parse(String(init.body))].flat())
      }
      return Response.json({ data: [] })
    }) as typeof fetch

    // wrangler.jsonc's SUBREQUEST_LIMIT (50) alone would defer all of these.
    const result = await run(nodeEnv(config, { ...secrets, FCM_SERVICE_ACCOUNT: account }), {})
    assert.equal(result.counts.sent, 299)
    assert.equal(result.counts['dead-token'], 1)
    assert.equal(result.counts.deferred, undefined)
    assert.equal(marked.size, 299) // every alert sent is marked sent
    assert.deepEqual(result.archivedDevices, [1000])
    assert.equal(result.events, 0) // no PUSH_EVENTS binding
    assert.equal(result.logged, 1)
    assert.equal(logged.length, 1)
  })
})

describe('run under Node, FCM refusing', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  it('finishes and saves state, and its result fails the job', async () => {
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign'],
    )
    const der = Buffer.from(new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))).toString('base64')
    const label = ['PRIVATE', 'KEY'].join(' ')
    const account = JSON.stringify({ project_id: 'p', client_email: `refuse-${Date.now()}@p.iam.gserviceaccount.com`, private_key: `-----BEGIN ${label}-----\n${der}\n-----END ${label}-----\n` })

    const logged: unknown[] = []
    globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
      const url = new URL(String(input))
      if (url.hostname === 'aqi.test') {
        return Response.json({ success: true, data: [{ station_id: 105, aqi: 180, name: { en: 'Zhongshan' }, publish_time: null }] })
      }
      if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 't', expires_in: 3600 })
      if (url.hostname === 'fcm.googleapis.com') return new Response('{"error":{"status":"PERMISSION_DENIED"}}', { status: 403 })
      if (url.pathname.endsWith('/twaqi_push_subscriptions') && (init.method ?? 'GET') === 'GET') {
        return Response.json({ data: [1, 2].map((k) => ({
          id: k, station_id: '105', site_id: null, metric: 'aqi', direction: 'above', threshold: 120,
          last_value: null, in_zone: false, last_fired_at: null,
          device: { id: 1000 + k, fcm_token: `tok${k}`, locale: 'en', dnd_enabled: false, dnd_start: null, dnd_end: null, timezone: 'Asia/Taipei' },
        })) })
      }
      if (url.pathname.endsWith('/twaqi_push_logs') && init.method === 'POST') {
        logged.push(...[JSON.parse(String(init.body))].flat())
      }
      return Response.json({ data: [] })
    }) as typeof fetch

    const result = await run(nodeEnv(config, { ...secrets, FCM_SERVICE_ACCOUNT: account }), {})
    assert.equal(result.counts.failed, 2)
    assert.equal(logged.length, 2) // the failures reached Directus before the job fails
    assert.match(failure(result) ?? '', /^2 alert\(s\) failed to send/)
  })
})
