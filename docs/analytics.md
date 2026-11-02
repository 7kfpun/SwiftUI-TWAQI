# Analytics

The iPhone app logs Firebase Analytics events through `TrackingManager.logEvent`.
Every event name is a case of `AnalyticsEvent` (`TWAQI/Utils/AnalyticsEvent.swift`),
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

## Pro funnel

`source` is a `ProScreenSource`: `help_row`, `onboarding`, `widget_locked` or
`deep_link`. Every step of the funnel carries it:

1. `pro_screen_opened`: logged once each time the Pro screen is shown.
2. `pro_plan_selected`: `plan` is `1m`, `6m`, `12m` or `lifetime`.
3. `user_premium_buy_product_done`. Alongside it, the purchase also logs
   `user_premium_buy_product_not_completed` (cancelled, or pending Ask to Buy)
   or `user_premium_buy_product_failed`.

To read the funnel by source: Firebase console → Analytics → Explore →
Funnel exploration, with steps 1–3 above and **Breakdown** set to the
event-scoped custom dimension `source`. Register `source` and `plan` under
Custom definitions first.

Related events: `alert_limit_shown` (the "at most two stations" note on a
station's alerts) and `ad_banner_tapped` (`placement`: `main`, `details`,
`details_list`, `favourites`, `help`). Neither opens the Pro screen today.

## Feedback and review

- `open_feedback_form` (`source`), then `submit_feedback` (`rating`,
  `platform`, `interview_interest`) or `submit_feedback_failed` (`reason`).
- `review_requested` (`app_open_count`): the app asked StoreKit for the
  review prompt. iOS decides whether it actually shows.

## Onboarding

`onboarding_shown` (`label`: launch, when the flow opens by itself),
`onboarding_step_viewed` (`step`, `index`), `onboarding_location` and
`onboarding_notifications` (`label`: on / off, the answer to each permission
prompt), then `onboarding_completed`, or `onboarding_skipped` (`label`:
`step_<index>`).
