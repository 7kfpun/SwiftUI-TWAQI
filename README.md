# WIP: SwiftUI-TWAQI

## Download

[![App Store Button](assets/app-store.png "App Store Button")](https://itunes.apple.com/tw/app/id1286516443?mt=8)

## Screenshots

### iOS

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios0.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios3.png" width="210">

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios4.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios5.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios6.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios7.png" width="210">

### Apple Watch

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch0.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch3.png" width="210">

### Apple Vision Pro

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro0.png" width="420"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro1.png" width="420">

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro2.png" width="420"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro3.png" width="420">

## Development

```bash
# Clone this repo
$ git clone git@github.com:7kfpun/SwiftUI-TWAQI.git

# Go inside the project and install pod dependencies
$ cd SwiftUI-TWAQI && pod install

# Copy example config
$ cp TWAQI/Config/example.xcconfig TWAQI/Config/debug.xcconfig

# Get a Google Maps API key, https://developers.google.com/maps/documentation/ios-sdk/get-api-key, and update the key `GMSServicesApiKey` in the debug.xcconfig file
$ open TWAQI/Config/debug.xcconfig

# Create a Firebase project and download the config file, GoogleService-Info.plist, to the folder, https://firebase.google.com/docs/ios/setup
$ cp ~/GoogleService-Info.plist TWAQI/GoogleService-Info.plist

# Directus: set DirectusFeedbackToken (and optionally DirectusCooperateToken) in debug.xcconfig, and PushApiUrl for push — see the comments in example.xcconfig

# Open Xcode and run with Command (⌘)-R
$ open TWAQI.xcworkspace
```

`debug.xcconfig`, `release.xcconfig` and `GoogleService-Info.plist` are gitignored; they hold real keys.

Targets: `TWAQI` (iPhone/iPad, iOS 15), `TWAQIWidget`, `TWAQIWatch` + `TWAQIWatchWidget`, `TWAQIVision` (visionOS). Cloudflare Workers live under `workers/<name>/`.

## Services

| What | Where |
| --- | --- |
| Air-quality readings | MOENV open data, served to the app from the `API_DOMAIN` endpoints in the xcconfig |
| In-app feedback (Help → Feedback / Contact us) | Directus on `https://cms.wahthefox.com`, collection `twaqi_feedback`, with the app's static token (`DirectusFeedbackToken`) |
| 空品區 AQI forecast | Directus `twaqi_aqi_forecast`, filled hourly from MOENV `AQF_P_01` by [`workers/twaqi-workers`](workers/twaqi-workers/README.md); the app only reads it |
| Business partner form (Help → Interested to be our Business Partner?) | Directus collection `twaqi_cooperate`, create-only with `DirectusCooperateToken`, or `DirectusFeedbackToken` when that is empty; soft delete via `archived` |
| Station webcams | R2 bucket `twaqi-station-cams` behind `https://twaqi.app.wahthefox.com`, synced every 10 min by `workers/twaqi-workers` |
| Push alerts | Firebase Cloud Messaging, settings in Directus (see below) |
| Crash reporting / analytics | Firebase Crashlytics + Analytics (Swift Package Manager), Bugsnag, Sentry |
| Website, privacy policy, terms | `web/` on Firebase Hosting at `https://taiwanair.wahthefox.com` (site `taiwanair-wahthefox`); `kf-twaqi.web.app` 301s there. Cutover runbook: [`docs/web-hosting.md`](docs/web-hosting.md) |

### Station webcams

- Latest frame: `https://twaqi.app.wahthefox.com/stations/{siteId}.jpg` (plus `manifest.json`, which maps each `siteId` to its name, location and latest `hourKey`).
- Hourly history: `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` — one frame per site per clock hour, `yyyy-MM-dd` and `HH` in **Taiwan time (Asia/Taipei, UTC+8)**. The station screen's scrubber reads the last 24 of these.
- R2 keeps a **rolling 24 h** of hourly frames. A missing hour is a plain 404; the app treats it as missing, not as a failure.
- `siteId` is the MOENV image site id (`001`), not a TWAQI station id; the app matches cams to stations by name, then by distance.
- On device, fetched frames and hourly frames are cached for offline use and purged after a week, along with the other offline caches.

### Push notifications: Firebase Cloud Messaging (FOX-13)

- **Delivery:** Firebase Messaging (SPM) gets an FCM token from the APNs token; `AppDelegate` hands both to `DirectusPushMirror`. [`workers/twaqi-push-sender`](workers/twaqi-push-sender/README.md)'s `run()` reads every station's AQI every 2 hours, asks Directus for only the subscriptions whose zone that changes (filtered per station), and sends through FCM HTTP v1 when a station crosses a threshold (edge-triggered, quiet hours honoured), logging each send to `twaqi_push_logs` without the full token. The scheduled run is the **`Push sender` GitHub Actions workflow** (`.github/workflows/push-sender.yml`, environment `push-sender`), not a Worker cron: the Cloudflare account is on the Workers Free plan, which can't carry the sends (FOX-71). The Worker serves the app's push API below. It only sends to devices with an FCM token; The app also keeps the OneSignal SDK (no service extension) and writes the same alert and DND tags there (`OneSignalTags`), so OneSignal can be switched back on as a sender; its sending (the `ai-playground` tracker) is being turned off, after which builds before FOX-13, which have no FCM token, get no alerts until they update. The Firebase project needs the APNs auth key. The app clears the icon badge when it opens; alerts set none.
- **Write path (FOX-37 M5):** the app has no Directus token for the push collections. `PushService` calls the `twaqi-push-sender` Worker (`PushApiUrl`: `PUT /app/v1/device`, `GET /app/v1/device`, `PUT /app/v1/stations/:id`, `POST /app/v1/archive-all`), each request signed with the install's Keychain `device_id` and a random secret. The Worker stores only a SHA-256 of the secret and touches only that device's rows; the 3-station limit is enforced in the app only.
- **Settings:** station alerts and the do-not-disturb window live in Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`). Changes are saved on the device first and synced in the background, retried on the next change, launch, foreground or token change. Switching an alert off archives its row; nothing is deleted. A reinstall restores alerts and do-not-disturb from the device's row (Keychain device id).
- **Favourites ↔ alerts:** a station with an alert on is always a favourite, and removing a favourite turns its alerts off (`FavouriteAlerts`). Alerts can be on for at most 3 stations (`FavouriteAlerts.maxAlertedStations`); the station screen locks its switches once 3 others have them.

## Tests

- **Before merge, run the full suite locally** (Mac mini / Orca):

  ```bash
  xcodebuild test -workspace TWAQI.xcworkspace -scheme TWAQI \
    -destination 'platform=iOS Simulator,name=<an installed iPhone>,OS=latest' \
    -only-testing:TWAQITests
  ```

- **GitHub CI runs a small, high-signal subset** (`-only-testing` in `.github/workflows/ci.yml`) covering the crash- and regression-prone areas: networking/offline caches (`PollutantCacheTests`, `OfflineCacheRetentionTests`), push dual-write and favourites ↔ alerts (`PushServiceTests`, `FavouriteAlertsTests`), the station-cam history loader and caches (`StationCamTests`, `StationCamFrameCacheTests`, `StationCamHistoryCacheTests`), `SettingsStore` persistence (`AppLanguageTests`) and the Directus create-only forms (`FeedbackServiceTests`, `CooperateServiceTests`). Add a suite there only if it guards one of those areas.
- CI builds the **`TWAQI-CI`** scheme: `TWAQI` without the `TWAQIUITests` runner, which CI never runs. Locally, keep using `-scheme TWAQI` as above. The job picks its simulator in the background during the build, runs `build-for-testing`, then boots the simulator (booting it during the build slowed both down on slow runners) and runs `test-without-building` against it, and caches Swift packages (`Package.resolved`), `Pods/` (`Podfile.lock`, `Podfile`) and the DerivedData build products (exact key: Xcode build + those three files; app and test sources always rebuild). Caches are per PR, so a PR's first run is cold.
- Workers have their own tests: `cd workers/<name> && npm test` (`twaqi-workers`, `twaqi-push-sender`).

## Branches, CI and review

- Work on `feature/fox-nn-*` branches and open a PR to `master`, as a draft until it is ready. Flow: Orca codes → another agent's review → user greenlight → squash-merge → TestFlight / App Store / Firebase only when the ticket names them. Full map of checks and deploy paths: [`docs/ci-cd-guardrails.md`](docs/ci-cd-guardrails.md).
- On every PR to `master`, drafts included:
  - **PR policy** — `feature/` branch, `FOX-nn` in the branch or title, `Depends on #N` merged first, and version / build numbers / What's New consistent.
  - **Secret files** — fails on `debug.xcconfig`, `release.xcconfig`, `GoogleService-Info.plist`, `.env`, `.dev.vars`, signing keys, force-added gitignored files or real-looking secret values in the diff.
  - **LGTM** (status) — pending until a reviewer's LGTM covers the head commit: a pull request review or comment whose first line is `**<Name> LGTM**`, with any reviewer name (or none). A later `**<Name> — changes needed**` sets it back to pending. The advisory Claude Code Review bot doesn't count.
- On a **non-draft** PR from `feature/*` to `master`, GitHub also runs:
  - **CI / Unit tests** — the subset above. Skipped when the PR only touches docs, media, `assets/`, `fastlane/`, `web/` or `workers/`.
  - **CI / Vulnerability checks** — TruffleHog and osv-scanner, posted as a PR comment. Fails only on secrets TruffleHog **verified** as live; everything else is a warning.
  - **Claude Code Review** — reviews the diff against the ticket scope and the PR body's claims, and marks push / favourites ↔ alerts / dual-write breaks as blocking. A failed review fails the check.
  - **Workers** — typechecks and dry-runs any Worker the PR changes (green when none changed). Merging to `master` deploys only the changed Workers.
- Put the Linear ticket (`FOX-nn`) and its scope in the PR body, and only claim behavior the diff shows — the reviewer checks both. The PR template carries the merge gates.
- `master` protection (required checks, no direct pushes, up-to-date branches) is proposed in [`docs/master-protection.md`](docs/master-protection.md).
- Releases (version bump, TestFlight, App Store) use the fastlane lanes in [`fastlane/README.md`](fastlane/README.md) and are run by hand, never from a feature PR. Screenshot uploads refuse to run while the version is `WAITING_FOR_REVIEW` (`fastlane asc_version_state` shows the state). The website deploys through the manual `Firebase Hosting` workflow.

## License

Released under the [MIT License](http://opensource.org/licenses/MIT).
