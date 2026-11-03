#!/usr/bin/env node
// FOX-66: Directus collection `twaqi_push_logs`, one row per FCM send attempt
// by twaqi-push-sender. Soft delete only: Archive on the boolean `archived`.
// Never stores a whole FCM token, only its last characters (`token_suffix`).
//
// Idempotent: creates whatever is missing (collection, fields, the M2O to
// twaqi_push_devices, the push worker's create permission) and leaves
// everything that exists alone. Deletes nothing.
//
//   DIRECTUS_ADMIN_TOKEN=… node directus/push-logs.mjs           # show the plan
//   DIRECTUS_ADMIN_TOKEN=… node directus/push-logs.mjs --apply   # make it so
//
// The admin token is read from the environment only and never printed.

const BASE = (process.env.DIRECTUS_URL || 'https://cms.wahthefox.com').replace(/\/+$/, '')
const TOKEN = process.env.DIRECTUS_ADMIN_TOKEN
const APPLY = process.argv.includes('--apply')
const COLLECTION = 'twaqi_push_logs'
const WORKER_POLICY = 'TWAQI Push Worker'

const choices = (...values) => ({ choices: values.map((value) => ({ text: value, value })) })

export const collection = {
  collection: COLLECTION,
  meta: {
    icon: 'outgoing_mail',
    note: 'One row per FCM send attempt by twaqi-push-sender (FOX-66). Never the full token. Archive, never delete.',
    archive_field: 'archived',
    archive_value: 'true',
    unarchive_value: 'false',
    archive_app_filter: true,
    sort_field: null,
  },
  schema: {},
  fields: [
    {
      field: 'id',
      type: 'integer',
      meta: { hidden: true, readonly: true, interface: 'input' },
      schema: { is_primary_key: true, has_auto_increment: true },
    },
  ],
}

export const fields = [
  {
    field: 'token_suffix',
    type: 'string',
    meta: { interface: 'input', required: true, note: 'Last 6 characters of the FCM token. Never the whole token.' },
    schema: { max_length: 16, is_nullable: false },
  },
  {
    field: 'status',
    type: 'string',
    meta: { interface: 'select-dropdown', options: choices('sent', 'failed', 'unregistered'), required: true },
    schema: { max_length: 32, is_nullable: false },
  },
  {
    field: 'station',
    type: 'string',
    meta: { interface: 'input', note: 'AQI API station id, as in twaqi_push_subscriptions.station_id.' },
    schema: { max_length: 32 },
  },
  {
    field: 'trigger',
    type: 'string',
    meta: {
      interface: 'select-dropdown',
      options: choices('pollution', 'cleanliness', 'test'),
      required: true,
      note: 'pollution = an "above" alert, cleanliness = "below", test = POST /test.',
    },
    schema: { max_length: 32, is_nullable: false },
  },
  {
    field: 'device',
    type: 'integer',
    meta: { interface: 'select-dropdown-m2o', special: ['m2o'], options: { template: '{{id}} {{app_version}}' } },
    schema: {},
  },
  { field: 'aqi', type: 'integer', meta: { interface: 'input', note: 'AQI that triggered the alert.' }, schema: {} },
  {
    field: 'fcm_message_id',
    type: 'string',
    meta: { interface: 'input', readonly: true, note: 'projects/…/messages/… from FCM HTTP v1.' },
    schema: { max_length: 255 },
  },
  {
    field: 'error_code',
    type: 'string',
    meta: { interface: 'input', note: 'FCM error code, e.g. UNREGISTERED, QUOTA_EXCEEDED.' },
    schema: { max_length: 64 },
  },
  {
    field: 'archived',
    type: 'boolean',
    meta: { interface: 'boolean', width: 'half', special: ['cast-boolean'] },
    schema: { default_value: false, is_nullable: false },
  },
  {
    field: 'date_created',
    type: 'timestamp',
    meta: { interface: 'datetime', special: ['date-created'], readonly: true, width: 'half' },
    schema: {},
  },
]

export const relation = {
  collection: COLLECTION,
  field: 'device',
  related_collection: 'twaqi_push_devices',
  // A device row is archived, never deleted; if one ever is, keep its logs.
  schema: { on_delete: 'SET NULL' },
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
  if (!TOKEN) throw new Error('Set DIRECTUS_ADMIN_TOKEN (an admin user token; it is not printed).')
  const me = await api('GET', '/users/me?fields=id,role.admin_access,role.name')
  if (!me.ok) throw new Error(`token rejected: ${me.status}`)

  const existing = await api('GET', `/collections/${COLLECTION}`)
  if (existing.ok) {
    console.log(`${COLLECTION} exists`)
  } else {
    await step(`create collection ${COLLECTION}`, () => api('POST', '/collections', collection))
  }

  const have = APPLY || existing.ok ? await api('GET', `/fields/${COLLECTION}`) : { ok: true, data: [] }
  const names = new Set((have.data ?? []).map((f) => f.field))
  for (const field of fields) {
    if (names.has(field.field)) continue
    await step(`add field ${field.field} (${field.type})`, () => api('POST', `/fields/${COLLECTION}`, field))
  }

  const rel = await api('GET', `/relations/${COLLECTION}/device`)
  if (rel.ok && rel.data) {
    console.log('device → twaqi_push_devices relation exists')
  } else {
    await step('relate device → twaqi_push_devices (on delete: set null)', () => api('POST', '/relations', relation))
  }

  const policies = await api('GET', `/policies?filter[name][_eq]=${encodeURIComponent(WORKER_POLICY)}&fields=id,name`)
  const policy = policies.data?.[0]
  if (!policy) throw new Error(`policy "${WORKER_POLICY}" not found`)
  const perms = await api(
    'GET',
    `/permissions?filter[policy][_eq]=${policy.id}&filter[collection][_eq]=${COLLECTION}&filter[action][_eq]=create&fields=id`,
  )
  if (perms.data?.length) {
    console.log(`"${WORKER_POLICY}" may already create ${COLLECTION}`)
  } else {
    // Create only: the worker writes logs, never reads, edits or deletes them.
    await step(`let "${WORKER_POLICY}" create ${COLLECTION}`, () =>
      api('POST', '/permissions', { policy: policy.id, collection: COLLECTION, action: 'create', fields: ['*'], permissions: null, validation: null }),
    )
  }

  if (!APPLY) console.log('\nNothing written. Run again with --apply to make these changes.')
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(String(e.message ?? e))
    process.exit(1)
  })
}
