# TWAQI for Android

Native Kotlin + Jetpack Compose + Material 3. One `app` module, package `com.kfpun.twaqi`
(it updates the existing Play listing), minSdk 26, compileSdk / targetSdk 36.
Decisions: FOX-51. Setup: FOX-52. Features follow from FOX-53.

The iOS app is in [`../ios`](../ios). Shared parts stay at the repository root:
`workers/`, `services/`, `web/`, `docs/`, `tools/`, `assets/` and `.github/` (FOX-89).

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
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
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
| `secrets.properties` | `API_DOMAIN`, `MAPS_API_KEY`, Directus URL and tokens, Play service-account path | `secrets.example.properties` |
| `app/google-services.json` | Firebase (Crashlytics, Analytics) | Firebase console |
| `keystore.properties` | release signing | `keystore.example.properties` |
| `play-service-account.json` | Play upload (or the path in `PLAY_SERVICE_ACCOUNT_JSON`) | Google Cloud / Play Console |

- `secrets.properties` overrides `secrets.example.properties` key by key. Values reach the app
  as `BuildConfig.API_DOMAIN`, `BuildConfig.DIRECTUS_URL`, `BuildConfig.DIRECTUS_FEEDBACK_TOKEN`,
  `BuildConfig.DIRECTUS_COOPERATE_TOKEN`, and the Maps key as the manifest's
  `com.google.android.geo.API_KEY`. The names match `ios/TWAQI/Config/example.xcconfig` on iOS.
- Anything in `BuildConfig` or the manifest ships inside the APK and can be read out of it,
  as on iOS. The Directus tokens must stay create-only on their collections
  (`twaqi_feedback`, `twaqi_cooperate`) and read-only on `twaqi_aqi_forecast`; push goes
  through the Worker's signed API and needs no Directus token.
- **Firebase:** register the Android app `com.kfpun.twaqi` in the TWAQI Firebase project and
  save its `google-services.json` to `android/app/`. The google-services and Crashlytics Gradle
  plugins apply only when that file exists.

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
