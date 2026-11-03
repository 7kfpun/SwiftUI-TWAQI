import assert from 'node:assert/strict'
import { afterEach, describe, it } from 'node:test'
import { tokenSuffix } from '../src/directus.ts'
import { buildMessage, classifyError, isConfigured, parseServiceAccount, send } from '../src/fcm.ts'
import { alertText, isChinese, stationName, testText } from '../src/message.ts'

describe('buildMessage', () => {
  it('sends a visible alert with APNs headers and no badge', () => {
    const now = Date.parse('2026-11-03T06:00:00Z')
    const message = buildMessage(
      {
        token: 'tok',
        title: 'T',
        body: 'B',
        data: { station_id: '105' },
        collapseId: 'aqi-7',
        threadId: 'station-105',
        expiresInSeconds: 3600,
      },
      now,
    )
    assert.deepEqual(message, {
      token: 'tok',
      notification: { title: 'T', body: 'B' },
      data: { station_id: '105' },
      apns: {
        headers: { 'apns-priority': '10', 'apns-collapse-id': 'aqi-7', 'apns-expiration': String(now / 1000 + 3600) },
        payload: { aps: { sound: 'default', 'thread-id': 'station-105' } },
      },
    })
  })

  it('leaves out empty data and optional headers', () => {
    const message = buildMessage({ token: 'tok', title: 'T', body: 'B', data: {} })
    assert.equal('data' in message, false)
    assert.deepEqual(message.apns, { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } })
  })
})

describe('classifyError', () => {
  const fcmError = (status: string, errorCode: string, message = '') => ({
    error: { status, message, details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode }] },
  })

  it('treats an unregistered token as dead', () => {
    assert.deepEqual(classifyError(404, fcmError('NOT_FOUND', 'UNREGISTERED')), { errorCode: 'UNREGISTERED', deadToken: true })
  })

  it('treats a token from another Firebase project as dead', () => {
    assert.equal(classifyError(403, fcmError('PERMISSION_DENIED', 'SENDER_ID_MISMATCH')).deadToken, true)
  })

  it('treats a malformed token as dead, but not a malformed message', () => {
    const badToken = fcmError('INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'The registration token is not a valid FCM registration token')
    assert.equal(classifyError(400, badToken).deadToken, true)
    const badPayload = fcmError('INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'Invalid value at message.data')
    assert.deepEqual(classifyError(400, badPayload), { errorCode: 'INVALID_ARGUMENT', deadToken: false })
  })

  it('keeps the token on outages, quota and auth errors', () => {
    assert.equal(classifyError(503, fcmError('UNAVAILABLE', 'UNAVAILABLE')).deadToken, false)
    assert.equal(classifyError(429, fcmError('RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED')).deadToken, false)
    assert.equal(classifyError(401, fcmError('UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR')).deadToken, false)
    assert.deepEqual(classifyError(500, null), { errorCode: 'HTTP_500', deadToken: false })
  })
})

describe('parseServiceAccount', () => {
  it('names the missing field without echoing the key', () => {
    assert.throws(() => parseServiceAccount(undefined), /not set/)
    assert.throws(() => parseServiceAccount('nope'), /not JSON/)
    assert.throws(() => parseServiceAccount('{"project_id":"p","client_email":"e"}'), /no private_key/)
    assert.equal(isConfigured({ FCM_SERVICE_ACCOUNT: '{"project_id":"p"}' }), false)
  })
})

describe('send', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  it('signs an RS256 assertion, exchanges it, and posts to the project', async () => {
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign', 'verify'],
    )
    const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))
    const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString('base64')}\n-----END PRIVATE KEY-----\n`
    const account = JSON.stringify({ project_id: 'kf-twaqi', client_email: 'sender@kf-twaqi.iam.gserviceaccount.com', private_key: pem })

    const calls: { url: string; body: string }[] = []
    globalThis.fetch = (async (url: string, init: RequestInit) => {
      calls.push({ url: String(url), body: String(init.body) })
      if (String(url).startsWith('https://oauth2.googleapis.com/')) {
        return new Response(JSON.stringify({ access_token: 'ya29.test', expires_in: 3600 }), { status: 200 })
      }
      assert.equal((init.headers as Record<string, string>).Authorization, 'Bearer ya29.test')
      return new Response(JSON.stringify({ name: 'projects/kf-twaqi/messages/123' }), { status: 200 })
    }) as typeof fetch

    const res = await send({ FCM_SERVICE_ACCOUNT: account }, { token: 'tok', title: 'T', body: 'B' })
    assert.deepEqual(res, { ok: true, status: 200, messageId: 'projects/kf-twaqi/messages/123', deadToken: false })

    const assertion = new URLSearchParams(calls[0].body).get('assertion') ?? ''
    const [header, claims, signature] = assertion.split('.')
    const decode = (s: string) => JSON.parse(Buffer.from(s, 'base64url').toString())
    assert.deepEqual(decode(header), { alg: 'RS256', typ: 'JWT' })
    const c = decode(claims)
    assert.equal(c.iss, 'sender@kf-twaqi.iam.gserviceaccount.com')
    assert.equal(c.scope, 'https://www.googleapis.com/auth/firebase.messaging')
    assert.equal(c.aud, 'https://oauth2.googleapis.com/token')
    assert.equal(c.exp - c.iat, 3600)
    const verified = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      pair.publicKey,
      Buffer.from(signature, 'base64url'),
      new TextEncoder().encode(`${header}.${claims}`),
    )
    assert.equal(verified, true)

    assert.equal(calls[1].url, 'https://fcm.googleapis.com/v1/projects/kf-twaqi/messages:send')
    assert.equal(JSON.parse(calls[1].body).message.token, 'tok')

    // The access token is reused on the next send.
    await send({ FCM_SERVICE_ACCOUNT: account }, { token: 'tok2', title: 'T', body: 'B' })
    assert.equal(calls.length, 3)
    assert.ok(calls[2].url.startsWith('https://fcm.googleapis.com/'))

    // A dead token comes back as such.
    globalThis.fetch = (async () =>
      new Response(
        JSON.stringify({
          error: { status: 'NOT_FOUND', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] },
        }),
        { status: 404 },
      )) as typeof fetch
    const dead = await send({ FCM_SERVICE_ACCOUNT: account }, { token: 'gone', title: 'T', body: 'B' })
    assert.deepEqual(dead, { ok: false, status: 404, errorCode: 'UNREGISTERED', deadToken: true })
  })
})

describe('alert text', () => {
  it('follows the app language the device reports', () => {
    assert.equal(isChinese('zh-Hant'), true)
    assert.equal(isChinese('en'), false)
    assert.equal(isChinese(null), false)
  })

  it('names the station in that language, falling back to the other', () => {
    const names = { nameZh: '中山', nameEn: 'Zhongshan' }
    assert.equal(stationName('zh-Hant', names, 105), '中山')
    assert.equal(stationName('en', names, 105), 'Zhongshan')
    assert.equal(stationName('en', { nameZh: '中山', nameEn: null }, 105), '中山')
    assert.equal(stationName('en', { nameZh: null, nameEn: null }, 105), '#105')
  })

  it('says which way the AQI crossed, with rounded numbers', () => {
    assert.deepEqual(alertText('above', 'zh-Hant', '中山', 135.4, 120), {
      title: '中山 AQI 135',
      body: '空氣品質指標已高於你設定的 120，外出請留意。',
    })
    assert.deepEqual(alertText('below', 'en', 'Zhongshan', 24, 30), {
      title: 'Zhongshan: AQI 24',
      body: 'Air quality is now below your alert level of 30. The air has cleared up.',
    })
    assert.equal(testText('zh-Hant').title, '台灣空氣 測試通知')
  })
})

describe('push logs', () => {
  it('keep only the end of the token', () => {
    assert.equal(tokenSuffix('abcdefghijklmnop'), 'klmnop')
    assert.equal(tokenSuffix('abc'), 'abc')
  })
})

describe('twaqi_push_logs schema', () => {
  it('has a field for everything the Worker writes, and an archive flag', async () => {
    const { fields, collection } = await import('../directus/push-logs.mjs')
    const names = new Set(fields.map((f: { field: string }) => f.field))
    // Keys of PushLog plus the archived flag writeLogs adds.
    for (const key of ['token_suffix', 'status', 'station', 'trigger', 'device', 'aqi', 'fcm_message_id', 'error_code', 'archived']) {
      assert.ok(names.has(key), key)
    }
    assert.equal(collection.meta.archive_field, 'archived')
  })
})
