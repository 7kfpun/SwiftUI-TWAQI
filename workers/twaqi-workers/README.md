# twaqi-workers

Cloudflare Worker that:

- mirrors MOENV air-quality station webcam JPEGs (`aqx_p_01`) into R2 bucket `twaqi-station-cams` and serves them publicly via the R2 custom domain `twaqi.app.wahthefox.com`;
- mirrors the MOENV 空品區 AQI forecast (`aqf_p_01`) into the Directus collection `twaqi_aqi_forecast` on `cms.wahthefox.com`, which the app reads directly.

## Station webcams

- **Cron** `*/10 * * * *`: latest `aqx_p_01` zip → unzip (fflate) → `stations/{siteId}.jpg` + `manifest.json`. A zip already synced (same source URL) is skipped, and images whose timestamp hasn't changed aren't re-uploaded.
- `siteId` is the MOENV image site id from the filename (`001-202610302200.jpg` → `001`), **not** a TWAQI station id.
- Station name and lat/lon come from `info.xml` (`site`, `TWD97Lat`, `TWD97Lon`), falling back to `Data.csv`.

### Webcam endpoints

Public images are served straight from R2 via the bucket's custom domain — no Worker in the path:

- `https://twaqi.app.wahthefox.com/stations/{siteId}.jpg`
- `https://twaqi.app.wahthefox.com/manifest.json`

The Worker has no custom-domain route; it runs on `https://twaqi-workers.710kfpun.workers.dev`. Each feature has its own path prefix; the webcam routes are under `/station-cams`.

| Route | |
| --- | --- |
| `GET /` | Worker health |
| `GET /station-cams` | Webcam sync status: last sync time, source zip, station count |
| `GET /station-cams/manifest.json` | `{ updatedAt, source, stations: { [siteId]: { name, lat, lon, time, key } } }` — `max-age=60` |
| `GET /station-cams/stations/{siteId}.jpg` | Latest JPEG — `max-age=300`, ETag / 304 |
| `POST /station-cams/sync` | Manual sync, `Authorization: Bearer $SYNC_TOKEN`; `?force` re-uploads everything |

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
