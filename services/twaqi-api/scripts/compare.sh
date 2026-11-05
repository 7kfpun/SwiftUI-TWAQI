#!/usr/bin/env bash
# Compare a deployed API with the Lambda, request by request, byte for byte:
#   scripts/compare.sh https://<host>
# To hit Cloud Run directly, set TWAQI_API_ORIGIN_TOKEN (sent as the origin
# token header); `make compare` does that. A 20-minute pull can land between
# the two reads: rerun a reading mismatch before suspecting the code.
set -uo pipefail
cd "$(dirname "$0")/.."
base="${1:?usage: scripts/compare.sh <base URL>}"
base="${base%/}"
LAMBDA=https://t8dqflx6ec.execute-api.us-west-2.amazonaws.com/api
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
header=()
[ -n "${TWAQI_API_ORIGIN_TOKEN:-}" ] && header=(-H "x-twaqi-origin-token: $TWAQI_API_ORIGIN_TOKEN")
total=0; failed=0
while read -r name path; do
  total=$((total + 1))
  a=$(curl -s -o "$tmp/lambda" -w '%{http_code}' "$LAMBDA$path")
  b=$(curl -s -o "$tmp/new" -w '%{http_code}' ${header[@]+"${header[@]}"} "$base$path")
  la=$(wc -c < "$tmp/lambda" | tr -d ' '); lb=$(wc -c < "$tmp/new" | tr -d ' ')
  if [ "$a" = "$b" ] && cmp -s "$tmp/lambda" "$tmp/new"; then
    echo "same  $name  lambda $a ${la}B  new $b ${lb}B"
  else
    failed=$((failed + 1))
    echo "DIFF  $name  lambda $a ${la}B  new $b ${lb}B"
    cmp "$tmp/lambda" "$tmp/new" | sed 's/^/      /'
  fi
done < <(jq -r '.[] | "\(.name) \(.path)"' test/cases.json)
if [ "$failed" -gt 0 ]; then echo "$failed of $total differ"; exit 1; fi
echo "all $total identical"
