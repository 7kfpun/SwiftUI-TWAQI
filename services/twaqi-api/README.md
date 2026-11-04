# twaqi-api (Cloud Run)

The TWAQI read API (FOX-82): the Lambda's four `/v1` reads, same paths, params and response
bytes, served from Cloud Run and read from the Lambda's MySQL. Written in Rust (axum,
mysql_async); the container is a distroless image with one static-ish binary. The Lambda
(`7kfpun/lambda-serverless`) keeps pulling MOENV into MySQL every 20 minutes; this service
only reads.

```
app / push sender ─▶ Worker twaqi-workers, route <webcam host>/v1/* (10 min edge cache)
                     ─▶ Cloud Run twaqi-api (kf-personal-tools, asia-east1)
                          ─▶ Cloud SQL kf-personal-tools:asia-east1:mysql (built-in connection, user twaqi_read)
```

| Endpoint | Params | Response |
|---|---|---|
| `GET /v1/countries` | — | `{success, data: [{id, code, name, lat, lon, zoom}]}` |
| `GET /v1/stations` | `country=<code>` or `country_id=<id>` | `{success, data: [Station]}`, `lat` descending |
| `GET /v1/current-pollutants` | `country` / `country_id`, or `station_id=1,2,3` | `{success, data: [station fields + reading]}` |
| `GET /v1/historical-pollutants` | `station_id` or `station`, `limit` (default 24, max 100) | `{success, station, data: [reading]}`, oldest first |

Error answers keep the Lambda's `{"success":false,"error":"…"}` messages. Deliberate
differences:

- an unknown country answers `"No such a country"` (the Lambda sent a 500 with a Python traceback);
- a database failure is a 500 `{"success":false,"error":"Internal error"}`, with the detail only
  in Cloud Logging;
- in `current-pollutants`, a reading whose station row is missing is left out (the Lambda raised
  `KeyError`, a 500);
- `station_id` takes at most 100 distinct ids (Taiwan has 84 stations); more answer
  `"Too many station ids"`. The Lambda had no cap.

Every `/v1` request needs the header `x-twaqi-origin-token` (Secret Manager
`twaqi-api-origin-token`, also the Worker's `TWAQI_API_ORIGIN_TOKEN`); without it the service
answers 403. `/health` needs no token (not `/healthz`: Cloud Run reserves it) and doesn't touch the database.

## Same bytes as the Lambda

`src/pyjson.rs` writes JSON the way Chalice does: compact separators, non-ASCII as `\uXXXX`,
MySQL DECIMAL as a Python float (`17.0`, `0.8`), JSON-in-TEXT columns re-serialized with their
stored key order, `*_display` strings rounded half-to-even on the exact decimal (Python's
`Decimal.__format__`, not float rounding), and `publish_time` as the stored Taiwan-local time
with no zone.

## Tests

Rust stable (`brew install rustup && rustup default stable`), `jq` and `curl`.

```sh
make check          # cargo fmt --check, clippy -D warnings, cargo test
make record         # re-record test/fixtures from the live Lambda (scripts/record.sh)
make compare        # live Cloud Run vs the Lambda, byte for byte (scripts/compare.sh)
make compare BASE=https://<webcam host>    # the same through Cloudflare
```

The golden tests (`tests/golden.rs`) rebuild database rows from each recorded Lambda
response (`test/fixtures`, cases in `test/cases.json`) and check the handler writes that
exact body back; `tests/server.rs` covers the token gate, `/health`, 404/405, HEAD and a
database failure. The `Services` check (`.github/workflows/services.yml`) runs fmt, clippy and
the tests on PRs that change `services/`; the app's `Unit tests` skip it. Run `make check` before deploying too.

## Deploy (by hand)

One-off, from this folder, as a project owner. Nothing here is automated: merging a PR
does not deploy Cloud Run.

### 1. Service account and secrets (once)

```sh
P=kf-personal-tools
SA=twaqi-api@$P.iam.gserviceaccount.com
gcloud iam service-accounts create twaqi-api --project $P \
  --display-name "twaqi-api (Cloud Run, FOX-82)"
# Generated straight into Secret Manager; never printed.
openssl rand -hex 32 | tr -d '\n' | gcloud secrets create twaqi-api-origin-token --project $P --data-file=-
openssl rand -hex 24 | tr -d '\n' | gcloud secrets create twaqi-api-db-password --project $P --data-file=-
gcloud projects add-iam-policy-binding $P --member serviceAccount:$SA \
  --role roles/cloudsql.client --condition=None
for s in twaqi-api-origin-token twaqi-api-db-password; do
  gcloud secrets add-iam-policy-binding $s --project $P --member serviceAccount:$SA \
    --role roles/secretmanager.secretAccessor
done
```

### 2. Read-only MySQL user (once)

Through the Cloud SQL Auth Proxy:

```sh
brew install cloud-sql-proxy          # or: gcloud components install cloud-sql-proxy
cloud-sql-proxy kf-personal-tools:asia-east1:mysql --port 3307 &
PW="$(gcloud secrets versions access latest --secret twaqi-api-db-password --project kf-personal-tools)"
/opt/homebrew/opt/mysql-client/bin/mysql -h 127.0.0.1 -P 3307 -u root -p <<SQL
CREATE USER 'twaqi_read'@'%' IDENTIFIED WITH caching_sha2_password BY '$PW';
GRANT SELECT ON aqi.country TO 'twaqi_read'@'%';
GRANT SELECT ON aqi.station TO 'twaqi_read'@'%';
GRANT SELECT ON aqi.pollutant TO 'twaqi_read'@'%';
GRANT SELECT ON aqi.currentpollutant TO 'twaqi_read'@'%';
SQL
unset PW
kill %1
```

### 3. Deploy

`make deploy` runs the tests, then this (every setting each time, so a deploy always
matches the Makefile), then `make health`:

```sh
P=kf-personal-tools
gcloud run deploy twaqi-api \
  --project $P --region asia-east1 \
  --source . \
  --service-account "twaqi-api@$P.iam.gserviceaccount.com" \
  --add-cloudsql-instances kf-personal-tools:asia-east1:mysql \
  --set-env-vars DB_SOCKET=/cloudsql/kf-personal-tools:asia-east1:mysql,DB_USER=twaqi_read,DB_NAME=aqi,DB_CONNECTION_LIMIT=3 \
  --set-secrets DB_PASSWORD=twaqi-api-db-password:latest,ORIGIN_TOKEN=twaqi-api-origin-token:latest \
  --allow-unauthenticated \
  --cpu 1 --memory 512Mi --cpu-boost \
  --min-instances 0 --max-instances 3 --concurrency 40 --timeout 30
```

- `--allow-unauthenticated`: the service checks the Worker's origin token itself.
- `--max-instances 3` × `DB_CONNECTION_LIMIT=3` caps it at 9 MySQL connections (db-f1-micro).
- `make status` prints the service URL; the Worker's `TWAQI_API_ORIGIN_URL` must match it.

### 4. Check against the Lambda

`make health` and `make compare` do this:

```sh
URL="$(gcloud run services describe twaqi-api --project kf-personal-tools --region asia-east1 --format 'value(status.url)')"
curl -s "$URL/health"                                          # {"ok":true}
curl -s -o /dev/null -w '%{http_code}\n' "$URL/v1/countries"    # 403
TWAQI_API_ORIGIN_TOKEN="$(gcloud secrets versions access latest --secret twaqi-api-origin-token --project kf-personal-tools)" \
  scripts/compare.sh "$URL"
```

### 5. Hand the token to the Worker deploy

```sh
gcloud secrets versions access latest --secret twaqi-api-origin-token --project kf-personal-tools \
  | gh secret set TWAQI_API_ORIGIN_TOKEN --env workers-production
```

Then `twaqi-workers` deploys with `workers.yml` on merge and starts answering
`/v1/...` on the webcam host (see `workers/twaqi-workers/README.md`, Read API).

To redeploy after a code change: `make deploy`. `make help` lists the other targets
(`status`, `logs`, `compare`, `record`). To rotate the origin token, add a new
version to `twaqi-api-origin-token`, redeploy (step 3), update the GitHub secret (step 5) and
redeploy the Worker.
