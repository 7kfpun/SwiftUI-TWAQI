# twaqi-workers

Cloudflare Worker that:

- mirrors MOENV air-quality station webcam JPEGs (`aqx_p_01`) into R2 bucket `twaqi-station-cams` and serves them publicly via the bucket's R2 custom domain (the webcam host);
- mirrors the MOENV 空品區 AQI forecast (`aqf_p_01`) into the Directus collection `twaqi_aqi_forecast`, which the app reads directly.
- fronts the TWAQI read API (FOX-82) at `/v1/...` on the webcam host, the same host as the webcam images (see [Read API](#read-api-v1)).
- writes Central Weather Administration (CWA) weather for the station page to `weather/latest.json` in the same bucket, served from the webcam host (see [CWA weather](#cwa-weather-fox-11)).

## Station webcams

- **Cron** `*/10 * * * *`: latest `aqx_p_01` zip → unzip (fflate) → `stations/{siteId}.jpg` + `manifest.json`. A zip already synced (same source URL) is skipped, and images whose timestamp hasn't changed aren't re-uploaded.
- The same sync files **one frame per clock hour** per site under `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` (see [Hourly history](#hourly-history)).
- `siteId` is the MOENV image site id from the filename (`001-202610302200.jpg` → `001`), **not** a TWAQI station id.
- Station name and lat/lon come from `info.xml` (`site`, `TWD97Lat`, `TWD97Lon`), falling back to `Data.csv`.

### Webcam endpoints

Public images are served straight from R2 via the bucket's custom domain — no Worker in the path:

- `<webcam host>/stations/{siteId}.jpg`
- `<webcam host>/stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` (hourly history)
- `<webcam host>/manifest.json`

The Worker's own routes run on its `workers.dev` URL; on the webcam host it takes only `/v1/*` (the read API below), everything else there is R2. Each feature has its own path prefix; the webcam routes are under `/station-cams`.

| Route | |
| --- | --- |
| `GET /` | Worker health |
| `GET /station-cams` | Webcam sync status: last sync time, source zip, station count |
| `GET /station-cams/manifest.json` | `{ updatedAt, source, stations: { [siteId]: { name, lat, lon, time, key, hourKey } }, sweptHour }` — `max-age=60` |
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
- **Retention: only the 24 hours the app shows** (`HISTORY_DAYS = 1` in `src/history.ts`). Once per newly filed hour (the manifest's `sweptHour` records the last one) the sync lists `stations/` and deletes every hourly object more than 24 clock hours before its site's last filed hour (`staleHourKeys`). That covers hours a site skipped, frames from the old 7-day retention, and a sweep that failed (it is retried on the next sync). A site that stopped reporting keeps the 24 hours before it stopped, which the app still shows; a site that files its new hour after the sweep keeps one extra hour until the next sweep. The latest `stations/{siteId}.jpg`, `manifest.json` and anything else that isn't an hourly key are never touched. (The app keeps its own offline copies for up to a week.)

Logic tests (`node --test`, no extra dependencies, Node 23.6+):

```sh
npm test
```

Checking a deploy by hand:

```sh
# WORKER = the Worker's workers.dev URL, HOST = the webcam host (wrangler.jsonc)
curl -X POST -H "Authorization: Bearer $SYNC_TOKEN" "$WORKER/station-cams/sync"
# → { …, "hours": 81, "expired": 81, … } on the first sync of an hour (the first sweep also clears older leftovers), then "hours": 0, "expired": 0 until the next hour
curl -s "https://$HOST/manifest.json" | jq '.stations["001"].hourKey'
curl -sI "https://$HOST/$(curl -s "https://$HOST/manifest.json" | jq -r '.stations["001"].hourKey')"
```

## AQI forecast (`aqf_p_01`)

- **Cron** `35 * * * *` (hourly; MOENV publishes a few times a day, roughly :30): fetch `aqf_p_01` with `MOENV_API_KEY` → one row per (`area`, `forecast_date`) → upsert into Directus `twaqi_aqi_forecast` with `DIRECTUS_FORECAST_TOKEN`.
- **Latest only.** A row is updated only when the feed's `PublishTime` is newer than the stored `publish_time`; older or equal publishes are skipped. An archived row for a date still in the feed is overwritten and un-archived.
- **Last good rows win.** If MOENV errors, answers with a non-JSON body (a bad key is a `200` with `api_key 不存在。`), or returns no usable rows, Directus is left alone and the failure is logged.
- Rows whose `forecast_date` is more than 14 days old are soft-archived (`archived = true`). Nothing is deleted.
- Stored as MOENV publishes it: `area` is the short name (`北部`, `雲嘉南`, not `北部空品區`), `forecast_date` is `YYYY-MM-DD`, `publish_time` is Taiwan local time `YYYY-MM-DD HH:mm:ss`, `source` is `AQF_P_01`.
- The MOENV key stays in the Worker. The app reads Directus with its own read-only static token.

### Pre-translated forecast text (`content_i18n`)

`content` is MOENV's Traditional Chinese text and stays the source of truth. After each upsert the sync translates it into English with an LLM on [OpenRouter](https://openrouter.ai) (`src/translate.ts`) and stores it in the JSON field `content_i18n`:

```json
{ "zh-Hant": "<the content it was translated from>", "en": "Today (the 3rd), …" }
```

- **Current** when `content_i18n["zh-Hant"]` equals `content`. Clients should use `en` only then, and otherwise fall back to `content` (the app translates on device).
- **When:** a row is translated if its text has Chinese and its translation is missing or was made from older text: new rows, publishes that changed the text, and rows an earlier run failed on. Rows already current make no call, so the sync is idempotent. MOENV repeats one text on every row of a publish, so each distinct text costs one call, shared by those rows.
- **Model:** pinned in `TRANSLATION_MODEL` (`deepseek/deepseek-v4.1-flash`), `temperature: 0`, a short system prompt plus the glossary terms found in the text (the 10 forecast areas, pollutants, AQI levels, MOENV alerts). Output must be plain English with no Chinese left, or it is rejected.
- **Limits:** 30 s per call, at most 40 distinct texts and 120 s of translating per run; the rest waits for the next hour.
- **Never blocks the forecast.** Translation runs after the rows are stored. A failed call, a missing `OPENROUTER_FORECAST_API_KEY`, a missing `content_i18n` field or a refused write leaves `content_i18n` as it was and is retried next run.
- **Saves in batches.** Rows that only copy an existing translation are saved first (no model call), then the translations after every 5 model calls (`TRANSLATION_SAVE_BATCH`). Once Directus refuses a save (e.g. 403: the Worker role lacks update on `content_i18n`), the run makes no more model calls, so a refused save costs at most one batch per run instead of up to 40 calls; the unsent texts count as `translationDeferred`.
- `GET /forecast` reports `translated` (texts translated and saved), `translatedRows`, `translationFailed` (including texts translated but not saved), `translationDeferred`, and `translationSkipped` with the reason when translation did not run or could not save; after a refused save it ends with `model calls stopped after N, M left for next run`.
- Directus: `content_i18n` is a JSON field on `twaqi_aqi_forecast`; the **TWAQI Forecast Worker** role needs read and update on it, and the app's role read.

| Route | |
| --- | --- |
| `GET /forecast` | Outcome of the last sync (`{ ok, at, result \| error }`), kept in R2 at `forecast/last-sync.json` |
| `POST /forecast/sync` | Manual sync, `Authorization: Bearer $SYNC_TOKEN` |

Local testing against a mock feed (no MOENV key needed). `.dev.vars` holds `DIRECTUS_FORECAST_TOKEN`, `SYNC_TOKEN` and, to try translation, `OPENROUTER_FORECAST_API_KEY`; the mock URL is passed as a var because `wrangler dev` only loads the declared secrets from `.dev.vars`:

```sh
npx wrangler dev --var MOENV_FORECAST_URL:http://127.0.0.1:8799/feed.json
curl -X POST -H "Authorization: Bearer $SYNC_TOKEN" localhost:8787/forecast/sync
```

## CWA weather (FOX-11)

- **Cron** `40 * * * *` (hourly, its own invocation so it never shares the forecast's CPU or subrequest budget): fetch two CWA open-data sets with `CWA_API_KEY` → one compact JSON → R2 `weather/latest.json`, `Cache-Control: public, max-age=300`, served straight from the webcam host like `manifest.json` (no Worker in the path). Code: `src/weather.ts`.
  - `F-C0032-001`: the 36-hour county (縣市) forecast. Kept per county and period: start/end (Taiwan time, ISO 8601 with `+08:00`), Wx code and CWA's text, PoP, MinT, MaxT. CI (comfort) is dropped: the app doesn't show it.
  - `O-A0003-001`: CWA's staffed stations. Kept per station: id, name, county, WGS84 lat/lon, observation time, temperature, humidity, rain since midnight (`Now.Precipitation`), wind speed. CWA's missing-value markers (`-99`, `-990`, `X`, …) become `null`; for rain, `T` (trace) and `-98` (no rain in 6 h) are `0`. A station with no reading left is dropped.
- **Shape:** `{ version: 1, updatedAt, forecast: { fetchedAt, counties: { "臺北市": [period…] } } | null, observations: { fetchedAt, stations: [station…] } | null }`. County names use 臺 as CWA writes them. Free text (Wx descriptions, station names) stays zh-Hant; the app maps Wx codes to its own strings.
- **Last good wins.** Each set is fetched and parsed on its own. One that fails (HTTP error, non-JSON body, `success` not true, nothing usable) keeps its section from the previous file; the file is rewritten only when at least one set is new, and left untouched when both fail. Nothing is deleted.
- **Wx codes:** CWA's table (預報產品天氣描述代碼表) is 1–42 without 40 (`WX_CODES`). A code outside it is still stored and listed in the sync status as `unknownWx`, so a new code is noticed before the app learns it.
- **Free plan:** two fetches, one R2 read and two writes per run. Parsing both sets at full size (22 counties; 80 stations, more than CWA's staffed network) took 6.2 ms on a cold first run and ~0.5 ms after, in Node 25's V8 (the same engine), against the Free plan's 10 ms CPU per invocation; time spent waiting on CWA or R2 isn't CPU. The Worker's observability logs show each run's real CPU time.

| Route | |
| --- | --- |
| `GET /weather` | Outcome of the last sync (`{ ok, at, result \| error }`; `result` has `forecast` / `observations` = `updated` \| `kept` \| `missing`, counts, `unknownWx`, and the error of a set that wasn't updated, with any URL query string and `Authorization` value stripped), kept in R2 at `weather/last-sync.json` |
| `POST /weather/sync` | Manual sync, `Authorization: Bearer $SYNC_TOKEN` |

Checking a deploy by hand:

```sh
# WORKER = the Worker's workers.dev URL, HOST = the webcam host (wrangler.jsonc)
curl -X POST -H "Authorization: Bearer $SYNC_TOKEN" "$WORKER/weather/sync"
curl -s "https://$HOST/weather/latest.json" | jq '{updatedAt, counties: (.forecast.counties | keys | length), stations: (.observations.stations | length)}'
```

Local testing against a mock CWA (no key needed): `npx wrangler dev --var CWA_API_BASE:http://127.0.0.1:8799` with `CWA_API_KEY` in `.dev.vars`, serving `/F-C0032-001` and `/O-A0003-001` (the fixtures in `test/fixtures/` work).

## Deploy

GitHub Actions deploys this Worker when a merge to master changes `workers/twaqi-workers/` (see `.github/workflows/workers.yml`). Run the **Workers** workflow by hand to redeploy.

`DIRECTUS_URL` is a plain var in `wrangler.jsonc`. Secrets are listed in `secrets.required` there; a deploy fails if any is missing. CI uploads them on every deploy from the secrets of the same names in the `workers-production` GitHub environment, and each new one also needs a line in the deploy's "Collect Worker secrets" env:

```sh
gh secret set MOENV_API_KEY -R 7kfpun/SwiftUI-TWAQI --env workers-production
gh secret set SYNC_TOKEN -R 7kfpun/SwiftUI-TWAQI --env workers-production
# Directus static token of the "TWAQI Forecast Worker" user (create/read/update on twaqi_aqi_forecast, including content_i18n)
gh secret set DIRECTUS_FORECAST_TOKEN -R 7kfpun/SwiftUI-TWAQI --env workers-production
# OpenRouter key for pre-translating the forecast text
gh secret set OPENROUTER_FORECAST_API_KEY -R 7kfpun/SwiftUI-TWAQI --env workers-production
# CWA open-data key (授權碼) for the weather sync; it never goes to the app
gh secret set CWA_API_KEY -R 7kfpun/SwiftUI-TWAQI --env workers-production
```

Local development:

```sh
npm install
npx wrangler dev
```

## Read API (`/v1`)

FOX-82. A route for `/v1/*` on the webcam host (`routes` in `wrangler.jsonc`): the Lambda's four reads,
answered by the Cloud Run service [`services/twaqi-api`](../../services/twaqi-api/README.md)
with the Lambda's exact bytes. The webcam paths on the same host (`/stations/…`,
`/manifest.json`) never reach the Worker. Code: `src/api.ts`.

| Route | |
| --- | --- |
| `GET /v1/countries` | Countries |
| `GET /v1/stations?country=…` / `country_id=…` | A country's stations |
| `GET /v1/current-pollutants?country=…` / `station_id=1,2,3` | Latest readings |
| `GET /v1/historical-pollutants?station_id=…&limit=…` | A station's history (max 100) |

- Forwards to `TWAQI_API_ORIGIN_URL` with the header `x-twaqi-origin-token: TWAQI_API_ORIGIN_TOKEN`
  (secret; same value as Secret Manager `twaqi-api-origin-token` and the `workers-production`
  environment secret). Cloud Run answers 403 without it.
- Successful answers are cached at the edge for `TWAQI_API_CACHE_SECONDS` (600, 10 minutes)
  and carry `x-twaqi-cache: HIT|MISS`. The data changes every 20 minutes. The cache key and
  the origin query keep only the route's own params (first value each, fixed order), so an
  extra `?_=N` or a reordered query can't bypass the cache.
- The Worker sets `cache-control` itself on every 200: `public, max-age=600` on a MISS, and on
  a HIT `max-age` = 600 minus the cached copy's `age`, at least 0, so a reading is at most
  10 minutes old in total. What `caches.default.match` returns would otherwise carry the
  zone's 4-hour Browser Cache TTL (`max-age=14400`).
- Cloud Run errors never reach the apps as HTML: an origin 4xx becomes 502
  `{"success":false,"error":"Upstream error"}`, a 5xx keeps its status, an unreachable origin is
  502. None are cached. Other `/v1/` paths are 404; writes are 405.
- Check a deploy against the Lambda: `cd services/twaqi-api && make compare BASE=https://<webcam host>`.
