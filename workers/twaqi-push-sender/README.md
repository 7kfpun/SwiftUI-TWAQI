# twaqi-push-sender

Cloudflare Worker that sends the TWAQI iOS app's AQI alerts through **Firebase Cloud Messaging** (HTTP v1). FCM hands them to APNs with the auth key uploaded in the Firebase console (project `kf-twaqi`).

- **Cron** `*/10 * * * *`: read enabled subscriptions (with their device) from Directus, read current AQI from the app's own API (`AQI_API_BASE` + `/v1/current-pollutants?country=twn`, then `?station_id=` for any station outside it), and send an alert to each subscription whose station just crossed its threshold.
- **Only devices with an `fcm_token`**, i.e. builds from FOX-13 on. Older builds have no FCM token and are still served by the OneSignal tracker in `ai-playground`, which this Worker does not touch.
- **Directus** (`https://cms.wahthefox.com`) is the database. The app creates and updates rows; this Worker reads them and updates state. Nothing is deleted: dead rows get `archived = true`.

## Rules

| | |
| --- | --- |
| Criteria | `direction = above`: AQI **>** threshold. `below`: AQI **<** threshold (the app says 「高於／低於此數值」). Metric is `aqi` only. |
| Edge trigger | Alert when a subscription **enters** the zone (`in_zone` false/null → true), not on every run spent inside it. Leaving the zone sets `in_zone = false` and re-arms it. |
| Cool-down | A crossing within `COOLDOWN_MINUTES` (180) of `last_fired_at` is recorded but not sent, for values bouncing around the threshold. |
| Quiet hours | If the device has `dnd_enabled` and the current time in its `timezone` is in `dnd_start`–`dnd_end` (`HH:mm`, may run past midnight, e.g. 23:00–07:00), the crossing is recorded and the alert is **dropped**. No backlog, no digest. |
| Stale data | Readings with `publish_time` older than `MAX_DATA_AGE_MINUTES` (180), or AQI ≤ 0, are skipped without changing state. |
| Failed send | `in_zone` is left as it was, so the next run retries. |
| Dead token | FCM `UNREGISTERED`, `SENDER_ID_MISMATCH`, or `INVALID_ARGUMENT` about the registration token → device `archived = true`. Its subscriptions stop matching until the app writes its row again (which sets `archived = false`). |
| Expiry | An alert APNs can't deliver within an hour is dropped (`apns-expiration`). Same subscription → same `apns-collapse-id`; a station's alerts share a `thread-id`. No badge. |

The text is written here, in the app's language (`device.locale`, which the app sets to its own language: Chinese when it starts with `zh`, otherwise English):

| | zh-Hant | en |
| --- | --- | --- |
| above | **中山 AQI 135** 空氣品質指標已高於你設定的 120，外出請留意。 | **Zhongshan: AQI 135** Air quality is now above your alert level of 120. |
| below | **中山 AQI 24** 空氣品質指標已低於你設定的 30，空氣變好了。 | **Zhongshan: AQI 24** Air quality is now below your alert level of 30. The air has cleared up. |

The FCM `data` carries `station_id`, `site_id`, `subscription_id`, `direction`, `threshold` and `aqi` (strings), for the app to open the station from a tap once it reads them.

## Send log (`twaqi_push_logs`, FOX-66)

Every send attempt, alert or test, is written to `twaqi_push_logs`: `token_suffix` (last 6 characters of the FCM token, **never the whole token**), `status` (`sent` / `failed` / `unregistered`), `station`, `trigger` (`pollution` = above, `cleanliness` = below, `test`), `device` (M2O to `twaqi_push_devices`), `aqi`, `fcm_message_id`, `error_code`, `archived`, `date_created`. Archive soft delete on `archived`; nothing is deleted.

The log is best effort: a failed write is logged to the console and never holds up a send or its state. Quiet-hours and cool-down skips are not logged (the subscription's `last_value` / `in_zone` record those).

The collection is created by [`directus/push-logs.mjs`](directus/push-logs.mjs), which also lets the **TWAQI Push Worker** policy create rows (and nothing else) there. It is idempotent and only adds what's missing:

```sh
DIRECTUS_ADMIN_TOKEN=… node directus/push-logs.mjs          # show the plan, write nothing
DIRECTUS_ADMIN_TOKEN=… node directus/push-logs.mjs --apply  # create it
```

## Routes

`https://twaqi-push-sender.710kfpun.workers.dev`

| Route | |
| --- | --- |
| `GET /` | Health, and whether the FCM service account is set |
| `POST /run` | Run now. `?dry` sends and writes nothing and lists each decision. Body `{"aqi": {"105": 180}}` replaces live AQI for those stations, to force a crossing. |
| `POST /test` | `{"device_id": 5}` (optionally `"station_id": 105`): one test alert to one device, ignoring quiet hours. Checks the service account and the APNs key in Firebase. |

Both POST routes need `Authorization: Bearer $SYNC_TOKEN` (the same token as `twaqi-workers`).

```sh
curl -X POST "$WORKER/run?dry" -H "Authorization: Bearer $SYNC_TOKEN" -d '{"aqi":{"105":180}}'
curl -X POST "$WORKER/test"    -H "Authorization: Bearer $SYNC_TOKEN" -d '{"device_id":5}'
```

## Directus

`twaqi_push_devices`: `device_id` (Keychain), `device_token` (APNs, hex), `fcm_token`, `environment`, `app_version`, `locale`, `last_seen_at`, `dnd_enabled`, `dnd_start`, `dnd_end` (`HH:mm`), `timezone`, `archived`.

`twaqi_push_subscriptions`: `device` (M2O), `station_id` (AQI API station id, stored as a string), `site_id` (MOENV SiteId, for cams only), `metric` (`aqi`), `direction` (`above`|`below`), `threshold`, `enabled`, `last_value`, `in_zone`, `last_fired_at`, `archived`.

The Worker's token belongs to the **TWAQI Push Worker** user: it reads unarchived rows, updates `last_value` / `in_zone` / `last_fired_at` on subscriptions and `archived` on devices, and creates `twaqi_push_logs` rows.

## Secrets

Listed under `secrets.required` in `wrangler.jsonc`. CI uploads them from the `workers-production` environment secrets of the same names on every deploy, and refuses to deploy if one is missing. Never commit any of them.

| Secret | |
| --- | --- |
| `FCM_SERVICE_ACCOUNT` | The whole service-account JSON: Firebase console → `kf-twaqi` → Project settings → Service accounts → Generate new private key. |
| `DIRECTUS_PUSH_TOKEN` | Static token of the TWAQI Push Worker user. |
| `AQI_API_BASE` | The app's `API_DOMAIN` (from `release.xcconfig`, with the `\/` unescaped), ending in `/api`. |
| `SYNC_TOKEN` | Already set for `twaqi-workers`; gates `/run` and `/test`. |

```sh
gh secret set FCM_SERVICE_ACCOUNT -R 7kfpun/SwiftUI-TWAQI --env workers-production < kf-twaqi-firebase-adminsdk.json
gh secret set DIRECTUS_PUSH_TOKEN -R 7kfpun/SwiftUI-TWAQI --env workers-production
gh secret set AQI_API_BASE        -R 7kfpun/SwiftUI-TWAQI --env workers-production
```

To set one on the live Worker without a deploy: `npx wrangler secret put FCM_SERVICE_ACCOUNT < kf-twaqi-firebase-adminsdk.json`.

Non-secret settings are `vars` in `wrangler.jsonc`: `DIRECTUS_URL`, `AQI_COUNTRIES`, `COOLDOWN_MINUTES`, `MAX_DATA_AGE_MINUTES`.

## Develop

```sh
npm install
npm test          # rules, FCM request + JWT, alert text, log schema
npm run typecheck
npx wrangler dev  # secrets from .dev.vars (gitignored)
```

`/run?dry` works locally against the live Directus and AQI API with only `DIRECTUS_PUSH_TOKEN`, `AQI_API_BASE` and `SYNC_TOKEN` in `.dev.vars`; it reads and never writes.

Each run makes one subrequest per alert sent, plus one OAuth exchange when the access token is older than ~55 minutes, one AQI request per country and a few Directus calls. With no limit on alerted stations (FOX-41), a busy hour can pass the free plan's 50 subrequests per run; the paid plan allows 1000.
