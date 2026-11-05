# TWAQI Android — agent context

Native Kotlin + Jetpack Compose + Material 3 app, one `app` module (FOX-51, FOX-52).
The repo-wide rules in the root `CLAUDE.md` still apply (branches, draft PRs, LGTM, merge
only on the user's greenlight). Read `README.md` here for setup.

## Facts that are easy to get wrong

- **Package id `com.kfpun.twaqi`** updates the old React Native app's Play listing. Never
  change it.
- **versionCode** stays above **3000000** and only goes up (the old app shipped codes up to
  2097176). `AppIdentityTest` guards it. versionName starts at 2.0.0.
- minSdk 26, compileSdk and targetSdk 36. JDK 17.
- **Config** comes from `secrets.properties` (gitignored), key by key over
  `secrets.example.properties`. Add a new key to the example file with a dummy value, then
  read it in `app/build.gradle.kts` (`secret("NAME")` → BuildConfig or a manifest placeholder).
- **Firebase** is Crashlytics + Analytics only (FOX-85: no Sentry, no Bugsnag). The plugins
  apply only when `app/google-services.json` (gitignored) exists, so code must not assume
  Firebase is initialised.
- **Signing** comes from `keystore.properties` (gitignored). Without it a release is unsigned
  and `publish*Bundle` stops. Never create, commit or print a keystore or service account.
- **Backup:** `allowBackup` is on so favourites and settings follow the user to a new phone.
  Exclude device secrets (e.g. the push device secret) and caches in
  `res/xml/backup_rules.xml` and `data_extraction_rules.xml` when they are added.
- Don't upload to Play, bump versions or release unless asked.

## Commands (from `android/`)

```sh
export JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$(brew --prefix)/share/android-commandlinetools
./gradlew ktlintCheck lint test assembleDebug   # what the Android CI job runs
./gradlew ktlintFormat                          # fix formatting
```

## Public repo

Commits, PR text, comments and docs are public. No hostnames other than
`taiwanair.wahthefox.com`, `kf-twaqi.web.app` and `kf-nihongo.web.app`, no IPs, keys, tokens,
account emails or infra details. Real hosts and keys live only in the gitignored config
files; example files hold dummy values (`example.com`, `placeholder-…`).
