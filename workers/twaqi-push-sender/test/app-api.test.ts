import assert from 'node:assert/strict'
import { afterEach, beforeEach, describe, it } from 'node:test'
import { handleApp, plan, sha256 } from '../src/app-api.ts'

// An in-memory Directus with just the REST the app API uses.
type Row = Record<string, unknown> & { id: number }
let tables: Record<string, Row[]>
let nextId: number
const realFetch = globalThis.fetch

function fakeDirectus(url: string, init: RequestInit = {}): Response {
  const u = new URL(url)
  const [, , collection, id] = u.pathname.split('/') // /items/<collection>/<id>
  const rows = tables[collection]
  const method = init.method ?? 'GET'
  const body = init.body ? JSON.parse(String(init.body)) : undefined
  const filters = [...u.searchParams].flatMap(([k, v]) => {
    const m = /^filter\[(\w+)\]\[_eq\]$/.exec(k)
    return m ? [[m[1], v] as const] : []
  })
  const match = (row: Row) => filters.every(([field, value]) => String(row[field]) === value)
  if (method === 'GET' && id) return Response.json({ data: rows.find((r) => r.id === Number(id)) ?? null })
  if (method === 'GET') return Response.json({ data: rows.filter(match).sort((a, b) => a.id - b.id) })
  if (method === 'POST') {
    if (collection === 'twaqi_push_devices' && rows.some((r) => r.device_id === body.device_id || (body.device_token != null && r.device_token === body.device_token))) {
      return new Response('{"errors":[{"message":"unique"}]}', { status: 400 })
    }
    const row = { id: nextId++, ...body }
    rows.push(row)
    return Response.json({ data: { id: row.id } })
  }
  if (method === 'PATCH' && id) {
    Object.assign(rows.find((r) => r.id === Number(id)) as Row, body)
    return Response.json({ data: { id: Number(id) } })
  }
  if (method === 'PATCH') {
    for (const row of rows.filter((r) => body.keys.includes(r.id))) Object.assign(row, body.data)
    return Response.json({ data: [] })
  }
  return new Response('unsupported', { status: 500 })
}

const env = { DIRECTUS_URL: 'https://cms.test', DIRECTUS_PUSH_TOKEN: 'worker' }
const ME = '6f1c2e7a-0000-4000-8000-000000000001'
const SECRET = 'a'.repeat(43)
const TOKEN = 'ab'.repeat(32)

function call(method: string, path: string, body?: unknown, who = { id: ME, secret: SECRET }) {
  const request = new Request(`https://push.test${path}`, {
    method,
    headers: { 'X-Device-Id': who.id, Authorization: `Bearer ${who.secret}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  return handleApp(request, env).then(async (res) => ({ status: res!.status, body: await res!.json() }))
}

const device = (over: Record<string, unknown> = {}) => ({
  device_id: ME, device_token: TOKEN, fcm_token: 'fcm', environment: 'production',
  app_version: '3.1.4', locale: 'zh-Hant', is_pro: false, last_seen_at: '2026-11-03T00:00:00Z',
  dnd_enabled: false, dnd_start: '22:00', dnd_end: '07:00', timezone: 'Asia/Taipei', archived: false, ...over,
})

beforeEach(() => {
  tables = { twaqi_push_devices: [], twaqi_push_subscriptions: [] }
  nextId = 1
  globalThis.fetch = (async (url: string, init?: RequestInit) => fakeDirectus(String(url), init)) as typeof fetch
})
afterEach(() => {
  globalThis.fetch = realFetch
})

describe('app API auth', () => {
  it('needs a device id and a secret', async () => {
    assert.equal((await call('PUT', '/app/v1/device', device(), { id: 'nope', secret: SECRET })).status, 401)
    assert.equal((await call('PUT', '/app/v1/device', device(), { id: ME, secret: 'short' })).status, 401)
  })

  it('creates the row with only a hash of the secret', async () => {
    const res = await call('PUT', '/app/v1/device', device())
    assert.deepEqual(res, { status: 200, body: { id: 1, created: true } })
    const row = tables.twaqi_push_devices[0]
    assert.equal(row.device_id, ME)
    assert.equal(row.secret_hash, await sha256(SECRET))
    assert.equal(JSON.stringify(row).includes(SECRET), false)
  })

  it('refuses another secret for the same device id', async () => {
    await call('PUT', '/app/v1/device', device())
    const thief = await call('PUT', '/app/v1/device', device({ fcm_token: 'stolen' }), { id: ME, secret: 'b'.repeat(43) })
    assert.equal(thief.status, 403)
    assert.equal(tables.twaqi_push_devices[0].fcm_token, 'fcm')
    assert.equal((await call('PUT', '/app/v1/stations/105', { above: 100 }, { id: ME, secret: 'b'.repeat(43) })).status, 403)
  })

  it('never hands over a row from before the secret: it is retired with its alerts', async () => {
    tables.twaqi_push_devices.push({ id: 7, ...device(), secret_hash: null })
    tables.twaqi_push_subscriptions.push({ id: 70, device: 7, station_id: '105', direction: 'above', threshold: 120, enabled: true, archived: false })
    nextId = 8
    // Not even a restore reads it.
    assert.deepEqual((await call('GET', '/app/v1/device')).body, { device: null, subscriptions: [] })

    assert.deepEqual((await call('PUT', '/app/v1/device', device())).body, { id: 8, created: true })
    const [old, fresh] = tables.twaqi_push_devices
    assert.deepEqual([old.archived, old.device_id, old.device_token, old.fcm_token], [true, 'retired-7', 'retired-7', null])
    assert.equal(fresh.secret_hash, await sha256(SECRET))
    assert.equal(tables.twaqi_push_subscriptions[0].archived, true)
    // The new row starts empty; the app sends its own alerts again.
    assert.deepEqual((await call('GET', '/app/v1/device')).body.subscriptions, [])
  })

  it('stops the takeover Codex described: a known device_id buys nothing', async () => {
    // A victim's row from an older build, whose device_id an attacker read
    // with the old shared token.
    tables.twaqi_push_devices.push({ id: 7, ...device(), secret_hash: null })
    tables.twaqi_push_subscriptions.push({ id: 70, device: 7, station_id: '105', direction: 'above', threshold: 120, enabled: true, archived: false })
    nextId = 8
    const attacker = { id: ME, secret: 'e'.repeat(43) }
    await call('PUT', '/app/v1/device', device({ device_token: 'cd'.repeat(32), fcm_token: 'attacker' }), attacker)
    // The victim's alerts were archived, not moved to the attacker's row.
    assert.deepEqual((await call('GET', '/app/v1/device', undefined, attacker)).body.subscriptions, [])
    assert.equal(tables.twaqi_push_subscriptions.find((r) => r.id === 70)?.archived, true)
    // The real app now gets 403 for that id, and starts over with a new one.
    assert.equal((await call('PUT', '/app/v1/device', device())).status, 403)
  })

  it('retires an older row holding this APNs token instead of adopting it', async () => {
    tables.twaqi_push_devices.push({ id: 3, ...device({ device_id: null }), secret_hash: null })
    nextId = 4
    assert.deepEqual((await call('PUT', '/app/v1/device', device())).body, { id: 4, created: true })
    assert.equal(tables.twaqi_push_devices[0].archived, true)
    assert.equal(tables.twaqi_push_devices[0].device_token, 'retired-3')
  })

  it('updates its own row in place', async () => {
    await call('PUT', '/app/v1/device', device())
    assert.deepEqual((await call('PUT', '/app/v1/device', device({ locale: 'en' }))).body, { id: 1, created: false })
    assert.equal(tables.twaqi_push_devices.length, 1)
    assert.equal(tables.twaqi_push_devices[0].locale, 'en')
  })

  it('writes only the fields the app may set', async () => {
    await call('PUT', '/app/v1/device', { ...device(), secret_hash: 'x', in_zone: true, id: 99 })
    const row = tables.twaqi_push_devices[0]
    assert.equal(row.id, 1)
    assert.equal(row.secret_hash, await sha256(SECRET))
    assert.equal('in_zone' in row, false)
  })
})

describe('app API platforms (FOX-100)', () => {
  // What the Android app sends from FOX-100 on: no device_token unless a test gives one.
  const android = (over: Record<string, unknown> = {}) => {
    const body: Record<string, unknown> = device({ platform: 'android', fcm_token: 'fcm:android', ...over })
    if (!('device_token' in over)) delete body.device_token
    return body
  }

  it('stores ios for a body without a platform, as every iOS build sends', async () => {
    assert.equal((await call('PUT', '/app/v1/device', device())).status, 200)
    assert.equal(tables.twaqi_push_devices[0].platform, 'ios')
    assert.equal(tables.twaqi_push_devices[0].device_token, TOKEN)
  })

  it('keeps iOS validation: an iOS row still needs a hex APNs token', async () => {
    const noToken: Record<string, unknown> = device()
    delete noToken.device_token
    assert.equal((await call('PUT', '/app/v1/device', noToken)).status, 400)
    assert.equal((await call('PUT', '/app/v1/device', device({ platform: 'ios' }))).status, 200)
    assert.equal((await call('PUT', '/app/v1/device', device({ platform: 'ios', device_token: null }))).status, 400)
    assert.equal((await call('PUT', '/app/v1/device', device({ device_token: 'not-hex' }))).status, 400)
    assert.equal((await call('PUT', '/app/v1/device', device({ environment: undefined }))).status, 400)
  })

  it('refuses a platform it does not know', async () => {
    assert.equal((await call('PUT', '/app/v1/device', device({ platform: 'web' }))).status, 400)
    assert.equal((await call('PUT', '/app/v1/device', device({ platform: 1 }))).status, 400)
    assert.equal(tables.twaqi_push_devices.length, 0)
  })

  it('stores an Android device with no device_token, and its alerts', async () => {
    assert.deepEqual(await call('PUT', '/app/v1/device', android()), { status: 200, body: { id: 1, created: true } })
    const row = tables.twaqi_push_devices[0]
    assert.equal(row.platform, 'android')
    assert.equal(row.fcm_token, 'fcm:android')
    assert.equal('device_token' in row, false)
    assert.equal((await call('PUT', '/app/v1/stations/105', { site_id: '015', above: 120 })).status, 200)
    const subs = (await call('GET', '/app/v1/device')).body.subscriptions as Row[]
    assert.deepEqual(subs.map((s) => [s.station_id, s.direction, s.threshold, s.enabled]), [['105', 'above', 120, true]])
    // Updated in place, still Android.
    assert.deepEqual((await call('PUT', '/app/v1/device', android({ locale: 'en' }))).body, { id: 1, created: false })
    assert.deepEqual([tables.twaqi_push_devices.length, row.platform, row.locale], [1, 'android', 'en'])
  })

  it('accepts a null device_token from Android', async () => {
    assert.equal((await call('PUT', '/app/v1/device', android({ device_token: null }))).status, 200)
    assert.equal(tables.twaqi_push_devices[0].platform, 'android')
  })

  it('keeps existing Android installs working: the 64-hex SHA-256 shim is accepted', async () => {
    const shim = await sha256(ME)
    assert.match(shim, /^[0-9a-f]{64}$/)
    assert.equal((await call('PUT', '/app/v1/device', android({ device_token: shim }))).status, 200)
    const row = tables.twaqi_push_devices[0]
    assert.deepEqual([row.platform, row.device_token, row.fcm_token], ['android', shim, 'fcm:android'])
    // A shim that is not hex is refused, as on iOS.
    assert.equal((await call('PUT', '/app/v1/device', android({ device_token: 'zz' }))).status, 400)
  })

  it('an Android row with no device_token retires nothing else', async () => {
    tables.twaqi_push_devices.push({ id: 3, ...device({ device_id: null }), secret_hash: null })
    nextId = 4
    assert.deepEqual((await call('PUT', '/app/v1/device', android())).body, { id: 4, created: true })
    assert.equal(tables.twaqi_push_devices[0].archived, false)
    // Two Android rows without a token don't collide.
    const other = { id: '6f1c2e7a-0000-4000-8000-000000000002', secret: 'c'.repeat(43) }
    assert.deepEqual((await call('PUT', '/app/v1/device', android(), other)).body, { id: 5, created: true })
  })
})

describe('app API alerts', () => {
  beforeEach(async () => {
    await call('PUT', '/app/v1/device', device())
  })

  it('sets one station\'s alerts and reads them back for a restore', async () => {
    assert.equal((await call('PUT', '/app/v1/stations/105', { site_id: '015', above: 120, below: 30 })).status, 200)
    const { body } = await call('GET', '/app/v1/device')
    const subs = (body as { subscriptions: Row[] }).subscriptions
    assert.deepEqual(subs.map((s) => [s.station_id, s.direction, s.threshold, s.site_id]), [
      ['105', 'above', 120, '015'],
      ['105', 'below', 30, '015'],
    ])
    assert.equal((body as { device: { dnd_start: string } }).device.dnd_start, '22:00')
  })

  it('archives a switched-off alert instead of deleting it', async () => {
    await call('PUT', '/app/v1/stations/105', { above: 120, below: 30 })
    await call('PUT', '/app/v1/stations/105', { above: 150, below: null })
    const rows = tables.twaqi_push_subscriptions
    assert.equal(rows.length, 2)
    assert.deepEqual(rows.map((r) => [r.direction, r.threshold, r.archived, r.enabled]), [
      ['above', 150, false, true],
      ['below', 30, true, false],
    ])
  })

  it('leaves the station limit to the app', async () => {
    for (const id of [1, 2, 3, 4]) assert.equal((await call('PUT', `/app/v1/stations/${id}`, { above: 100 })).status, 200)
    assert.equal(tables.twaqi_push_subscriptions.filter((r) => !r.archived).length, 4)
  })

  it('cancel-all archives only this device\'s alerts', async () => {
    await call('PUT', '/app/v1/stations/105', { above: 120 })
    tables.twaqi_push_subscriptions.push({ id: 500, device: 42, station_id: '105', direction: 'above', threshold: 90, enabled: true, archived: false })
    assert.deepEqual((await call('POST', '/app/v1/archive-all')).body, { archived: 1 })
    assert.equal(tables.twaqi_push_subscriptions.find((r) => r.id === 500)?.archived, false)
  })

  it('rejects bad thresholds and unknown routes', async () => {
    assert.equal((await call('PUT', '/app/v1/stations/105', { above: 'lots' })).status, 400)
    assert.equal((await call('PUT', '/app/v1/stations/105', { above: 9999 })).status, 400)
    assert.equal((await call('GET', '/app/v1/everything')).status, 404)
  })
})

describe('plan', () => {
  const row = (id: number, direction: 'above' | 'below', threshold: number, enabled = true) =>
    ({ id, station_id: '5', site_id: null, metric: 'aqi', direction, threshold, enabled })

  it('creates rows for new alerts', () => {
    assert.deepEqual(plan([], '5', 'A1', { above: 120, below: 30 }), {
      save: [
        { id: undefined, station_id: '5', site_id: 'A1', direction: 'above', threshold: 120 },
        { id: undefined, station_id: '5', site_id: 'A1', direction: 'below', threshold: 30 },
      ],
      archive: [],
    })
  })

  it('updates a changed threshold, archives what is off, and leaves a match alone', () => {
    assert.deepEqual(plan([row(1, 'above', 120), row(2, 'below', 30)], '5', null, { above: 150, below: null }), {
      save: [{ id: 1, station_id: '5', site_id: null, direction: 'above', threshold: 150 }],
      archive: [2],
    })
    assert.deepEqual(plan([row(1, 'above', 120)], '5', null, { above: 120, below: null }), { save: [], archive: [] })
  })

  it('archives duplicates from an earlier race', () => {
    assert.deepEqual(plan([row(1, 'above', 120), row(2, 'above', 120)], '5', null, { above: 120, below: null }), { save: [], archive: [2] })
  })
})

describe('twaqi_push_devices platform schema (FOX-100)', () => {
  it('adds platform with ios as the default, and only the values the Worker accepts', async () => {
    const { platformField } = await import('../directus/push-devices-platform.mjs')
    assert.equal(platformField.field, 'platform')
    assert.equal(platformField.schema.default_value, 'ios')
    assert.deepEqual(platformField.meta.options.choices.map((c: { value: string }) => c.value), ['ios', 'android'])
  })

  it('lets device_token be empty only where it is not yet', async () => {
    const { deviceTokenChange } = await import('../directus/push-devices-platform.mjs')
    assert.equal(deviceTokenChange({ meta: { required: false }, schema: { is_nullable: true } }), null)
    assert.deepEqual(deviceTokenChange({ meta: { required: true }, schema: { is_nullable: true } }), { meta: { required: false } })
    assert.deepEqual(deviceTokenChange({ meta: {}, schema: { is_nullable: false } }), { schema: { is_nullable: true } })
  })

  it('adds platform to a worker permission that lists fields, and leaves * alone', async () => {
    const { permissionFields } = await import('../directus/push-devices-platform.mjs')
    assert.equal(permissionFields(['*']), null)
    assert.equal(permissionFields('*'), null)
    assert.equal(permissionFields(['device_token', 'platform']), null)
    assert.deepEqual(permissionFields(['device_token', 'fcm_token']), ['device_token', 'fcm_token', 'platform'])
    assert.deepEqual(permissionFields(null), ['platform'])
  })
})
