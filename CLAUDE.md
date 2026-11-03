# TWAQI — agent context

Taiwan air-quality app: SwiftUI iPhone/iPad app (`TWAQI`, iOS 15), Home Screen widget,
Apple Watch app + complication, visionOS app, and Cloudflare Workers under `workers/`.
Read `README.md` first — it is the source of truth for services, tests and CI.

## Facts that are easy to get wrong

- **Backend is Directus on `https://cms.wahthefox.com`**, not Airtable. In-app feedback
  writes `twaqi_feedback` and the business partner form (`CooperateView`) writes
  `twaqi_cooperate`, both create-only with soft delete via `archived`; the 空品區 forecast
  is read from `twaqi_aqi_forecast`.
- **Push is Firebase Cloud Messaging** (FOX-13). Alerts and do-not-disturb live in
  Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`), written by
  `DirectusPushMirror`: saved on the device first, synced in the background and retried.
  The device row carries the APNs and FCM tokens; `workers/twaqi-push-sender` reads it and
  sends through FCM, logging to `twaqi_push_logs` (token suffix only). No OneSignal in the
  app; the old OneSignal tracker in `ai-playground` still serves pre-FOX-13 builds.
- **Favourites ↔ alerts** (`FavouriteAlerts`): an alert on ⇒ the station is a favourite;
  removing a favourite turns its alerts off. Alerts are keyed by station id. No station cap (FOX-41).
- **Station cams** are R2 behind `https://twaqi.app.wahthefox.com`: latest
  `stations/{siteId}.jpg`, hourly `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg`, rolling 24 h.
  `siteId` is the MOENV image site id, not a station id. A missing hour is a normal 404.
- **Time zone:** Taiwan-local logic (cam hour keys, forecast dates, MOENV publish times)
  uses `Asia/Taipei`, never the device zone. UTC timestamps from the API stay UTC.
- Offline caches are purged after a week; any new cache directory must sit inside a
  directory `OfflineCacheRetention` scans.
- `debug.xcconfig`, `release.xcconfig`, `GoogleService-Info.plist` are gitignored — copy
  from `TWAQI/Config/example.xcconfig`. Never commit real keys.

## Workflow

- Branch `feature/fox-nn-*` off `master`; open a **draft** PR to `master` using the PR
  template. CI (unit-test subset, vulnerability checks, Claude review) runs only on
  non-draft `feature/*` PRs, `Workers` on every non-draft PR; `PR policy`, `Secret files`
  and the `LGTM` status on every PR. Map: `docs/ci-cd-guardrails.md`.
- Merge only after another agent's LGTM covers the head and the user gives the greenlight, squash only. The LGTM is a pull request review or comment whose first line is `**<Name> LGTM**`, with any reviewer name, e.g. `**Grok LGTM** (head abc1234)`. A later `**<Name> — changes needed**` cancels it. The advisory Claude Code Review bot doesn't count. That turns the `LGTM` status green. Rebasing or updating the branch from `master` keeps it, as long as the PR's own changes stay the same; conflict fixes or new commits need a fresh LGTM. Don't start a comment with "LGTM" unless you reviewed the head.
- Don't merge, bump versions, archive, or upload to TestFlight/App Store unless asked.
- Workers deploy on merge to `master`; don't deploy them from a branch.

## Tests

- Run the **full** `TWAQITests` locally before a PR is marked ready / merged:
  `xcodebuild test -workspace TWAQI.xcworkspace -scheme TWAQI -destination 'platform=iOS Simulator,name=<iPhone>,OS=latest' -only-testing:TWAQITests`
- GitHub CI runs only a high-signal subset (offline caches, push dual-write,
  favourites ↔ alerts, cam history, `SettingsStore`) — listed in `.github/workflows/ci.yml`.
  Add a suite there only if it guards one of those areas.
- CI builds the CI-only `TWAQI-CI` scheme (`TWAQI` minus the `TWAQIUITests` runner) with
  `build-for-testing` + `test-without-building`. Use `-scheme TWAQI` locally; if you change
  the `TWAQI` scheme's build or test targets, mirror it in `TWAQI-CI`.
- Workers: `cd workers/<name> && npm test` (`twaqi-workers`, `twaqi-push-sender`).

## Self-review before opening a PR

Run through this — it is what the Claude Code Review workflow checks:

1. **Ticket scope.** Does the diff do everything the Linear ticket (FOX-nn) asks, and
   nothing outside it? If the ticket removes UI (button, row, picker, section), is it gone
   from the views *and* its `Localizable.strings` keys (en + zh-Hant)?
2. **PR body claims.** Every behavioral claim ("no behavior change", "removes X",
   "tests cover Y") is backed by the diff. Quote the ticket scope in the body.
3. **Blocking invariants.** Alert changes are saved on the device first and reach
   Directus later, never lost on a failed write; switching off archives, never deletes;
   favourites ↔ alerts stay in step; reordering favourites leaves alerts alone.
4. **Correctness:** force unwraps, optionals, off-by-one, `Asia/Taipei` vs device time
   zone, Codable key mismatches; UI updates on the main actor; widget/App Group sharing.
5. **Tests:** full `TWAQITests` passed locally; new logic in a CI-subset area has a test.
6. No style nitpicks — SwiftLint (`.githooks/pre-commit`) covers those.
