# Directus `twaqi_push_logs`

FOX-66. A log of push sends, one row per send attempt. It lives in Directus on
`https://cms.wahthefox.com`, next to `twaqi_push_devices` and `twaqi_push_subscriptions`.

**Only the schema exists for now.** The collection is live on the CMS but nothing writes to it
yet. The app doesn't read or write it, and neither does any worker. The Slice 2 sender (the FCM / DIY
push sender) will write rows here later. That work is a separate ticket and is not part of
FOX-66 or this doc.

Live push on `master` is still OneSignal (see [README → Push notifications](../../README.md#push-notifications-onesignal-today-fcm-not-yet)).
The FCM cutover (`feature/twaqi-fcm-cutover`, PR #15) is not merged and does not depend on
this collection.

Schema snapshot (taken from the live CMS when the collection was created):
[`twaqi_push_logs.schema.json`](twaqi_push_logs.schema.json).

## Rules

- **Never store a full FCM token.** Keep only `token_suffix`, the last few characters, so a
  row can be matched to a device by eye. To link a row to a device, use the optional
  `device` relation to `twaqi_push_devices`. Don't copy the token.
- **Soft delete only.** The collection uses Directus Archive: `archived = true` hides a row,
  and `archived = false` restores it. Rows are never hard-deleted, not from the app, a
  worker, the Directus UI or MCP. The Directus MCP **Allow Deletes** setting stays **off**.
- How the Slice 2 sender fills rows (when it inserts, which fields it updates) is decided in
  that ticket. Whatever it does, it must follow the two rules above.

## Collection settings

| Setting | Value |
| --- | --- |
| Archive field | `archived` |
| Archive value / unarchive value | `true` / `false` |
| Archive app filter | on (archived rows are hidden in the Directus app by default) |
| Accountability | `all` |
| Display template | `{{status}} {{station}} {{trigger}} {{token_suffix}}` |

## Fields

| Field | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | integer | no | auto-increment | Primary key |
| `token_suffix` | string | yes | — | Last few characters of the FCM token, **never** the full token |
| `status` | string (dropdown) | no | `queued` | `queued`, `sent`, `failed`, `unregistered` |
| `station` | string | yes | — | Station id or code that the alert is about |
| `trigger` | string (dropdown, other allowed) | yes | — | `pollution`, `cleanliness`, `test`, `manual`, or any other string |
| `device` | integer, m2o → `twaqi_push_devices.id` | yes | — | Optional. Shows as `{{environment}} {{device_id}}` |
| `fcm_message_id` | string | yes | — | Message name/id from the FCM HTTP v1 send response |
| `error` | text | yes | — | Send error that a person can read |
| `error_code` | string | yes | — | Error code from FCM or the sender, for machines |
| `archived` | boolean | no | `false` | Soft-delete flag (Directus Archive) |
| `date_created` | timestamp | yes | — | Set by Directus on create (UTC) |
| `date_updated` | timestamp | yes | — | Set by Directus on update (UTC) |

`status` meanings:

- `queued`: the row was written before the send.
- `sent`: FCM accepted the message. `fcm_message_id` is set.
- `failed`: the send failed. `error` / `error_code` say why.
- `unregistered`: FCM reports that the token is no longer valid.

Timestamps are UTC, the same as the rest of the Directus API.

## Changing the schema

Change the schema on the CMS first. Then re-export the snapshot over
`twaqi_push_logs.schema.json` and update the field table above in the same PR. Removing a
field or adding a hard-delete path needs the user's sign-off.
