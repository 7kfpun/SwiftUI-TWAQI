# twaqi-push-sender

Cloudflare Worker that sends the TWAQI iOS app's AQI alerts straight to APNs. No OneSignal.

- **Cron** `*/10 * * * *`: read enabled subscriptions (with their device) from Directus, read current AQI from the app's own API (`AQI_API_BASE` + `/v1/current-pollutants?country=twn`, then `?station_id=` for any station outside it), and send an alert to each subscription whose station just crossed its threshold.
- **Directus** (`https://cms.wahthefox.com`) is the database. The app creates and updates rows; this Worker reads them and updates state. Nothing is deleted: dead rows get `archived = true`.

## Rules

| | |
| --- | --- |
| Criteria | `direction = above`: AQI **>** threshold. `below`: AQI **<** threshold. Metric is `aqi` only (v1). |
| Edge trigger | Alert when a subscription **enters** the zone (`in_zone` false/null → true), not on every run spent inside it. Leaving the zone sets `in_zone = false` and re-arms it. |
| Cool-down | A crossing within `COOLDOWN_MINUTES` (180) of `last_fired_at` is recorded but not sent, for values bouncing around the threshold. |
| Quiet hours | If the device has `dnd_enabled` and the current time in its `timezone` is in `dnd_start`–`dnd_end` (`HH:mm`, may run past midnight, e.g. 23:00–07:00), the crossing is recorded and the alert is **dropped**. No backlog, no digest, no bypass. |
| Stale data | Readings with `publish_time` older than `MAX_DATA_AGE_MINUTES` (180), or AQI ≤ 0, are skipped without changing state. |
| Failed send | `in_zone` is left as it was, so the next run retries. |
| Dead token | APNs `410` / `BadDeviceToken` / `Unregistered` → device `archived = true`. Its subscriptions stop matching. |
| Environment | `device.environment = sandbox` → `api.sandbox.push.apple.com`, `production` → `api.push.apple.com`. Xcode debug builds are sandbox; **TestFlight and App Store builds are production.** |

The alert text is localized on the phone from the app's `Localizable.strings` (`Push.aqi_above_title`, `Push.aqi_above_body`, …), so it follows the app's language. The Worker only picks the station name: Chinese when `device.locale` starts with `zh`. The payload carries `station_id` (plus `site_id`, `subscription_id`, `direction`, `threshold`, `aqi`); tapping the alert opens that station.

## Routes

`https://twaqi-push-sender.<account>.workers.dev`

| Route | |
| --- | --- |
| `GET /` | Health, and whether the APNs secrets are set |
| `POST /run` | Run now. `?dry` sends and writes nothing and lists each decision. Body `{"aqi": {"91": 180}}` replaces live AQI for those stations, to force a crossing. |
| `POST /test` | `{"device_id": 12, "station_id": 91}` — one test alert to one device, ignoring quiet hours. Checks the APNs key and the tap-through. |

Both POST routes need `Authorization: Bearer $ADMIN_TOKEN`.

```sh
curl -X POST "$WORKER/run?dry" -H "Authorization: Bearer $ADMIN_TOKEN" -d '{"aqi":{"91":180}}'
curl -X POST "$WORKER/test"    -H "Authorization: Bearer $ADMIN_TOKEN" -d '{"device_id":12,"station_id":91}'
```

## Directus

`twaqi_push_devices`: `device_token` (unique), `environment` (`sandbox`|`production`), `app_version`, `locale`, `last_seen_at`, `install_id`, `external_id`, `dnd_enabled`, `dnd_start`, `dnd_end` (`HH:mm`), `timezone` (default `Asia/Hong_Kong`), `archived`.

`twaqi_push_subscriptions`: `device` (M2O), `station_id` (AQI API station id, stored as a string), `site_id` (MOENV SiteId, for cams only), `metric` (`aqi`), `direction` (`above`|`below`), `threshold`, `enabled`, `last_value`, `in_zone`, `last_fired_at`, `archived`.

The Worker's token belongs to the **TWAQI Push Worker** role: it reads unarchived rows and updates `last_value` / `in_zone` / `last_fired_at` on subscriptions and `archived` on devices.

## Secrets

Listed under `secrets.required` in `wrangler.jsonc`. CI uploads them from GitHub repository secrets of the same names on every deploy, and refuses to deploy if one is missing. Never commit any of them.

| Secret | |
| --- | --- |
| `APNS_KEY_ID` | Key ID of an **APNs** auth key (Certificates, IDs & Profiles → Keys, "Apple Push Notifications service" enabled). The App Store Connect API key is a different key and will not work. |
| `APNS_TEAM_ID` | Apple Developer team ID. |
| `APNS_KEY_P8` | The whole `AuthKey_<KEYID>.p8` file, PEM header and all. |
| `DIRECTUS_TOKEN` | Static token of the TWAQI Push Worker user. |
| `AQI_API_BASE` | The app's `API_DOMAIN` (from `release.xcconfig`, with the `\/` unescaped), ending in `/api`. |
| `ADMIN_TOKEN` | Any long random string, for `/run` and `/test`. |

```sh
gh secret set APNS_KEY_ID    -R 7kfpun/SwiftUI-TWAQI
gh secret set APNS_TEAM_ID   -R 7kfpun/SwiftUI-TWAQI
gh secret set APNS_KEY_P8    -R 7kfpun/SwiftUI-TWAQI < AuthKey_XXXXXXXXXX.p8
gh secret set DIRECTUS_TOKEN -R 7kfpun/SwiftUI-TWAQI
gh secret set AQI_API_BASE   -R 7kfpun/SwiftUI-TWAQI
openssl rand -hex 32 | gh secret set ADMIN_TOKEN -R 7kfpun/SwiftUI-TWAQI
```

To set one on the live Worker without a deploy: `npx wrangler secret put APNS_KEY_P8 < AuthKey_XXXXXXXXXX.p8`.

Non-secret settings are `vars` in `wrangler.jsonc`: `APNS_BUNDLE_ID` (`com.kfpun.twaqi`), `DIRECTUS_URL`, `AQI_COUNTRIES`, `COOLDOWN_MINUTES`, `MAX_DATA_AGE_MINUTES`.

## Develop

```sh
npm install
npm test          # rules: edge trigger, quiet hours, cool-down
npm run typecheck
npx wrangler dev  # secrets from .dev.vars (gitignored)
```

`wrangler dev` cannot reach APNs: the local runtime fetches over HTTP/1.1 and APNs only speaks HTTP/2. Everything up to the send works locally (`/run?dry`); check real sends against the deployed Worker with `/test`.

Each run makes one subrequest per alert sent, plus one AQI request per country and a few Directus calls. The free plan allows 50 subrequests per run.
