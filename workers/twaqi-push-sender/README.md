# twaqi-push-sender

Cloudflare Worker that sends the TWAQI iOS app's AQI alerts through **Firebase Cloud Messaging** (HTTP v1). FCM hands them to APNs with the auth key uploaded in the Firebase console (project `kf-twaqi`).

- **Cron** `20 */2 * * *` (every 2 hours, at :20 past even hours, UTC and Taiwan alike):
  1. Read every station's current AQI in one request to the app's own API (`AQI_API_BASE` + `/v1/current-pollutants?country=twn`): the same numbers the station screen shows.
  2. Ask Directus for **only the subscriptions whose zone changes at those readings**, filtered per station: an "above" alert with threshold ≤ AQI that isn't marked `in_zone` yet (send it), or one marked `in_zone` whose threshold AQI no longer reaches (re-arm it). "Below" mirrors it. Ten stations per request, so 84 stations take 9 requests; a run where nothing crossed reads no subscriptions at all.
  3. Send an alert to each one that crossed in, and write back only the rows whose state changed.
- **Only devices with an `fcm_token`**, i.e. builds from FOX-13 on. Older builds have no FCM token. They were served by the OneSignal tracker in `ai-playground`, which is being switched off. The app keeps OneSignal registered with the same tags, so it can be switched back on.
- **Directus** (`https://cms.wahthefox.com`) is the database. The app creates and updates rows; this Worker reads them and updates state. Nothing is deleted: dead rows get `archived = true`.

## Rules

| | |
| --- | --- |
| Criteria | `direction = above`: AQI **≥** threshold. `below`: AQI **≤** threshold (FOX-13; the OneSignal tracker matched the same way). Metric is `aqi` only. |
| Edge trigger | Alert when a subscription **enters** the zone (`in_zone` false/null → true), not on every run spent inside it. Leaving the zone sets `in_zone = false` and re-arms it. |
| Cool-down | A crossing within `COOLDOWN_MINUTES` (180) of `last_fired_at` is recorded but not sent, for values bouncing around the threshold. With runs 2 hours apart, a subscription alerts at most every 4 hours. |
| Quiet hours | If the device has `dnd_enabled` and the current time in its `timezone` is in `dnd_start`–`dnd_end` (`HH:mm`, may run past midnight, e.g. 23:00–07:00), the crossing is recorded and the alert is **dropped**. No backlog, no digest. |
| Stale data | Stations whose `publish_time` is older than `MAX_DATA_AGE_MINUTES` (180), or whose AQI is ≤ 0, are left out of the filter, so nothing on them changes. |
| Limit | The app allows alerts on at most **3 stations** per device (`FavouriteAlerts.maxAlertedStations`). |
| Opted out | The app reports `notifications_allowed` on its row (false when notifications are off for it in iOS Settings, or never allowed). Only devices where it is **true** are sent to. Not asked yet (empty) waits: a crossing before the user allows notifications stays unmarked and fires on the first run after they do, which the app reports at once. Rows from before this build have no FCM token, so they're not sent to anyway. |
| Failed send | `in_zone` is left as it was, so the next run retries. |
| Dead token | FCM `UNREGISTERED`, `SENDER_ID_MISMATCH`, or `INVALID_ARGUMENT` about the registration token → device `archived = true`. Its subscriptions stop matching until the app writes its row again (which sets `archived = false`). |
| Expiry | An alert APNs can't deliver within an hour is dropped (`apns-expiration`). Same subscription → same `apns-collapse-id`; a station's alerts share a `thread-id`. No badge. |

The text is written here, in the app's language (`device.locale`, which the app sets to its own language: Chinese when it starts with `zh`, otherwise English):

| | zh-Hant | en |
| --- | --- | --- |
| above | **中山 AQI 135** 空氣品質指標已高於你設定的 120，外出請留意。 | **Zhongshan: AQI 135** Air quality is now above your alert level of 120. |
| below | **中山 AQI 24** 空氣品質指標已低於你設定的 30，空氣變好了。 | **Zhongshan: AQI 24** Air quality is now below your alert level of 30. The air has cleared up. |

The FCM `data` carries `station_id`, `site_id`, `subscription_id`, `direction`, `threshold` and `aqi` (strings), for the app to open the station from a tap once it reads them.

## App API (FOX-37 M5)

The app has **no Directus token for the push collections**. It writes its own row and alerts through this Worker, the only holder of a Directus token for them (`src/app-api.ts`):

| Route | |
| --- | --- |
| `PUT /app/v1/device` | Upsert this device's row (tokens, `environment`, `app_version`, `locale`, `is_pro`, `last_seen_at`, DND, `timezone`) → `{ id }`. Other fields in the body are dropped. |
| `GET /app/v1/device?device_token=…` | For a restore: `{ device: { id, dnd_* } \| null, subscriptions: [...] }`. |
| `PUT /app/v1/stations/:stationId` | `{ site_id, above, below }` (a whole AQI, or `null` for off): brings that station's rows in line, archiving what's off. Refuses (409) a 4th station with alerts. |
| `POST /app/v1/archive-all` | Help's "cancel all": archives this device's live alerts. |

- **Auth:** every request carries `X-Device-Id` (the Keychain UUID) and `Authorization: Bearer <secret>`, 32 random bytes the app makes once and keeps in the Keychain next to the id ("this device only").
- **Only a SHA-256 of the secret** is stored, in `twaqi_push_devices.secret_hash`. A row with another hash gets 403.
- **Rows from before the secret are never handed over.** Older builds' shared token could read device ids, so knowing one proves nothing. A device that finds its id, or its APNs token, on a row it can't prove is its own **retires** that row: its alerts are archived, the row archived, and its `device_id` and token freed. It then gets a new row, which the app fills again from the alerts saved on the phone. A restore never reads such a row.
- **Self-healing:** if another install holds this device's id, the app gets 403, makes a new Keychain id and secret, and registers again. If its row was retired (404), it registers again with the same identity.
- **Rate limit:** 60 requests a minute per IP (`APP_LIMITER`).

## Send log (`twaqi_push_logs`, FOX-66)

Every send is recorded in **Workers Analytics Engine** (dataset `twaqi_push_events`, binding `PUSH_EVENTS`). The fields are status, trigger, station, error code, token suffix, device id and AQI, kept about 3 months and queryable with SQL. Only **failures, dead tokens and `/test` sends** also get a row in Directus `twaqi_push_logs`: at 40k alerts a run, a row per send would be ~14M rows a month.

The Directus rows are: `token_suffix` (last 6 characters of the FCM token, **never the whole token**), `status` (`sent` / `failed` / `unregistered`), `station`, `trigger` (`pollution` = above, `cleanliness` = below, `test`), `device` (M2O to `twaqi_push_devices`), `aqi`, `fcm_message_id`, `error_code`, `archived`, `date_created`. Archive soft delete on `archived`; nothing is deleted.

Both logs are best effort: a failed write is logged to the console and never holds up a send or its state. Quiet-hours and cool-down skips are not logged (the subscription's `last_value` / `in_zone` record those).

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

`twaqi_push_devices`: `device_id` (Keychain), `secret_hash` (SHA-256 of the app's secret, hidden), `device_token` (APNs, hex), `fcm_token`, `environment`, `app_version`, `locale` (the language chosen under Help, else iOS's), `is_pro` (Taiwan Air Pro active), `notifications_allowed` (iOS lets the app show notifications), `last_seen_at`, `dnd_enabled`, `dnd_start`, `dnd_end` (`HH:mm`), `timezone`, `archived`.

`twaqi_push_subscriptions`: `device` (M2O), `station_id` (AQI API station id, stored as a string), `site_id` (MOENV SiteId, for cams only), `metric` (`aqi`), `direction` (`above`|`below`), `threshold`, `enabled`, `last_value`, `in_zone`, `last_fired_at`, `archived`.

The Worker's token belongs to the **TWAQI Push Worker** user. It needs:
- `twaqi_push_devices`: create, read and update, including `secret_hash`;
- `twaqi_push_subscriptions`: create, read and update;
- `twaqi_push_logs`: create.

It never deletes. The app's static token (TWAQI App role) needs **no** access to the push collections: remove the "TWAQI App Push" policy once builds before this one no longer matter, since their dual-write is what still uses it.

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

Non-secret settings are `vars` in `wrangler.jsonc`: `DIRECTUS_URL`, `AQI_COUNTRIES`, `COOLDOWN_MINUTES`, `MAX_DATA_AGE_MINUTES`, `MAX_SENDS_PER_RUN`. Bindings: `APP_LIMITER` (rate limit), `PUSH_EVENTS` (Analytics Engine). `limits.subrequests` sets the per-run request budget.

## Develop

```sh
npm install
npm test          # rules, FCM request + JWT, alert text, log schema
npm run typecheck
npx wrangler dev  # secrets from .dev.vars (gitignored)
```

`/run?dry` works locally against the live Directus and AQI API with only `DIRECTUS_PUSH_TOKEN`, `AQI_API_BASE` and `SYNC_TOKEN` in `.dev.vars`; it reads and never writes.

Each run makes one AQI request, 9 Directus reads (more pages only when over 500 subscriptions change at once), one subrequest per alert sent, an OAuth exchange when the access token is older than ~55 minutes, and one write each for state, dead tokens and logs. **Sized for 40,000 alerts per 2-hour run** on Workers Paid.
- **Requests:** a run may make up to `limits.subrequests` = 100,000 outgoing requests (Paid allows 10,000 by default, up to 10M). Each alert takes one FCM request, or two when a 429/5xx is retried, plus reads and writes, so 45,000 alerts fit even if every one is retried.
- **Budget:** the run counts its own requests against `SUBREQUEST_LIMIT`, which must equal `limits.subrequests`. A batch of 100 starts only if its worst case still fits, and is then charged what it actually used. A send that threw counts as two.
- **Time:** sends go 25 at a time, so 40k at ~100 ms each take about 3 minutes. A cron every 2 h gets 15 min of CPU and 15 min of wall time.
- **Cap:** `MAX_SENDS_PER_RUN` is 45,000. Anything past it stays unsent and goes out on the next run.
- **No repeats:** state is saved to Directus after every 100 sends, so a run cut short never resends what it already delivered.
- **FCM** allows about 600k messages a minute per project.
