# Analytics

The iPhone app logs Firebase Analytics events through `TrackingManager.logEvent`.
Every event name is a case of `AnalyticsEvent` (`ios/TWAQI/Utils/AnalyticsEvent.swift`),
with its parameters noted beside it. Add a case for a new event. Never rename an
existing one: Firebase would record the new name as a separate event.

Parameters carry no personal data. Station ids are fine. Coordinates and form
contents are not.

## Collection

- Release builds report unless the device is excluded. To exclude it, tap the
  version row in Help 7 times.
- DEBUG (Xcode) runs report nothing, except to **DebugView** when the scheme's
  launch arguments include `-FIRDebugEnabled`. Firebase keeps debug-mode events
  out of the production reports. An excluded device stays off even with the flag.

### Checking new events in DebugView

1. Edit Scheme → Run → Arguments → add `-FIRDebugEnabled`. Don't commit the
   scheme change.
2. Run on a simulator or device. Firebase console → Analytics → DebugView shows
   the events within seconds. Xcode's console prints a `LogEvent` line for each one.

### Android

The Android app (`android/`) logs the same event names through `Analytics.logEvent`
(`analytics/Analytics.kt`), only for the features it has so far. Numbers go to Firebase as
numbers and booleans as 1 / 0, as the iPhone app's do. `TrackingManager` decides whether
anything is sent:

- Release builds report unless the install opted out: tap the version row in Help 7 times
  (a toast confirms; tap 7 more to opt back in). The opt-out is per install and left out of
  backups.
- Debug builds report nothing (collection is off in the manifest from the first event on),
  except to DebugView when started with
  `adb shell am start -n com.kfpun.twaqi/.MainActivity --ez analytics_debug true` after
  `adb shell setprop debug.firebase.analytics.app com.kfpun.twaqi`. An opted-out install stays
  off.
- Without `app/google-services.json` nothing is sent; debug builds still print a `LogEvent`
  line to Logcat for each event.

## Pro funnel

`source` is a `ProScreenSource`: `help_row`, `onboarding`, `widget_locked` or
`deep_link`. Every step of the funnel carries it:

1. `pro_screen_opened`: logged once each time the Pro screen is shown.
2. `pro_plan_selected`: `plan` is `1m`, `6m`, `12m` or `lifetime`. Use this
   as step 2, not `user_premium_buy_product_started`. Both fire on the same
   tap with the same parameters, and the older one is kept only so its
   history carries on. Putting both in one funnel counts each tap twice.
3. `user_premium_buy_product_done`. Alongside it, the purchase also logs
   `user_premium_buy_product_not_completed` (cancelled, or pending Ask to Buy)
   or `user_premium_buy_product_failed`.

To read the funnel by source: Firebase console → Analytics → Explore →
Funnel exploration, with steps 1–3 above and **Breakdown** set to the
event-scoped custom dimension `source`. Register `source` and `plan` under
Custom definitions first.

Related events: `alert_limit_shown` (the "at most three stations" note, `FavouriteAlerts.maxAlertedStations`, on a
station's alerts) and `ad_banner_tapped` (`placement`: `main`, `details`,
`details_list`, `favourites`, `help`). Neither opens the Pro screen today.

## Feedback and review

- `open_feedback_form` (`source`), then `submit_feedback` (`rating`,
  `platform`, `interview_interest`) or `submit_feedback_failed` (`reason`).
- `review_requested` (`source`: `app_opens` with `app_open_count`, or
  `feedback` with `rating`): the app asked StoreKit (Android: Play In-App
  Review) for the review prompt, every 20 app opens and after a 4- or 5-star
  feedback. The OS decides whether it actually shows and throttles it, so
  this count is higher than the number of prompts users saw.
- `write_review_tapped` (`source`: feedback): "Rate on the App Store" /
  "Rate on Google Play" in the thank-you after a 4- or 5-star feedback.

## Onboarding

`onboarding_shown` (`label`: launch, when the flow opens by itself),
`onboarding_step_viewed` (`step`, `index`), `onboarding_location` and
`onboarding_notifications` (`label`: on / off, the answer to each permission
prompt; `onboarding_location` is logged only when the system prompt was
shown), then `onboarding_completed`, or `onboarding_skipped` (`label`:
`step_<index>`). On the closest station step, `onboarding_add_favourite`
(`stationId`) and `onboarding_choose_station` (`stationId`, another station
picked from the list).

Steps since FOX-84 (five): `welcome` (1), `location` (2), `closest_station`
(3), `notifications` (4, quiet hours included), `more` (5: widgets, Siri, the
Forecast tab and Pro). Builds before it had seven: `do_not_disturb` (5),
`data_source` (6) and `premium` (7). Read a funnel across both by step name,
not index: index 5 and `step_5` mean `do_not_disturb` before FOX-84 and `more`
after it.
