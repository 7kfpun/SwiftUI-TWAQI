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

# Directus: set DirectusFeedbackToken (and optionally DirectusPushToken / DirectusCooperateToken) in debug.xcconfig — see the comments in example.xcconfig

# Open Xcode and run with Command (⌘)-R
$ open TWAQI.xcworkspace
```

`debug.xcconfig`, `release.xcconfig` and `GoogleService-Info.plist` are gitignored; they hold real keys.

Targets: `TWAQI` (iPhone/iPad, iOS 15), `TWAQIWidget`, `TWAQIWatch` + `TWAQIWatchWidget`, `TWAQIVision` (visionOS), `OneSignalNotificationServiceExtension`. Cloudflare Workers live under `workers/<name>/`.

## Services

| What | Where |
| --- | --- |
| Air-quality readings | MOENV open data, served to the app from the `API_DOMAIN` endpoints in the xcconfig |
| In-app feedback (Help → Feedback / Contact us) | Directus on `https://cms.wahthefox.com`, collection `twaqi_feedback`, with the app's static token (`DirectusFeedbackToken`) |
| 空品區 AQI forecast | Directus `twaqi_aqi_forecast`, filled hourly from MOENV `AQF_P_01` by [`workers/twaqi-workers`](workers/twaqi-workers/README.md); the app only reads it |
| Business partner form (Help → Interested to be our Business Partner?) | Directus collection `twaqi_cooperate`, create-only with `DirectusCooperateToken`, or `DirectusFeedbackToken` when that is empty; soft delete via `archived` |
| Station webcams | R2 bucket `twaqi-station-cams` behind `https://twaqi.app.wahthefox.com`, synced every 10 min by `workers/twaqi-workers` |
| Push alerts | OneSignal, with settings dual-written to Directus (see below) |
| Crash reporting / analytics | Firebase Crashlytics + Analytics (Swift Package Manager), Bugsnag, Sentry |
| Website, privacy policy, terms | `web/` on Firebase Hosting at `https://taiwanair.wahthefox.com` (site `taiwanair-wahthefox`); `kf-twaqi.web.app` 301s there. Cutover runbook: [`docs/web-hosting.md`](docs/web-hosting.md) |

### Station webcams

- Latest frame: `https://twaqi.app.wahthefox.com/stations/{siteId}.jpg` (plus `manifest.json`, which maps each `siteId` to its name, location and latest `hourKey`).
- Hourly history: `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` — one frame per site per clock hour, `yyyy-MM-dd` and `HH` in **Taiwan time (Asia/Taipei, UTC+8)**. The station screen's scrubber reads the last 24 of these.
- R2 keeps a **rolling 24 h** of hourly frames. A missing hour is a plain 404; the app treats it as missing, not as a failure.
- `siteId` is the MOENV image site id (`001`), not a TWAQI station id; the app matches cams to stations by name, then by distance.
- On device, fetched frames and hourly frames are cached for offline use and purged after a week, along with the other offline caches.

### Push notifications: OneSignal today, FCM not yet

- **Live on master:** OneSignal (`OneSignalXCFramework` 3.x) owns permission, APNs registration and delivery. Station alerts and the do-not-disturb window are OneSignal tags.
- **Dual-write:** `DirectusPushMirror` copies the same settings to Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`) *after* each OneSignal write. It is best-effort: a Directus failure never blocks or undoes the OneSignal write. Switching an alert off archives its row; nothing is deleted.
- **Favourites ↔ alerts:** a station with an alert on is always a favourite, and removing a favourite turns its alerts off (`FavouriteAlerts`).
- **FCM:** a Firebase Cloud Messaging cutover is on branch `feature/twaqi-fcm-cutover` (FOX-13) and is **not merged**. Firebase Messaging is not in the shipping app.

## Tests

- **Before merge, run the full suite locally** (Mac mini / Orca):

  ```bash
  xcodebuild test -workspace TWAQI.xcworkspace -scheme TWAQI \
    -destination 'platform=iOS Simulator,name=<an installed iPhone>,OS=latest' \
    -only-testing:TWAQITests
  ```

- **GitHub CI runs a small, high-signal subset** (`-only-testing` in `.github/workflows/ci.yml`) covering the crash- and regression-prone areas: networking/offline caches (`PollutantCacheTests`, `OfflineCacheRetentionTests`), push dual-write and favourites ↔ alerts (`PushServiceTests`, `FavouriteAlertsTests`), the station-cam history loader and caches (`StationCamTests`, `StationCamFrameCacheTests`, `StationCamHistoryCacheTests`) and `SettingsStore` persistence (`AppLanguageTests`). Add a suite there only if it guards one of those areas.
- Workers have their own tests: `cd workers/twaqi-workers && npm test`.

## Branches, CI and review

- Work on `feature/*` branches and open a PR to `master`, as a draft until it is ready.
- On a **non-draft** PR from `feature/*` to `master`, GitHub runs:
  - **CI / Unit tests** — the subset above. Skipped when the PR only touches docs, media, `assets/`, `fastlane/`, `web/` or `workers/`.
  - **CI / Vulnerability checks** — TruffleHog and osv-scanner. Warning-only; results are posted as a PR comment.
  - **Claude Code Review** — reviews the diff against the ticket scope and the PR body's claims, and marks push / favourites ↔ alerts / dual-write breaks as blocking. A failed review fails the check.
  - **Workers** — typechecks and dry-runs any Worker the PR changes. Merging to `master` deploys only the changed Workers.
- Put the Linear ticket (`FOX-nn`) and its scope in the PR body, and only claim behavior the diff shows — the reviewer checks both.
- Releases (version bump, TestFlight, App Store) use the fastlane lanes in [`fastlane/README.md`](fastlane/README.md) and are run by hand, never from a feature PR.

## License

Released under the [MIT License](http://opensource.org/licenses/MIT).
