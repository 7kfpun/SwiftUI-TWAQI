# twaqi-workers

Cloudflare Worker that mirrors MOENV air-quality station webcam JPEGs (`aqx_p_01`) into R2 bucket `twaqi-station-cams` and serves them publicly via the R2 custom domain `twaqi.app.wahthefox.com`.

- **Cron** `*/10 * * * *`: latest `aqx_p_01` zip → unzip (fflate) → `stations/{siteId}.jpg` + `manifest.json`. A zip already synced (same source URL) is skipped, and images whose timestamp hasn't changed aren't re-uploaded.
- `siteId` is the MOENV image site id from the filename (`001-202610302200.jpg` → `001`), **not** a TWAQI station id.
- Station name and lat/lon come from `info.xml` (`site`, `TWD97Lat`, `TWD97Lon`), falling back to `Data.csv`.

## Endpoints

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

## Deploy

GitHub Actions deploys this Worker when a merge to master changes `workers/twaqi-workers/` (see `.github/workflows/workers.yml`). Run the **Workers** workflow by hand to redeploy.

Secrets are listed in `secrets.required` in `wrangler.jsonc`. CI uploads them from GitHub repository secrets of the same names on every deploy:

```sh
gh secret set MOENV_API_KEY -R 7kfpun/SwiftUI-TWAQI
gh secret set SYNC_TOKEN -R 7kfpun/SwiftUI-TWAQI
```

Local development:

```sh
npm install
npx wrangler dev
```
