# TWAQI — Taiwan air quality

Taiwan air-quality app for iPhone, iPad, Apple Watch, Apple Vision Pro and Android, with Home Screen widgets, push alerts and station cams. Website, privacy policy and terms: [taiwanair.wahthefox.com](https://taiwanair.wahthefox.com). Contact: [info@wahthefox.com](mailto:info@wahthefox.com).

## Download

[![App Store Button](assets/app-store.png "App Store Button")](https://itunes.apple.com/tw/app/id1286516443?mt=8)
&nbsp;
[**Get it on Google Play**](https://play.google.com/store/apps/details?id=com.kfpun.twaqi)

## Screenshots

### iOS

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios0.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios3.png" width="210">

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios4.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios5.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios6.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-ios7.png" width="210">

### Android

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/android/app/src/main/play/listings/en-US/graphics/phone-screenshots/1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/android/app/src/main/play/listings/en-US/graphics/phone-screenshots/2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/android/app/src/main/play/listings/en-US/graphics/phone-screenshots/3.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/android/app/src/main/play/listings/en-US/graphics/phone-screenshots/4.png" width="210">

### Apple Watch

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch0.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch1.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch2.png" width="210"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-apple-watch3.png" width="210">

### Apple Vision Pro

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro0.png" width="420"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro1.png" width="420">

<img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro2.png" width="420"> <img src="https://raw.github.com/7kfpun/SwiftUI-TWAQI/master/assets/screenshot-vision-pro3.png" width="420">

## Repository layout

Two platforms in one repository (FOX-89):

| Folder | What |
| --- | --- |
| `ios/` | The Apple app: `TWAQI.xcworkspace` / `TWAQI.xcodeproj`, the targets (`TWAQI`, `TWAQIWidget`, `TWAQIWatch`, `TWAQIWatchWidget`, `TWAQIVision`, `TWAQITests`, `TWAQIUITests`), `Podfile`, `fastlane/` and `.swiftlint.yml` |
| `android/` | The Android app (Kotlin + Jetpack Compose, package `com.kfpun.twaqi`) and its Wear OS app; see [`android/README.md`](android/README.md) |
| root | Shared: `.github/`, `.githooks/`, `docs/`, `tools/`, `assets/`, `services/`, `web/`, `workers/`, Firebase Hosting (`firebase.json`, `.firebaserc`) |

## Development (iOS)

```bash
# Clone this repo
$ git clone git@github.com:7kfpun/SwiftUI-TWAQI.git

# Go inside the iOS project and install pod dependencies
$ cd SwiftUI-TWAQI/ios && pod install

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

The commands above run in `ios/`. `ios/TWAQI/Config/debug.xcconfig`, `release.xcconfig` and `ios/TWAQI/GoogleService-Info.plist` are gitignored; they hold real keys. So is `ios/fastlane/.env`.

Targets: `TWAQI` (iPhone/iPad, iOS 15), `TWAQIWidget`, `TWAQIWatch` + `TWAQIWatchWidget`, `TWAQIVision` (visionOS), all under `ios/`. Cloudflare Workers live under `workers/<name>/`, the Cloud Run read API under `services/twaqi-api/`.

## Development (Android)

Needs JDK 17 and the Android command-line tools (platform 36). Details, config and release steps: [`android/README.md`](android/README.md).

```bash
export JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$(brew --prefix)/share/android-commandlinetools

cd android
# Optional: real keys. A clean checkout builds with secrets.example.properties alone.
cp secrets.example.properties secrets.properties   # then fill in API_DOMAIN, MAPS_API_KEY, ...
./gradlew ktlintCheck lint test assembleDebug
```

`android/secrets.properties`, `android/app/google-services.json` and `android/keystore.properties` are gitignored.

## Services

| What | Where |
| --- | --- |
| Air-quality readings | MOENV open data, pulled into MySQL (Cloud SQL) every 20 min by the AWS Lambda (`7kfpun/lambda-serverless`). The app reads it from the `API_DOMAIN` endpoints in the xcconfig: the Lambda's API, or the same `/v1` API on the webcam host (a route on [`workers/twaqi-workers`](workers/twaqi-workers/README.md#read-api-v1) → Cloud Run [`services/twaqi-api`](services/twaqi-api/README.md), FOX-82), byte-for-byte the same responses |
| In-app feedback (Help → Feedback / Contact us) | Directus (`DirectusUrl`), collection `twaqi_feedback`, with the app's static token (`DirectusFeedbackToken`) |
| 空品區 AQI forecast | Directus `twaqi_aqi_forecast`, filled hourly from MOENV `AQF_P_01` by [`workers/twaqi-workers`](workers/twaqi-workers/README.md); the app only reads it |
| Business partner form (Help → Interested to be our Business Partner?) | Directus collection `twaqi_cooperate`, create-only with `DirectusCooperateToken`, or `DirectusFeedbackToken` when that is empty; soft delete via `archived` |
| Station webcams | R2 bucket `twaqi-station-cams` behind the webcam host (its custom domain), synced every 10 min by `workers/twaqi-workers` |
| Weather on the station page (FOX-11) | Central Weather Administration (CWA) open data (`F-C0032-001` county forecast, `O-A0003-001` observations), written hourly by [`workers/twaqi-workers`](workers/twaqi-workers/README.md#cwa-weather-fox-11) to `weather/latest.json` in the same bucket, read from the webcam host. The CWA key stays in the Worker |
| Push alerts | Firebase Cloud Messaging, settings in Directus (see below) |
| Crash reporting / analytics | Firebase Crashlytics + Analytics only (Swift Package Manager) |
| Website, privacy policy, terms | `web/` on Firebase Hosting at `https://taiwanair.wahthefox.com` (site `taiwanair-wahthefox`); `kf-twaqi.web.app` 301s there. Cutover runbook: [`docs/web-hosting.md`](docs/web-hosting.md) |

### Station webcams

- Latest frame: `<webcam host>/stations/{siteId}.jpg` (plus `manifest.json`, which maps each `siteId` to its name, location and latest `hourKey`).
- Hourly history: `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` — one frame per site per clock hour, `yyyy-MM-dd` and `HH` in **Taiwan time (Asia/Taipei, UTC+8)**. The station screen's scrubber reads the last 24 of these.
- R2 keeps a **rolling 24 h** of hourly frames. A missing hour is a plain 404; the app treats it as missing, not as a failure.
- `siteId` is the MOENV image site id (`001`), not a TWAQI station id; the app matches cams to stations by name, then by distance.
- On device, fetched frames and hourly frames are cached for offline use and purged after a week, along with the other offline caches.

### Weather (CWA)

- The station page's **Weather** card (free, not Pro) sits above the cam: the latest reading of the nearest CWA staffed station within 20 km (temperature, humidity, rain since midnight, wind, with the station's distance and the reading's age), then the next three 12-hour periods of the county's 36-hour forecast (icon, weather text, chance of rain, min–max °C).
- CWA station ids are unrelated to MOENV's; the app joins by position (observations) and by county name (forecast; the nearest CWA station's county when the station has none). The card hides itself when nothing is in range or fresh: readings older than 3 hours and periods that have ended are dropped.
- Weather codes map to the app's own en / zh-Hant strings and SF Symbols (`WeatherCode`). In Chinese the card shows CWA's own text; CWA's free text (descriptions, station names) is never shown in English.
- The last good file is cached on device (`cwa-weather.json` in Application Support) and purged after a week with the other offline caches. Times are Taiwan time.

### Push notifications: Firebase Cloud Messaging (FOX-13)

- **Delivery:** Firebase Messaging (SPM) gets an FCM token from the APNs token; `AppDelegate` hands both to `DirectusPushMirror`. [`workers/twaqi-push-sender`](workers/twaqi-push-sender/README.md)'s `run()` reads every station's AQI every 2 hours, asks Directus for only the subscriptions whose zone that changes (filtered per station), and sends through FCM HTTP v1 when a station crosses a threshold (edge-triggered, quiet hours honoured), logging each send to `twaqi_push_logs` without the full token. The scheduled run is the **`Push sender` GitHub Actions workflow** (`.github/workflows/push-sender.yml`, environment `push-sender`), not a Worker cron: the Cloudflare account is on the Workers Free plan, which can't carry the sends (FOX-71). The Worker serves the app's push API below. It only sends to devices with an FCM token; The app also keeps the OneSignal SDK (no service extension) and writes the same alert and DND tags there (`OneSignalTags`), so OneSignal can be switched back on as a sender; its sending (the `ai-playground` tracker) is being turned off, after which builds before FOX-13, which have no FCM token, get no alerts until they update. The Firebase project needs the APNs auth key. The app clears the icon badge when it opens; alerts set none.
- **Write path (FOX-37 M5):** the app has no Directus token for the push collections. `PushService` calls the `twaqi-push-sender` Worker (`PushApiUrl`: `PUT /app/v1/device`, `GET /app/v1/device`, `PUT /app/v1/stations/:id`, `POST /app/v1/archive-all`), each request signed with the install's Keychain `device_id` and a random secret. The Worker stores only a SHA-256 of the secret and touches only that device's rows; the 3-station limit is enforced in the app only.
- **Settings:** station alerts and the do-not-disturb window live in Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`). Changes are saved on the device first and synced in the background, retried on the next change, launch, foreground or token change. Switching an alert off archives its row; nothing is deleted. A reinstall restores alerts and do-not-disturb from the device's row (Keychain device id).
- **Favourites ↔ alerts:** a station with an alert on is always a favourite, and removing a favourite turns its alerts off (`FavouriteAlerts`). Alerts can be on for at most 3 stations (`FavouriteAlerts.maxAlertedStations`); the station screen locks its switches once 3 others have them.

## Tests

- **Before merge, run the full suite locally** (Mac mini / Orca), from `ios/`:

  ```bash
  cd ios
  xcodebuild test -workspace TWAQI.xcworkspace -scheme TWAQI \
    -destination 'platform=iOS Simulator,name=<an installed iPhone>,OS=latest' \
    -only-testing:TWAQITests
  ```

- **GitHub CI runs a small, high-signal subset** (`-only-testing` in `.github/workflows/ci.yml`) covering the crash- and regression-prone areas: networking/offline caches (`PollutantCacheTests`, `OfflineCacheRetentionTests`), push dual-write and favourites ↔ alerts (`PushServiceTests`, `FavouriteAlertsTests`), the station-cam history loader and caches (`StationCamTests`, `StationCamFrameCacheTests`, `StationCamHistoryCacheTests`), `SettingsStore` persistence (`AppLanguageTests`) and the Directus create-only forms (`FeedbackServiceTests`, `CooperateServiceTests`). Add a suite there only if it guards one of those areas, and then add its test file and the source files it tests to `CI_GUARDED_PATHS` next to it (the job fails when the two lists drift apart).
- **The `Unit tests` job runs at one of three levels**, decided from the PR's file list by [`tools/ci_test_level.py`](tools/ci_test_level.py) (highest level wins). A small Linux job, `Unit tests scope`, decides and prints the level and the files that decided it; at the **skip** level `Unit tests` is skipped and no macOS runner starts (FOX-143):

  | Level | When the PR touches only… | Runs |
  |---|---|---|
  | **skip** | `android/`, `workers/`, `services/`, `web/`, `ios/fastlane/`, `assets/`, docs (`.md`), media, `.github/**` except `.github/workflows/ci.yml` and `.github/actions/unit-tests-build/` | nothing; the `Unit tests` check is skipped, so no macOS runner starts (FOX-143) |
  | **build** | any other path (Swift, strings, asset catalogs, widget / watch / visionOS, `project.pbxproj`) | `build-for-testing` only; no simulator pick, boot or test run |
  | **test** | a `CI_GUARDED_PATHS` entry (the subset suites' test files and the sources they test), `.github/workflows/ci.yml`, `.github/actions/unit-tests-build/`, `tools/ci_test_level.py` (and its test), `ios/Podfile`, `ios/Podfile.lock`, `Package.resolved` | build + boot + the subset |

  The PR label **`ci-full-tests`** forces **test** (labels are read when the job runs: add the label, then re-run the job or push). An empty file list or an API error also gives **test**. The script's tests: `python3 -m unittest discover -s tools -p 'test_ci_test_level.py'`; `python3 tools/ci_test_level.py decide --files <list>` shows the level for a file list.
- CI builds the **`TWAQI-CI`** scheme: `TWAQI` without the `TWAQIUITests` runner, which CI never runs. Locally, keep using `-scheme TWAQI` as above. The job picks its simulator in the background during the build, runs `build-for-testing`, then boots the simulator (booting it during the build slowed both down on slow runners) and runs `test-without-building` against it, and caches Swift packages (`Package.resolved`), `ios/Pods/` (`Podfile.lock`, `Podfile`) and the DerivedData build products (exact key: Xcode build + those three files; app and test sources always rebuild).
- **Caches come from `master`** (FOX-65). The cache and build steps live in [`.github/actions/unit-tests-build`](.github/actions/unit-tests-build/action.yml), shared by `ci.yml` and the **`CI cache`** workflow ([`ci-cache.yml`](.github/workflows/ci-cache.yml)); `ci-cache.yml` carries a copy of `ci.yml`'s config step, and `tools/ci_test_level.py check` fails when the two differ. `CI cache` runs on `master` when `ios/Podfile`, `ios/Podfile.lock`, `Package.resolved`, the `TWAQI-CI` scheme, `ci.yml`, `ci-cache.yml` or the action change, daily (03:17 UTC: a new Xcode on the runner changes the DerivedData key, and caches unused for 7 days are evicted; when all three keys exist the run only restores them) and by hand (Actions → CI cache → Run workflow, on `master`). It builds exactly like the `Unit tests` job, without a simulator or tests, and saves the three caches under the same keys; when all three are already there it restores them (which keeps them alive) and stops. Every PR to `master` can read those caches, so a PR's first run starts warm. A PR saves a cache only when its exact key missed (say the PR changes `Podfile.lock`), into its own scope; it never stores a second copy of what `master` has.
- Workers have their own tests: `cd workers/<name> && npm test` (`twaqi-workers`, `twaqi-push-sender`). So does the Cloud Run API, in Rust: `cd services/twaqi-api && make check`, which the `Services` check (`services.yml`) also runs on PRs that change it; it is deployed by hand.

## Branches, CI and review

- Work on `feature/fox-nn-*` branches and open a PR to `master`, as a draft until it is ready. Flow: Orca codes → another agent's review → user greenlight → squash-merge → TestFlight / App Store / Firebase only when the ticket names them. Full map of checks and deploy paths: [`docs/ci-cd-guardrails.md`](docs/ci-cd-guardrails.md).
- On every PR to `master`, drafts included:
  - **PR policy** — `feature/` branch, `FOX-nn` in the branch or title, `Depends on #N` merged first, and version / build numbers / What's New consistent.
  - **Secret files** — fails on `debug.xcconfig`, `release.xcconfig`, `GoogleService-Info.plist`, `.env`, `.dev.vars`, signing keys, force-added gitignored files or real-looking secret values in the diff.
  - **LGTM** (status) — pending until a reviewer's LGTM covers the head commit: a pull request review or comment whose first line is `**<Name> LGTM**`, with any reviewer name (or none). A later `**<Name> — changes needed**` sets it back to pending. The advisory Claude Code Review bot doesn't count.
- On a **non-draft** PR from `feature/*` to `master`, GitHub also runs:
  - **CI / Unit tests** — the subset above, at the skip / build / test level from [Tests](#tests). Skipped (no macOS runner starts; a skipped required check counts as passing) when the PR only touches docs, media, `android/`, `assets/`, `ios/fastlane/`, `web/`, `workers/` or `.github/` (other than `ci.yml` and the `unit-tests-build` action).
  - **CI / Vulnerability checks** — TruffleHog and osv-scanner, posted as a PR comment. Fails only on secrets TruffleHog **verified** as live; everything else is a warning.
  - **Claude Code Review** — reviews the diff against the ticket scope and the PR body's claims, and marks push / favourites ↔ alerts / dual-write breaks as blocking. A failed review fails the check.
  - **Workers** — typechecks and dry-runs any Worker the PR changes (green when none changed). Merging to `master` deploys only the changed Workers.
- Put the Linear ticket (`FOX-nn`) and its scope in the PR body, and only claim behavior the diff shows — the reviewer checks both. The PR template carries the merge gates.
- `master` protection (required checks, no direct pushes, up-to-date branches) is proposed in [`docs/master-protection.md`](docs/master-protection.md).
- Releases (version bump, TestFlight, App Store) use the fastlane lanes in [`ios/fastlane/README.md`](ios/fastlane/README.md) (run from `ios/`) and are run by hand, never from a feature PR. Screenshot uploads refuse to run while the version is `WAITING_FOR_REVIEW` (`fastlane asc_version_state` shows the state). The website deploys through the manual `Firebase Hosting` workflow.

## Releases

Both stores are released by hand-off scripts, never from a feature PR, and name no secrets in the repository.

- **iOS:** a scheduled job builds `master` every day and uploads it to TestFlight when the iOS app changed since the last build. Each Friday another job submits the latest TestFlight build of the current version for App Store review with **manual release**, so it only goes live when the owner releases it. Lanes: [`ios/fastlane/README.md`](ios/fastlane/README.md).
- **Android:** the Gradle Play Publisher tasks and the Play API scripts upload the bundle, listing and release notes ([`android/README.md`](android/README.md#release-play-internal-track)). Managed publishing is off, so an update goes live as soon as Google approves it.

## License

Released under the [MIT License](http://opensource.org/licenses/MIT).
