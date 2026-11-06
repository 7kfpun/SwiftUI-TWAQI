# TWAQI Android — agent context

Native Kotlin + Jetpack Compose + Material 3 app: the `app` module (FOX-51, FOX-52), the Wear OS
app `wear` and the shared `core` library (FOX-62).
The repo-wide rules in the root `CLAUDE.md` still apply (branches, draft PRs, LGTM, merge
only on the user's greenlight). Read `README.md` here for setup.

## Branches: the Android integration branch

Until PR #77 merges to master, `feature/fox-52-android-project-setup` is the Android
integration branch. Branch each Android ticket (`feature/fox-nn-*`) off it and open the PR
**against it**, not master: `gh pr create --base feature/fox-52-android-project-setup`.
The coordinator merges those PRs in; #77 then takes everything to master. The Android
check, the Claude review, PR policy, Secret files, Public text and the LGTM gate run on
PRs into it as on master. One gap until the gate change reaches master: an LGTM written as
a PR *comment* runs master's gate, which skips this base, so the `LGTM` status updates only
on the next push or LGTM-gate re-run. An LGTM left as a PR *review* updates it at once.

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
- **Strings** (FOX-56): `values/strings.xml` (en) and `values-zh-rTW/strings.xml` (zh-Hant)
  are ported from the iOS `Localizable.strings`; names are the iOS keys in snake_case
  (`Help.language` → `help_language`). Add every new string to both files
  (`StringResourcesTest` fails otherwise).
- **App language** (FOX-56): `AppLocale` holds the in-app choice (Help › Language). Code that
  runs without an activity (widgets, notifications, workers) must get its text from
  `AppLocale.localizedContext(context)`, or it shows the phone's language below Android 13
  (the iOS widget bug FOX-42).
- **Pro** (FOX-58) has one source: `ProGraph.repository(context)` (`isPro`, `entitlement`),
  re-read from Play Billing on every start and cached in DataStore (left out of backups).
  Widgets, the alert limit and ads read it; never keep a separate Pro flag. The Play products
  are one subscription `com.kfpun.twaqi.subscription.adfree` with base plans `adfree-1m`,
  `adfree-6m`, `adfree-12m`, and the one-time lifetime product `com.kfpun.twaqi.adfree` (FOX-123,
  iOS's id) listed last (`ProPlan`). Pro = a paid subscription or an acknowledged lifetime
  purchase; both product types are queried, and lifetime's row is hidden until Play lists it. Open the Pro screen only through `ProNavigation`
  (with a `ProScreenSource`); `twaqi://pro?source=…` opens it too. Banners are `AdBanner`, shown
  only by `AdsPolicy` (free user, UMP consent given), at the standard 320x50 (`AdsPolicy.bannerSize`).
  Debug builds always use Google's test AdMob ids; `verifyReleaseAdIds` stops a release that
  would ship test, placeholder or malformed ids (FOX-61). Debug builds launched with
  `--ez demo_billing true` sell demo plans without Play (`DemoBillingGateway`).
- **Appearance** (FOX-97): Help › Appearance (System / Light / Dark) is AppCompat's night mode,
  applied at process start (`AppAppearanceStore`, `TwaqiApplication`). Activities must be
  `AppCompatActivity`, and anything dark-aware (the map style, FOX-54) follows
  `isSystemInDarkTheme()`; never read the phone's setting directly.
- **Welcome flow** (FOX-96): opens by itself once, behind iOS's versioned flag
  (`OnboardingStore.CURRENT_VERSION`, key `onboardingShownVersion` in the `settings` prefs),
  marked when it opens; Help › Getting started runs it again. Raise the version to show a
  reworked flow once more. Its Lottie files in `assets/onboarding/` are the iOS files, unchanged
  (`OnboardingTest` compares them byte for byte).
- **Wear OS** (FOX-62): `wear` has the same application id and signing key as `app` (Play and the
  Data Layer need both), versionCodes from **203000000** (`WearIdentityTest`), minSdk 30. Kotlin
  both apps need (indices, level bands and colours, `TaiwanTime`, the Data Layer contract) lives
  in `core`, not copied; resources (strings, the face images) are each app's own.
  `PhoneStateRelay` sends the watch the favourites, Pro and language; keep it fed when any of
  those gets a new source.
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
