# twaqi-workers

Cloudflare Worker that:

- mirrors MOENV air-quality station webcam JPEGs (`aqx_p_01`) into R2 bucket `twaqi-station-cams` and serves them publicly via the R2 custom domain `twaqi.app.wahthefox.com`;
- mirrors the MOENV 空品區 AQI forecast (`aqf_p_01`) into the Directus collection `twaqi_aqi_forecast` on `cms.wahthefox.com`, which the app reads directly.

## Station webcams

- **Cron** `*/10 * * * *`: latest `aqx_p_01` zip → unzip (fflate) → `stations/{siteId}.jpg` + `manifest.json`. A zip already synced (same source URL) is skipped, and images whose timestamp hasn't changed aren't re-uploaded.
- The same sync files **one frame per clock hour** per site under `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` (see [Hourly history](#hourly-history)).
- `siteId` is the MOENV image site id from the filename (`001-202610302200.jpg` → `001`), **not** a TWAQI station id.
- Station name and lat/lon come from `info.xml` (`site`, `TWD97Lat`, `TWD97Lon`), falling back to `Data.csv`.

### Webcam endpoints

Public images are served straight from R2 via the bucket's custom domain — no Worker in the path:

- `https://twaqi.app.wahthefox.com/stations/{siteId}.jpg`
- `https://twaqi.app.wahthefox.com/stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` (hourly history)
- `https://twaqi.app.wahthefox.com/manifest.json`

The Worker has no custom-domain route; it runs on `https://twaqi-workers.710kfpun.workers.dev`. Each feature has its own path prefix; the webcam routes are under `/station-cams`.

| Route | |
| --- | --- |
| `GET /` | Worker health |
| `GET /station-cams` | Webcam sync status: last sync time, source zip, station count |
| `GET /station-cams/manifest.json` | `{ updatedAt, source, stations: { [siteId]: { name, lat, lon, time, key, hourKey } } }` — `max-age=60` |
| `GET /station-cams/stations/{siteId}.jpg` | Latest JPEG — `max-age=300`, ETag / 304 |
| `GET /station-cams/stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` | That hour's JPEG — `max-age=86400`, ETag / 304; 404 if none was filed |
| `POST /station-cams/sync` | Manual sync, `Authorization: Bearer $SYNC_TOKEN`; `?force` re-uploads every latest frame (hourly frames already filed are left alone) |

### Hourly history

The app's station screen scrubs back through the past 24 clock hours of a cam. For that the sync keeps **one frame per site per hour**, not every 10-minute frame (24 a day, not ~144):

```
stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg      e.g. stations/001/2026-10-30/22.jpg
```

- `yyyy-MM-dd` and `HH` are **Taiwan local time** (UTC+8, no DST), read straight off the MOENV filename stamp (`001-202610302200.jpg` → `2026-10-30/22`).
- The first frame a sync sees in each hour is filed: the `:00` frame whenever a sync catches it, otherwise the earliest after it (a missed sync, or a site that skipped `:00`). Later frames in that hour are not. The manifest's per-site `hourKey` records the hour last filed, so nothing has to `HEAD` or list R2.
- An hour's object never changes once written (`Cache-Control: public, max-age=86400`); its `customMetadata.time` is the actual capture time.
- The app builds the URL from the site id and the hour. An hour with no frame (cam down, or not filed yet) is a plain 404.
- **Retention: rolling 24 hours** (`HISTORY_DAYS = 1` in `src/history.ts`). As each hour is filed, the same site's object for that hour the day before is deleted, so R2 holds the last 24 hourly slots per site without listing the bucket. (The app keeps its own offline copies for up to a week.) Frames left behind by a site that stopped reporting, or by a failed delete, are not swept; an R2 lifecycle rule on the bucket would catch those (follow-up).

Logic tests (`node --test`, no extra dependencies, Node 23.6+):

```sh
npm test
```

Checking a deploy by hand:

```sh
curl -X POST -H "Authorization: Bearer $SYNC_TOKEN" https://twaqi-workers.710kfpun.workers.dev/station-cams/sync
# → { …, "hours": 81, "expired": 81, … } on the first sync of an hour, then "hours": 0 until the next hour
curl -s https://twaqi.app.wahthefox.com/manifest.json | jq '.stations["001"].hourKey'
curl -sI "https://twaqi.app.wahthefox.com/$(curl -s https://twaqi.app.wahthefox.com/manifest.json | jq -r '.stations["001"].hourKey')"
```

## AQI forecast (`aqf_p_01`)

- **Cron** `35 * * * *` (hourly; MOENV publishes a few times a day, roughly :30): fetch `aqf_p_01` with `MOENV_API_KEY` → one row per (`area`, `forecast_date`) → upsert into Directus `twaqi_aqi_forecast` with `DIRECTUS_FORECAST_TOKEN`.
- **Latest only.** A row is updated only when the feed's `PublishTime` is newer than the stored `publish_time`; older or equal publishes are skipped. An archived row for a date still in the feed is overwritten and un-archived.
- **Last good rows win.** If MOENV errors, answers with a non-JSON body (a bad key is a `200` with `api_key 不存在。`), or returns no usable rows, Directus is left alone and the failure is logged.
- Rows whose `forecast_date` is more than 14 days old are soft-archived (`archived = true`). Nothing is deleted.
- Stored as MOENV publishes it: `area` is the short name (`北部`, `雲嘉南`, not `北部空品區`), `forecast_date` is `YYYY-MM-DD`, `publish_time` is Taiwan local time `YYYY-MM-DD HH:mm:ss`, `source` is `AQF_P_01`.
- The MOENV key stays in the Worker. The app reads Directus with its own read-only static token.

| Route | |
| --- | --- |
| `GET /forecast` | Outcome of the last sync (`{ ok, at, result \| error }`), kept in R2 at `forecast/last-sync.json` |
| `POST /forecast/sync` | Manual sync, `Authorization: Bearer $SYNC_TOKEN` |

Local testing against a mock feed (no MOENV key needed). `.dev.vars` holds `DIRECTUS_FORECAST_TOKEN` and `SYNC_TOKEN`; the mock URL is passed as a var because `wrangler dev` only loads the declared secrets from `.dev.vars`:

```sh
npx wrangler dev --var MOENV_FORECAST_URL:http://127.0.0.1:8799/feed.json
curl -X POST -H "Authorization: Bearer $SYNC_TOKEN" localhost:8787/forecast/sync
```

## Deploy

GitHub Actions deploys this Worker when a merge to master changes `workers/twaqi-workers/` (see `.github/workflows/workers.yml`). Run the **Workers** workflow by hand to redeploy.

`DIRECTUS_URL` is a plain var in `wrangler.jsonc`. Secrets are listed in `secrets.required` there; a deploy fails if any is missing. CI uploads them from GitHub repository secrets of the same names on every deploy:

```sh
gh secret set MOENV_API_KEY -R 7kfpun/SwiftUI-TWAQI
gh secret set SYNC_TOKEN -R 7kfpun/SwiftUI-TWAQI
# Directus static token of the "TWAQI Forecast Worker" user (create/read/update on twaqi_aqi_forecast)
gh secret set DIRECTUS_FORECAST_TOKEN -R 7kfpun/SwiftUI-TWAQI
```

Local development:

```sh
npm install
npx wrangler dev
```
