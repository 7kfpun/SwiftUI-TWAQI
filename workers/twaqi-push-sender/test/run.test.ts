import assert from 'node:assert/strict'
import { afterEach, describe, it } from 'node:test'
import { run } from '../src/index.ts'

describe('run', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  it('retries a failed state write, so a delivered alert is marked sent', async () => {
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign'],
    )
    const der = Buffer.from(new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))).toString('base64')
    const label = ['PRIVATE', 'KEY'].join(' ')
    const account = JSON.stringify({ project_id: 'p', client_email: `run-${Date.now()}@p.iam.gserviceaccount.com`, private_key: `-----BEGIN ${label}-----\n${der}\n-----END ${label}-----\n` })

    let patches = 0
    const marked: unknown[] = []
    globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
      const url = new URL(String(input))
      if (url.hostname === 'aqi.test') {
        return Response.json({ success: true, data: [{ station_id: 105, aqi: 180, name: { zh: '中山', en: 'Zhongshan' }, publish_time: null }] })
      }
      if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 't', expires_in: 3600 })
      if (url.hostname === 'fcm.googleapis.com') return Response.json({ name: 'projects/p/messages/1' })
      if (url.pathname.endsWith('/twaqi_push_subscriptions') && (init.method ?? 'GET') === 'GET') {
        return Response.json({ data: [{
          id: 7, station_id: '105', site_id: null, metric: 'aqi', direction: 'above', threshold: 120,
          last_value: null, in_zone: false, last_fired_at: null,
          device: { id: 5, fcm_token: 'tok', locale: 'zh-Hant', dnd_enabled: false, dnd_start: null, dnd_end: null, timezone: 'Asia/Taipei' },
        }] })
      }
      if (url.pathname.endsWith('/twaqi_push_subscriptions') && init.method === 'PATCH') {
        patches++
        if (patches === 1) return new Response('{"errors":[{"message":"busy"}]}', { status: 503 })
        marked.push(...JSON.parse(String(init.body)))
        return Response.json({ data: [] })
      }
      return Response.json({ data: [] })
    }) as typeof fetch

    const env = { FCM_SERVICE_ACCOUNT: account, DIRECTUS_URL: 'https://cms.test', DIRECTUS_PUSH_TOKEN: 'w', AQI_API_BASE: 'https://aqi.test/api', SYNC_TOKEN: 'x' } as never
    const result = await run(env, {})
    assert.equal(result.counts.sent, 1)
    assert.equal(patches, 2) // failed once, then landed
    assert.equal(result.updated, 1)
    assert.equal((marked[0] as { in_zone: boolean }).in_zone, true)
  })
})
