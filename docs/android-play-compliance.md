# Google Play compliance answers: Android app (FOX-61)

Proposed answers for Play Console's **App content** forms for `com.kfpun.twaqi` (phone app and
Wear OS app, one listing). They are a draft for the person filling the forms in. Every answer
comes from the code, with `file:line` evidence. Kotlin paths such as `push/PushApi.kt` are
under `android/app/src/main/kotlin/com/kfpun/twaqi/`; paths starting `app/`, `wear/` or `gradle/`
are under `android/`; `web/` is at the repository root. Re-check them against the code before each submission that adds an SDK, a
permission or a new request.

The privacy policy URL in App content is `https://taiwanair.wahthefox.com/privacy.html`. That
page (`web/privacy.html`) still describes the iOS app only. Update it for Android (Google Play,
Firebase Cloud Messaging on Android, Play Billing, AdMob, Firebase Analytics and Crashlytics)
before sending the Data safety form, so the two say the same thing.

## What the app sends, and to whom

| Flow | What leaves the device | Recipient | Evidence |
| --- | --- | --- | --- |
| Air quality, forecast, cams | Country code, station ids. No location, no identifiers | Our API, the webcam host | `app/src/main/kotlin/com/kfpun/twaqi/data/remote/ApiClient.kt:45-60` |
| Push alerts | Random per-install device id, FCM token, app version, language, Pro yes/no, notification permission, quiet hours with time zone; per station: station id, the cam site id, the above and below AQI levels | Our push service (signed with the install's secret), then Firebase Cloud Messaging for delivery | `push/PushApi.kt:109-130`, `push/PushApi.kt:214-271`, `push/PushIdentity.kt:19-36` |
| Feedback form | Email (required), name (optional), rating, message, other feedback, interview interest; app version, device model, OS version, locale, a random per-install id | Our form backend (create only) | `feedback/FeedbackSubmission.kt:90-100`, `forms/ClientInfo.kt:34-42`, `ui/help/FeedbackScreen.kt:73-74` |
| Business partner form | Type, company, name, job title (optional), email, phone (optional), website (optional), message; app version, device model, OS version, locale. No per-install id | Our form backend (create only) | `cooperate/CooperateSubmission.kt:81-95`, `forms/ClientInfo.kt:31` |
| Analytics | App interaction events (64 call sites through `Analytics.logEvent`), the Firebase app instance id, device and app info | Firebase Analytics (release builds only) | `analytics/Analytics.kt:200-204`, `app/build.gradle.kts` (`FIREBASE_COLLECTION_ENABLED` false in debug) |
| Crash reports | Stack traces, device and app info, a Crashlytics installation id | Firebase Crashlytics (release builds only) | `analytics/TrackingManager.kt:125-133`, `gradle/libs.versions.toml:67` |
| Ads | Advertising ID, IP (approximate location), ad interactions, device info | Google AdMob, only for free users and only once Google's consent form (UMP) allows ads | `gradle/libs.versions.toml:79-80`, `ads/AdsPolicy.kt`, `ads/AdConsent.kt:19-33`, merged manifest: `com.google.android.gms.permission.AD_ID` |
| Purchases | Handled by Google Play Billing; the app reads the result and sends only "Pro yes/no" to the push service | Google Play, our push service | `gradle/libs.versions.toml:78`, `push/PushSync.kt:268` |
| Device location | Nothing. Read on the device to centre the map, sort stations nearest first, pick the forecast region, the widget's and the watch's nearest station | Stays on the device | `ui/main/LocationAccess.kt:22-50`, `ui/main/MapScreen.kt:79-115`, `ui/forecast/ForecastViewModel.kt:60-63`, `widget/WidgetLocation.kt:28-39`, `wear/src/main/kotlin/com/kfpun/twaqi/watch/data/WatchApi.kt:92` |
| On-device translation | Nothing. ML Kit downloads its language model; text is translated on the device | Google (model download only) | `gradle/libs.versions.toml:88`, `translation/OnDeviceTranslation.kt` |
| Phone ↔ watch | Favourites, Pro yes/no, language; locked-complication events back | The user's own paired watch (Wearable Data Layer), not a server | `app/src/main/kotlin/com/kfpun/twaqi/wear/PhoneStateRelay.kt`, `…/wear/WatchEventRelay.kt` |

Permissions (`app/src/main/AndroidManifest.xml:4-16`): `INTERNET`, `ACCESS_NETWORK_STATE`,
`POST_NOTIFICATIONS`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `WRITE_EXTERNAL_STORAGE`
(Android 8–9 only, to save a share card). The Wear OS app asks only for `INTERNET` and
`ACCESS_COARSE_LOCATION` (`wear/src/main/AndroidManifest.xml:6-8`). Libraries add
`com.google.android.gms.permission.AD_ID`, `com.android.vending.BILLING` and the FCM receive
permission to the merged manifest.

## Data safety form

**Overview**

- Does the app collect or share any of the required user data types? **Yes.**
- Is all user data collected by the app encrypted in transit? **Yes.** Targeting API 36 with no
  `usesCleartextTraffic` and no network security config (`app/src/main/AndroidManifest.xml`),
  Android refuses plain HTTP; the push service accepts https only (`push/PushApi.kt:54-58`);
  Firebase, AdMob and Play use TLS.
- Do you provide a way for users to request that their data is deleted? **Yes.** Through
  Help › Feedback, as the privacy policy says (`web/privacy.html:95-97`). The app has no
  accounts, so Play's account-deletion URL does not apply.

**Data types.** Play's definitions: data that is processed only on the device is not
"collected"; data sent to a service provider that processes it for us is "collected", not
"shared"; data an SDK sends to a third party for its own purposes (AdMob's ads) is "shared".

| Category › type | Collected | Shared | Optional | Purposes | Why |
| --- | --- | --- | --- | --- | --- |
| Location › Approximate location | Yes | Yes | No | Advertising or marketing | AdMob derives it from the IP address for ads. The app's own use of the phone's location stays on the device (table above). |
| Location › Precise location | **No** | No | – | – | Read only on the device; never sent anywhere (`data/remote/ApiClient.kt:45-60`). |
| Personal info › Name | Yes | No | No | App functionality (replying to the user) | Feedback form (optional field) and business partner form (required field, `CooperateSubmission.kt:41`). |
| Personal info › Email address | Yes | No | No | App functionality (replying to the user) | Both forms; a valid email is required to send either (`FeedbackSubmission.kt:47`, `CooperateSubmission.kt:42`). |
| Personal info › Phone number | Yes | No | Yes | App functionality | Business partner form, optional field. |
| Personal info › Other info | Yes | No | No | App functionality | Business partner form: company (required, `CooperateSubmission.kt:40`), job title and website (optional). |
| Financial info › Purchase history | Yes | No | No | App functionality | Pro yes/no, sent with the push device so Pro features follow the subscription (`push/PushApi.kt:121`). Payment details stay with Google Play. |
| Messages › Other in-app messages | Yes | No | No | App functionality | The feedback and business partner messages; both forms require one. |
| App activity › App interactions | Yes | Yes | No | Analytics; Advertising or marketing | Firebase Analytics events (analytics, as a service provider); AdMob ad interactions (shared, advertising). |
| App activity › Other actions | Yes | No | No | App functionality | The stations a user follows for alerts, their AQI levels and quiet hours (`push/PushApi.kt:267-271`); only once alerts are switched on. |
| App info and performance › Crash logs | Yes | No | No | Analytics | Crashlytics. |
| App info and performance › Diagnostics | Yes | No | No | Analytics; App functionality | Crashlytics and Analytics device info; device model, OS version and app version in the forms. |
| Device or other IDs | Yes | Yes | No | App functionality; Analytics; Advertising or marketing | Advertising ID (AdMob, shared, advertising); FCM token and the random push device id (alerts); Firebase app instance and installation ids (analytics); the random per-install id in the feedback form. |

Not collected: health and fitness, contacts, calendar, photos and videos (the share card is
made on the device and handed to the share sheet or saved locally), audio, files, web
browsing, installed apps, search history (station search runs on the device), SMS, emails.

Optional vs required: **Optional** means the user can leave that field blank and still use
the feature. Only the phone number qualifies (business partner form). Everything a feature
cannot work without is **required**, even though the feature itself is opt-in: the email
and message in both forms; the name, company and enquiry type in the business partner form
(`FeedbackSubmission.kt:46-47`, `CooperateSubmission.kt:38-43`); the followed stations for
alerts. Where one form makes a field optional and the other requires it (name), answer
required. Analytics, crash reports and ads data are sent by default in release builds; the
per-install analytics opt-out sits behind a hidden developer gesture
(`ui/help/HelpScreen.kt:184-187`), so answer **required** for them.

**Security practices:** encrypted in transit, yes; deletion request, yes (above). Independent
security review: no. Families policy: not applicable (see Target audience).

## Content rating (IARC questionnaire)

- Category: **Reference, News, or Educational**. If the questionnaire's list doesn't fit, use
  "All Other App Types". It is a utility showing government air quality data.
- Violence, fear, sexuality, nudity, crude language, controlled substances, gambling: **No**
  to all.
- Users can interact or exchange content with each other: **No.** The forms go to the
  developer only; the share card goes through the system share sheet.
- Shares the user's physical location with other users: **No.**
- Allows purchase of digital goods: **Yes** (the Pro subscription).
- Contains ads: **Yes.**
- Unrestricted internet access (a web browser or search engine): **No.**

Expected result: Everyone / PEGI 3 / 普遍級, with the "In-app purchases" interactive element.

## Target audience and content

- Target age groups: **13–15, 16–17 and 18 and over.** Not under 13, so the Families policy
  doesn't apply.
- Could the app appeal to children? **No.** Air quality readings, health advice, no
  characters or games aimed at children. The level faces are simple icons, so if asked about
  appeal, explain they are AQI level indicators shared with the iOS app.
- Ads: AdMob serves to everyone who isn't Pro, after Google's consent form; no
  child-directed treatment is requested.

## Ads

- Does the app contain ads? **Yes.** AdMob banners (`ads/AdBanner.kt`, `ads/AdPlacement.kt`) for
  users without Pro (`ads/AdsPolicy.kt`). Debug builds use Google's test ids only (FOX-61,
  `app/build.gradle.kts`).

## Advertising ID

- Does the app use an advertising ID? **Yes.** The merged manifest has
  `com.google.android.gms.permission.AD_ID`, from `play-services-ads`
  (`gradle/libs.versions.toml:79`); Firebase Analytics also reads it when present.
- Purposes: **Advertising or marketing** (AdMob) and **Analytics** (Firebase Analytics).
- Not used for: account management, fraud prevention, personalization outside ads.

## Other App content declarations

- News app: **No.** Government app: **No.** The app is independent; the welcome screen says
  it is not run by the government. Financial features: **None.** Health: **None** (both already
  saved as drafts in Play Console).
- COVID-19 contact tracing or status: **No.**
- Data safety, content rating and these declarations go to review together with the first
  release and the privacy policy change.
