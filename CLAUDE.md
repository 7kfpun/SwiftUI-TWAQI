# TWAQI — agent context

Taiwan air-quality app: SwiftUI iPhone/iPad app (`TWAQI`, iOS 15), Home Screen widget,
Apple Watch app + complication, visionOS app, and Cloudflare Workers under `workers/`.
Read `README.md` first — it is the source of truth for services, tests and CI.

## Facts that are easy to get wrong

- **Backend is Directus on `https://cms.wahthefox.com`**, not Airtable. In-app feedback
  writes `twaqi_feedback` and the business partner form (`CooperateView`) writes
  `twaqi_cooperate`, both create-only with soft delete via `archived`; the 空品區 forecast
  is read from `twaqi_aqi_forecast`.
- **Push is OneSignal**, dual-written to Directus (`twaqi_push_devices`,
  `twaqi_push_subscriptions`) by `DirectusPushMirror`, always *after* the OneSignal write
  and best-effort. The FCM cutover (`feature/twaqi-fcm-cutover`) is not merged.
- **Favourites ↔ alerts** (`FavouriteAlerts`): an alert on ⇒ the station is a favourite;
  removing a favourite turns its alerts off. OneSignal tag codes: English name in Taiwan,
  numeric id elsewhere.
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

- Branch `feature/*` off `master`; open a **draft** PR to `master`. CI (unit-test subset,
  vulnerability checks, Claude review) runs only on non-draft `feature/*` PRs.
- Don't merge, bump versions, archive, or upload to TestFlight/App Store unless asked.
- Workers deploy on merge to `master`; don't deploy them from a branch.

## Tests

- Run the **full** `TWAQITests` locally before a PR is marked ready / merged:
  `xcodebuild test -workspace TWAQI.xcworkspace -scheme TWAQI -destination 'platform=iOS Simulator,name=<iPhone>,OS=latest' -only-testing:TWAQITests`
- GitHub CI runs only a high-signal subset (offline caches, push dual-write,
  favourites ↔ alerts, cam history, `SettingsStore`) — listed in `.github/workflows/ci.yml`.
  Add a suite there only if it guards one of those areas.
- Workers: `cd workers/twaqi-workers && npm test`.

## Self-review before opening a PR

Run through this — it is what the Claude Code Review workflow checks:

1. **Ticket scope.** Does the diff do everything the Linear ticket (FOX-nn) asks, and
   nothing outside it? If the ticket removes UI (button, row, picker, section), is it gone
   from the views *and* its `Localizable.strings` keys (en + zh-Hant)?
2. **PR body claims.** Every behavioral claim ("no behavior change", "removes X",
   "tests cover Y") is backed by the diff. Quote the ticket scope in the body.
3. **Blocking invariants.** OneSignal write first, Directus mirror after, never instead;
   a Directus failure never blocks or reverts OneSignal; switching off archives, never
   deletes; favourites ↔ alerts stay in step; reordering favourites leaves alerts alone.
4. **Correctness:** force unwraps, optionals, off-by-one, `Asia/Taipei` vs device time
   zone, Codable key mismatches; UI updates on the main actor; widget/App Group sharing.
5. **Tests:** full `TWAQITests` passed locally; new logic in a CI-subset area has a test.
6. No style nitpicks — SwiftLint (`.githooks/pre-commit`) covers those.
