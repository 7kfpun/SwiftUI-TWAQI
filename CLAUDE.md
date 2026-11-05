# TWAQI — agent context

Taiwan air-quality app: SwiftUI iPhone/iPad app (`TWAQI`, iOS 15), Home Screen widget,
Apple Watch app + complication, visionOS app, and Cloudflare Workers under `workers/`.
Read `README.md` first — it is the source of truth for services, tests and CI.

## Facts that are easy to get wrong

- **Backend is Directus** (the app's `DirectusUrl`), not Airtable. In-app feedback
  writes `twaqi_feedback` and the business partner form (`CooperateView`) writes
  `twaqi_cooperate`, both create-only with soft delete via `archived`; the 空品區 forecast
  is read from `twaqi_aqi_forecast`.
- **Push is Firebase Cloud Messaging** (FOX-13). Alerts and do-not-disturb live in
  Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`), written by
  `DirectusPushMirror`: saved on the device first, synced in the background and retried.
  The app holds **no Directus token for push**: it calls the Worker's `/app/v1` API, signed
  with its Keychain device id and secret, and only the Worker writes Directus (FOX-37 M5).
  The device row carries the APNs and FCM tokens; `workers/twaqi-push-sender` reads it and
  sends through FCM, logging to `twaqi_push_logs` (token suffix only). The OneSignal SDK
  stays in the app with the same alert tags (`OneSignalTags`), so OneSignal can be switched
  back on later; its sending is off. FCM is the live sender.
- **Favourites ↔ alerts** (`FavouriteAlerts`): an alert on ⇒ the station is a favourite;
  removing a favourite turns its alerts off. Alerts are keyed by station id. At most 3 stations
  have alerts (`FavouriteAlerts.maxAlertedStations`).
- **Station cams** are R2 behind the webcam host (`StationCams` base URL; it also serves the `/v1` read API): latest
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
  non-draft `feature/*` PRs, `Workers` and `Public text` on every non-draft PR; `PR policy`,
  `Secret files` and the `LGTM` status on every PR. Map: `docs/ci-cd-guardrails.md`.
- Merge only after another agent's LGTM covers the head and the user gives the greenlight, squash only. The LGTM is a pull request review or comment whose first line is `**<Name> LGTM**`, with any reviewer name, e.g. `**Grok LGTM** (head abc1234)`. A later `**<Name> — changes needed**` cancels it. The advisory Claude Code Review bot doesn't count. That turns the `LGTM` status green. Rebasing or updating the branch from `master` keeps it, as long as the PR's own changes stay the same; conflict fixes or new commits need a fresh LGTM. Don't start a comment with "LGTM" unless you reviewed the head.
- Don't merge, bump versions, archive, or upload to TestFlight/App Store unless asked.
- Workers deploy on merge to `master`; don't deploy them from a branch.
- **The repo is public.** Commits, PR descriptions (and their edit history), PR and issue
  comments, and docs are readable by anyone. Keep out of them: IP addresses, network
  ranges and allow-lists, changes to network access rules, which services are or were
  reachable from anywhere, incident details (attacker IPs, outage causes, what got hit), secret
  values or any part of them, database hosts, and account emails. **Hostnames:** only the
  public websites (`taiwanair.wahthefox.com`, `kf-twaqi.web.app`, `kf-nihongo.web.app`) may
  be named; every other host (API, webcam, Directus, Workers, Cloud Run, the Lambda) is
  named by its role ("the webcam host", "Directus") and lives only in the code or config
  that needs it. Name a resource only when a runbook or the code needs the name (a
  secret's name, never its value). Infra state, hosts, security changes and incident notes
  go in the Linear ticket (internal, so fine there); the PR links to it. Details: `docs/ci-cd-guardrails.md#public-repo-what-stays-out`.

## Tests

- Run the **full** `TWAQITests` locally before a PR is marked ready / merged:
  `xcodebuild test -workspace TWAQI.xcworkspace -scheme TWAQI -destination 'platform=iOS Simulator,name=<iPhone>,OS=latest' -only-testing:TWAQITests`
- GitHub CI runs only a high-signal subset (offline caches, push dual-write,
  favourites ↔ alerts, cam history, `SettingsStore`) — `CI_TEST_SUITES` in `.github/workflows/ci.yml`.
  Add a suite there only if it guards one of those areas, **and** add its test file and the
  source files it tests to `CI_GUARDED_PATHS` beside it (the job fails if they drift apart).
- The `Unit tests` job has three levels (FOX-79, `tools/ci_test_level.py`): **skip** for PRs
  touching only `workers/`, `web/`, `fastlane/`, `assets/`, docs, media or `.github/` other than
  `ci.yml` and `.github/actions/unit-tests-build`; **build** (no simulator) for any other app
  path; **test** (build + subset) when a guarded path, `ci.yml`, its build action, the level
  script, `Podfile(.lock)` or `Package.resolved` changes, or the PR has the `ci-full-tests`
  label. The check name stays `Unit tests` at every level.
- CI builds the CI-only `TWAQI-CI` scheme (`TWAQI` minus the `TWAQIUITests` runner) with
  `build-for-testing` + `test-without-building`. Use `-scheme TWAQI` locally; if you change
  the `TWAQI` scheme's build or test targets, mirror it in `TWAQI-CI`.
- The job's cache and build steps live in `.github/actions/unit-tests-build`, shared with
  `ci-cache.yml`, which fills the same three caches (Swift packages, Pods, DerivedData) from
  `master` on dependency changes, daily and by hand (FOX-65). PRs restore `master`'s caches
  and save only on a miss. Change cache keys or build flags in the action, never in one
  workflow alone. The `Prepare gitignored config` step is copied in both workflows; change
  both (`tools/ci_test_level.py check` fails when they differ).
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
