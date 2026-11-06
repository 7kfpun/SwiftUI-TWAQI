#!/usr/bin/env node
// FOX-100: `twaqi_push_devices` takes Android devices. Adds the `platform`
// field (`ios` | `android`, default `ios`, so every existing row reads ios),
// lets `device_token` (the APNs token) be empty, since an Android device has
// none, and lets the push Worker's policy write `platform` if its device
// permissions list fields one by one.
//
// Run it with --apply before the Worker that sends `platform` deploys: the
// Worker writes `platform` on every PUT /app/v1/device.
//
// Idempotent: changes only what is missing and leaves everything else alone.
// Deletes nothing.
//
//   DIRECTUS_ADMIN_TOKEN=… DIRECTUS_URL=… node directus/push-devices-platform.mjs           # show the plan
//   DIRECTUS_ADMIN_TOKEN=… DIRECTUS_URL=… node directus/push-devices-platform.mjs --apply   # make it so
//
// The admin token is read from the environment only and never printed.

const BASE = (process.env.DIRECTUS_URL || '').replace(/\/+$/, '')
const TOKEN = process.env.DIRECTUS_ADMIN_TOKEN
const APPLY = process.argv.includes('--apply')
const COLLECTION = 'twaqi_push_devices'
const WORKER_POLICY = 'TWAQI Push Worker'

export const platformField = {
  field: 'platform',
  type: 'string',
  meta: {
    interface: 'select-dropdown',
    options: { choices: [{ text: 'iOS', value: 'ios' }, { text: 'Android', value: 'android' }] },
    width: 'half',
    note: 'Set by the app through the push Worker (FOX-100). Builds before it send none, and are iOS.',
  },
  schema: { max_length: 16, default_value: 'ios', is_nullable: false },
}

/** What `device_token` needs to change, or null when it already allows empty. */
export function deviceTokenChange(field) {
  const required = field?.meta?.required === true
  const notNull = field?.schema?.is_nullable === false
  if (!required && !notNull) return null
  return {
    ...(required ? { meta: { required: false } } : {}),
    ...(notNull ? { schema: { is_nullable: true } } : {}),
  }
}

/** The fields list a permission needs to write `platform`, or null when it already can. */
export function permissionFields(fields) {
  const list = Array.isArray(fields) ? fields : typeof fields === 'string' ? fields.split(',') : []
  if (list.includes('*') || list.includes('platform')) return null
  return [...list, 'platform']
}

async function api(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/json',
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await res.text()
  const json = text ? JSON.parse(text) : {}
  return { status: res.status, ok: res.ok, data: json.data, errors: json.errors }
}

async function step(label, run) {
  if (!APPLY) return console.log(`would ${label}`)
  const res = await run()
  if (!res.ok) throw new Error(`${label}: ${res.status} ${JSON.stringify(res.errors ?? '').slice(0, 300)}`)
  console.log(`done: ${label}`)
}

async function main() {
  if (!BASE) throw new Error('Set DIRECTUS_URL (the Directus base URL).')
  if (!TOKEN) throw new Error('Set DIRECTUS_ADMIN_TOKEN (an admin user token; it is not printed).')
  const me = await api('GET', '/users/me?fields=id')
  if (!me.ok) throw new Error(`token rejected: ${me.status}`)

  const platform = await api('GET', `/fields/${COLLECTION}/platform`)
  if (platform.ok && platform.data) {
    console.log(`${COLLECTION}.platform exists`)
  } else {
    await step(`add field ${COLLECTION}.platform (string, default ios)`, () => api('POST', `/fields/${COLLECTION}`, platformField))
  }

  const token = await api('GET', `/fields/${COLLECTION}/device_token`)
  if (!token.ok) throw new Error(`${COLLECTION}.device_token not readable: ${token.status}`)
  const change = deviceTokenChange(token.data)
  if (change) {
    await step(`let ${COLLECTION}.device_token be empty (${JSON.stringify(change)})`, () =>
      api('PATCH', `/fields/${COLLECTION}/device_token`, change),
    )
  } else {
    console.log(`${COLLECTION}.device_token may already be empty`)
  }

  const policies = await api('GET', `/policies?filter[name][_eq]=${encodeURIComponent(WORKER_POLICY)}&fields=id,name`)
  const policy = policies.data?.[0]
  if (!policy) throw new Error(`policy "${WORKER_POLICY}" not found`)
  for (const action of ['create', 'update', 'read']) {
    const perms = await api(
      'GET',
      `/permissions?filter[policy][_eq]=${policy.id}&filter[collection][_eq]=${COLLECTION}&filter[action][_eq]=${action}&fields=id,fields`,
    )
    const perm = perms.data?.[0]
    if (!perm) {
      console.log(`warning: "${WORKER_POLICY}" has no ${action} permission on ${COLLECTION}`)
      continue
    }
    const next = permissionFields(perm.fields)
    if (!next) {
      console.log(`"${WORKER_POLICY}" may already ${action} ${COLLECTION}.platform`)
      continue
    }
    await step(`let "${WORKER_POLICY}" ${action} ${COLLECTION}.platform`, () => api('PATCH', `/permissions/${perm.id}`, { fields: next }))
  }

  if (!APPLY) console.log('\nNothing written. Run again with --apply to make these changes.')
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(String(e.message ?? e))
    process.exit(1)
  })
}
