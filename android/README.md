# TWAQI for Android

Native Kotlin + Jetpack Compose + Material 3. The `app` module, package `com.kfpun.twaqi`
(it updates the existing Play listing), minSdk 26, compileSdk / targetSdk 36; the Wear OS app
`wear` and the shared `core` (FOX-62, see Wear OS below).
Decisions: FOX-51. Setup: FOX-52. Features follow from FOX-53.

The iOS app is in [`../ios`](../ios). Shared parts stay at the repository root:
`workers/`, `services/`, `web/`, `docs/`, `tools/`, `assets/` and `.github/` (FOX-89).

## Branches: the Android integration branch

Until PR #77 merges to master, `feature/fox-52-android-project-setup` is the Android
integration branch. Branch each Android ticket (`feature/fox-nn-*`) off it and open the PR
**against it**, not master: `gh pr create --base feature/fox-52-android-project-setup`.
The coordinator merges those PRs in; #77 then takes everything to master. The Android
check, the Claude review, PR policy, Secret files, Public text and the LGTM gate run on
PRs into it as on master. One gap until the gate change reaches master: an LGTM written as
a PR *comment* runs master's gate, which skips this base, so the `LGTM` status updates only
on the next push or LGTM-gate re-run. An LGTM left as a PR *review* updates it at once.

## Toolchain

JDK 17 and the Android command-line tools (Homebrew), with platform 36 and build-tools:

```sh
export JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$(brew --prefix)/share/android-commandlinetools
```

Android Studio works too: open the `android/` folder. Always build with `./gradlew`.

## Build, test, lint

```sh
cd android
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk (and wear/…/wear-debug.apk)
./gradlew test                 # JVM unit tests
./gradlew lint                 # Android lint
./gradlew ktlintCheck          # Kotlin style (ktlintFormat fixes it)
./gradlew installDebug         # onto a running emulator or device
```

CI (`.github/workflows/android.yml`, check **Android**) runs
`./gradlew ktlintCheck lint test assembleDebug` with the example config on every pull request
that changes `android/` or the workflow, and on pushes to master. Other pull requests get a
green **Android** check without a build, so it can be a required check.

## Config and secrets

All of these are gitignored. A clean checkout builds without any of them.

| File | What | Template |
| --- | --- | --- |
| `secrets.properties` | `API_DOMAIN`, `MAPS_API_KEY`, Directus URL and tokens, `STATION_CAMS_URL` (the webcam host), AdMob app and ad unit ids, Play service-account path | `secrets.example.properties` |
| `app/google-services.json` | Firebase (Crashlytics, Analytics) | Firebase console |
| `keystore.properties` | release signing | `keystore.example.properties` |
| `play-service-account.json` | Play upload (or the path in `PLAY_SERVICE_ACCOUNT_JSON`) | Google Cloud / Play Console |

- `secrets.properties` overrides `secrets.example.properties` key by key. Values reach the app
  as `BuildConfig.API_DOMAIN`, `BuildConfig.DIRECTUS_URL`, `BuildConfig.DIRECTUS_FEEDBACK_TOKEN`,
  `BuildConfig.DIRECTUS_COOPERATE_TOKEN`, `BuildConfig.STATION_CAMS_URL`, and the Maps key as the manifest's
  `com.google.android.geo.API_KEY`. The names match `ios/TWAQI/Config/example.xcconfig` on iOS.
- Anything in `BuildConfig` or the manifest ships inside the APK and can be read out of it,
  as on iOS. The Directus tokens must stay create-only on their collections
  (`twaqi_feedback`, `twaqi_cooperate`) and read-only on `twaqi_aqi_forecast`; push goes
  through the Worker's signed API and needs no Directus token.
- **Firebase:** register the Android app `com.kfpun.twaqi` in the TWAQI Firebase project and
  save its `google-services.json` to `android/app/`. The google-services and Crashlytics Gradle
  plugins apply only when that file exists.

## Pro and ads (FOX-58)

- **Play Console → Monetize → Subscriptions:** one subscription
  `com.kfpun.twaqi.subscription.adfree` with three auto-renewing base plans, `adfree-1m`
  (1 month), `adfree-6m` (6 months) and `adfree-12m` (12 months). The app shows each base
  plan's own offer (no trial or intro offer, as on iOS). Test with license testers on a
  closed-test track; an emulator without Play shows "Retry" instead of plans.
- **AdMob:** the Android app's id goes in `ADMOB_APP_ID`, its banner units in
  `AD_UNIT_ID_*_FOOTER` (one per placement, as on iOS). The example file holds Google's test
  ids. Ads load only after Google's UMP consent allows them, and never for Pro.
- **Without Play:** a debug build started with
  `adb shell am start -n com.kfpun.twaqi/.MainActivity --ez demo_billing true` sells demo
  plans in memory, for screenshots and UI checks.

## Wear OS (FOX-62)

Two more modules sit beside `app`:

| Module | What |
| --- | --- |
| `core` | Android library, no resources: `AirIndexType`, `AirLevel` (the level bands and colours the phone's `AirStatus` builds on), `TaiwanTime`, and the phone ↔ watch contract (`WearContract`, `PhoneState`, `LockedComplicationPayload`). Both apps depend on it. |
| `wear` | The Wear OS app (Compose for Wear OS, minSdk 30): the reading for the nearest or chosen station, the station picker with the phone's favourites, the Pro paywall, a complication (`AqiComplicationService`, set up in `ComplicationConfigActivity`) and a tile (`AqiTileService`). The iOS counterparts are `ios/TWAQIWatch` and `ios/TWAQIWatchWidget`. |

- **Same application id** `com.kfpun.twaqi` as the phone app: Play takes a Wear OS app into the
  same listing only with it, and the Wearable Data Layer only pairs apps with the same id **and
  signing key**. `:wear` signs its release with the same `keystore.properties`.
- **versionCode:** Wear OS builds use **203000000 and up**, above every phone code (3000000 and
  up, which must stay below 200000000) and increasing with every Wear OS upload. Play needs every
  APK and bundle in a listing to have its own code, so the two ranges never meet.
  `WearIdentityTest` guards the range; `versionName` follows the phone's.
- **Data:** the watch reads the API itself (`WatchApi`, `API_DOMAIN` from `secrets.properties`)
  and caches its readings, purged after a week as on the phone. The phone sends the favourites,
  Pro (`ProRepository.isPro`) and the app language over the Data Layer (`PhoneStateRelay` in
  `app`); the watch sends back the locked-complication events, which the phone logs to Firebase
  as `watch_complication_locked` (`WatchEventListenerService`), as on iOS.
- **Pro:** the watch app and the face complication are free; the complication's number, its other
  styles and the tile are Pro. The watch follows the phone's Pro; its paywall opens the phone's Pro
  screen (`twaqi://pro?source=watch`). Debug builds have a Pro override in the station list's
  developer section (tap the version 7 times).
- **Language:** the phone app's language when the phone has sent one, else the watch's.
- **Try it:** `./gradlew :wear:installDebug` onto a Wear OS emulator or watch. Pair it with a phone
  running `app` (Wear OS app on the phone) for favourites, Pro and the language.
- **Release:** done by hand, only when asked. Add the Wear OS form factor to the app in Play
  Console, then upload `./gradlew :wear:bundleRelease` to a Wear OS track. Nothing in Gradle
  uploads it.

## Version

`versionCode` starts at **3000000** and must always be above it and increase with every
upload (the old React Native app used codes up to 2097176). `versionName` starts at 2.0.0.
Both live in `app/build.gradle.kts`; `AppIdentityTest` fails if the code drops below 3000000.

## Release (Play internal track)

Done by hand, only when asked. Nothing in CI signs or uploads.

1. **Signing.** The listing already exists, so the first upload must be signed with the old
   app's upload key, or with a new upload key registered through Play App Signing (Play
   Console → Test and release → App integrity). Copy `keystore.example.properties` to
   `keystore.properties` and point it at the keystore, kept outside the repo.
   Without `keystore.properties`, `assembleRelease` / `bundleRelease` produce an unsigned
   build and any `publish…Bundle` / `publish…Apk` task stops with a message.
2. **Service account.** In Google Cloud, create a service account with a JSON key; in Play
   Console → Users and permissions, invite it with release rights for this app. Save the key
   as `android/play-service-account.json` (or set `PLAY_SERVICE_ACCOUNT_JSON` in
   `secrets.properties`).
3. **Upload.** Raise `versionCode`, then:

   ```sh
   ./gradlew publishReleaseBundle   # Gradle Play Publisher: internal track, as a draft
   ```

   Roll the draft out to internal testers in Play Console.
