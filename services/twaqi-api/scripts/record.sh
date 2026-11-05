#!/usr/bin/env bash
# Re-record the golden fixtures from the live Lambda: `make record`.
# Writes each raw response body unchanged, so the tests compare bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
LAMBDA=https://t8dqflx6ec.execute-api.us-west-2.amazonaws.com/api
jq -r '.[] | "\(.name) \(.path)"' test/cases.json | while read -r name path; do
  curl -fsS "$LAMBDA$path" -o "test/fixtures/$name.json"
  echo "$name: $(wc -c < "test/fixtures/$name.json" | tr -d ' ') bytes"
done
