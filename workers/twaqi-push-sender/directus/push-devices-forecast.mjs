#!/usr/bin/env node
// FOX-191: `twaqi_push_devices` remembers the last forecast heads-up it was
// sent: `forecast_sent_at` (timestamp) and `forecast_digest` (string), so the
// sender pushes at most once per Taiwan day and never repeats an unchanged
// forecast. Also lets the push Worker's policy read and update them if its
// device permissions list fields one by one.
//
// Run it with --apply before the sender that reads them deploys.
// Idempotent: adds only what is missing. Deletes nothing.
//
//   DIRECTUS_ADMIN_TOKEN=… DIRECTUS_URL=… node directus/push-devices-forecast.mjs           # show the plan
//   DIRECTUS_ADMIN_TOKEN=… DIRECTUS_URL=… node directus/push-devices-forecast.mjs --apply   # make it so
//
// The admin token is read from the environment only and never printed.

const BASE = (process.env.DIRECTUS_URL || '').replace(/\/+$/, '')
const TOKEN = process.env.DIRECTUS_ADMIN_TOKEN
const APPLY = process.argv.includes('--apply')
const COLLECTION = 'twaqi_push_devices'
const WORKER_POLICY = 'TWAQI Push Worker'

export const FIELDS = [
  {
    field: 'forecast_sent_at',
    type: 'timestamp',
    meta: { interface: 'datetime', width: 'half', note: 'When the last forecast heads-up was sent (FOX-191). Written by the sender.' },
    schema: { is_nullable: true },
  },
  {
    field: 'forecast_digest',
    type: 'string',
    meta: { interface: 'input', width: 'half', note: 'Hash of what that heads-up said (FOX-191).' },
    schema: { max_length: 64, is_nullable: true },
  },
]

/** The fields list a permission needs to also cover `names`; null when it
 * already does, or lists no fields at all (left for a person to look at). */
export function permissionFields(fields, names) {
  const list = Array.isArray(fields) ? fields : typeof fields === 'string' ? fields.split(',').filter(Boolean) : []
  if (!list.length || list.includes('*')) return null
  const missing = names.filter((n) => !list.includes(n))
  return missing.length ? [...list, ...missing] : null
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

  for (const def of FIELDS) {
    const existing = await api('GET', `/fields/${COLLECTION}/${def.field}`)
    if (existing.ok && existing.data) console.log(`${COLLECTION}.${def.field} exists`)
    else await step(`add field ${COLLECTION}.${def.field} (${def.type})`, () => api('POST', `/fields/${COLLECTION}`, def))
  }

  const policies = await api('GET', `/policies?filter[name][_eq]=${encodeURIComponent(WORKER_POLICY)}&fields=id,name`)
  const policy = policies.data?.[0]
  if (!policy) throw new Error(`policy "${WORKER_POLICY}" not found`)
  const names = FIELDS.map((f) => f.field)
  for (const action of ['read', 'update']) {
    const perms = await api(
      'GET',
      `/permissions?filter[policy][_eq]=${policy.id}&filter[collection][_eq]=${COLLECTION}&filter[action][_eq]=${action}&fields=id,fields`,
    )
    const perm = perms.data?.[0]
    if (!perm) {
      console.log(`warning: "${WORKER_POLICY}" has no ${action} permission on ${COLLECTION}`)
      continue
    }
    const next = permissionFields(perm.fields, names)
    if (!next) {
      console.log(`"${WORKER_POLICY}" ${action} on ${COLLECTION} already covers ${names.join(', ')} (or lists no fields: check by hand)`)
      continue
    }
    await step(`let "${WORKER_POLICY}" ${action} ${names.join(', ')}`, () => api('PATCH', `/permissions/${perm.id}`, { fields: next }))
  }

  if (!APPLY) console.log('\nNothing written. Run again with --apply to make these changes.')
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(String(e.message ?? e))
    process.exit(1)
  })
}
