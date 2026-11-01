# FOX-37 — Deep review after the feature surge (findings only)

- **Reviewed:** `master` at `2f07bf3` (FOX-29 #33), including bump `cb7d78c` (3.1.4 / 146),
  FOX-26 #30 `b09671f`, FOX-25 #31 `f09fe67`, FOX-31 #32 `0b5898b`, and the earlier FOX-26
  privacy PRs #28 `48080bf` and #29 `f33535a`.
- **Branch:** `feature/fox-37-deep-review`. This file is the only change. No code changes, no merges, no pushes.
- **Not done:** no FOX-36 cleanup, FOX-34/13 on hold, #34/#35 untouched.
- **Method:** read the diffs of #28–#33. Read in full: `FavouriteAlerts`, `PushService`,
  `DirectusPushMirror`, `OneSignalManager`, `SettingsStore`, the Details, Favourites and Help
  view models and views, `ProView`/`IAPManager`, `AppDelegate`, `web/` (en + zh-Hant),
  `TWAQITests/PushServiceTests.swift`, `TWAQIUITests/*`, `.github/workflows/ci.yml` and the
  fastlane `capture_screenshots` lane. Opened the committed raw screenshots.
- **Tests were not run.** This worktree has no `Pods/`, and `pod install` rewrites
  `project.pbxproj`. Every finding comes from reading code or files.

## Summary

| Severity | Count | Items |
| --- | --- | --- |
| High | 3 (+M2 elevated in self-review) | H1 privacy/landing say favourites stay on device; H2 Terms/Privacy say "no subscription"; H3 App Store station screenshots predate FOX-25; **M2 hang/crash treated as H4** |
| Med | 6 | M1–M6 |
| Low | 8 | L1–L8 |
| Test/CI gaps | 7 | T1–T7 |

- **Code merge blockers:** none in this review. Nothing here is a crash on the main path or a
  data-loss bug in shipping code. All three Highs are about copy or assets: two web pages and
  one set of screenshots.
- **Fix before:**
  - H1 and H2 before 3.1.4 goes to App Review or the web copy is promoted.
  - H3 before the FOX-29 screenshots are uploaded.
  - M5 before the FOX-13 FCM cutover.
- **Blockers for Mini LGTM of this summary:** none known. Two things for the reviewer to accept:
  - The full `TWAQITests` suite was not run (see above).
  - M5 depends on how the Directus role is set up on the server, which I couldn't see from the repo.

---

## High

### H1 — Privacy policy and landing page say favourites stay on the device; since FOX-31 they don't

- **Area:** privacy/landing vs FOX-31.
- **What changed:** FOX-31 (#32, merged 09:01 on 1 Nov) makes the heart switch on the "AQI above
  120" alert. That sends the station tag and threshold to OneSignal and copies them to Directus:
  - `TWAQI/Views/Details/DetailsViewModel.swift:165-169`
  - `TWAQI/Views/Details/DetailsViewModel.swift:192-225`
  - `TWAQI/Utils/FavouriteAlerts.swift:209-249`
- **Copy still saying favourites stay on the device.** The privacy copy (#28/#29, merged 00:54)
  predates FOX-31:
  - `web/privacy.html:21`: "Favourites and settings stay on your device."
  - `web/zh-Hant/privacy.html:21` and `:32`: the same, plus 收藏的測站 listed as on-device only.
  - `web/index.html:58` (FAQPage JSON-LD) and `:262`: "Your favourites and settings stay on your device."
  - `web/zh-Hant/index.html:54`: 你的最愛測站與設定都只存在你的裝置上.
  - `web/privacy.html` Notifications: "If you turn on alerts for a station…". The policy only
    describes alerts as something the user switches on themselves. It never says that favouriting
    a station switches them on.
  - `web/index.html:244` step 3: "Tap the heart … choose a threshold". The heart now sets the
    threshold itself.
- **Fix (copy only, en + zh-Hant):** favouriting a station also turns on an AQI alert for it,
  unless two stations already have alerts or notifications are off. That alert's station and
  threshold go to OneSignal and to the Directus copy.

### H2 — Terms and Privacy say Pro is a one-time purchase with "no subscription"; the paywall sells auto-renewing subscriptions and links to those pages

- **Area:** Pro paywall vs legal pages.
- **What the app sells:** 1-, 6- and 12-month auto-renewing subscriptions plus lifetime:
  - `TWAQI/Utils/IAPManager.swift:25-33`
  - `TWAQI/Views/Help/ProView.swift:84-108`
- **What the legal pages say:**
  - The paywall's footer shows "Terms of Use" and "Privacy Policy", which Apple requires beside a
    subscription offer (`ProView.swift:110-126`).
  - `web/terms.html:24-25`: "one non-consumable in-app purchase that removes ads … **There is no
    subscription and nothing renews.**" `web/zh-Hant/terms.html:24-25` says the same (非訂閱制，不會自動續訂).
  - `web/privacy.html:67` and `web/zh-Hant/privacy.html:67`: "The ad-free upgrade is a one-time purchase."
  - The Privacy summary calls Pro "the ad-free upgrade". Pro also unlocks complications and
    medium/large widgets (`ProView.swift:177-183`; landing FAQ `web/index.html`).
- **Why High:**
  - `terms.html` was last touched before subscriptions shipped (`git log -- web/terms.html`;
    subscriptions came in `4ca3033`).
  - FOX-26 moved the paywall links to the new domain (#30) but left the content as it was.
  - Under App Review Guideline 3.1.2, the linked terms contradicting an auto-renewing offer is a
    likely rejection reason.
- **Fix (copy only):** describe the subscriptions, the lifetime option, renewal and cancellation,
  and what Pro includes, in en + zh-Hant.

### H3 — The FOX-29 station screenshots show the layout from before FOX-25

- **Area:** screenshot harness consistency.
- **Evidence:**
  - `fastlane/screenshots_raw/en-US/iPhone 02 station.png` goes header → AQI scale → **Live
    camera** → Pollutants. It has no alerts card and no health advice.
  - `fastlane/screenshots_raw/zh-Hant/iPad 02 station.png` has 健康建議 at the very bottom, under wind.
  - The order on master (`TWAQI/Views/Details/DetailsView.swift:124-195`) is: scale → **alerts
    card** (`:132-135`) → health guidance (`:139-142`) → forecast/cam → pollutants.
- **When they were taken:** the frames read "Last updated … 1:00 AM · 1 hr. ago" and the cam says
  "Captured 23:40 · 2 hr. ago", so roughly 02:00 +0800 on 1 Nov. FOX-25 merged at 09:13 that day.
  The #33 commit is based on master with #31, but the PNGs were taken from an older build.
- **Impact:** the station shot, one of four headline images, leaves out what FOX-25 added. The
  iPhone and iPad sets are both affected (en and zh-Hant), and so are the 03 trend shots. The Duo
  captures are older still.
- **Fix:** re-run `fastlane capture_screenshots` on current master (iPhone and iPad) before any
  upload. That run will hit M3: on a simulator where OneSignal hasn't registered, the alerts card
  shows locked switches and the two-station caption. Fix M3 first, or check the card in the
  captures.

---

## Med

### M1 — The Directus copy doesn't wait for OneSignal to accept the write in three of four paths

- **Area:** push dual-write invariant.
- **The one path that waits:** FOX-31's `enableForNewFavourite` only mirrors after `sendTags`
  succeeds (`FavouriteAlerts.swift:236-244`). A test pins this (`testOneSignalWriteFailureSkipsTheDirectusCopy`).
- **The three that don't:**
  1. **Unfavourite clear:** `FavouriteAlerts.clear` (`FavouriteAlerts.swift:111-127`) starts
     `sendTags(off)` and does not wait for it. It then mirrors `.off` to Directus and posts
     `isOn: false` straight away.
     - If OneSignal fails (offline, not registered), the alert stays live in OneSignal for a
       station that is no longer a favourite.
     - Meanwhile the local record (`knownAlerts`), Directus and the UI all say it is off, and
       nothing retries.
     - This breaks "removing a favourite turns its alerts off".
  2. **Station switches:** `SettingsRowViewModel.stationSetting.didSet`
     (`SettingsRowViewModel.swift:36-53`) sends to OneSignal, then mirrors and posts whatever
     OneSignal answers. This predates FOX-31, but FOX-25 put these switches at the top of the page.
  3. **Help "cancel all":** `HelpViewModel.removeAllNotification` (`HelpViewModel.swift:100-120`)
     calls `DirectusPushMirror.cancelAll()` **before** it reads or writes OneSignal. The comment
     says this is on purpose. It still inverts "OneSignal first", and if the tag read fails,
     Directus is archived while OneSignal keeps sending.
- **Suggested fix (for a ticket):**
  - For 1 and 3, mirror and post only on OneSignal success.
  - If OneSignal fails, keep the station favourited, or queue a retry, and tell the user.
  - For 2, debounce, then mirror on success.

### M2 — `getOneSignalSettings` can leave callers waiting forever and can crash on a bad tag

- **Area:** concurrency / error handling.
- **Where:** `TWAQI/Utils/OneSignalManager.swift`.
- **The problems:**
  - `:67-69`: when `tags == nil` the closure returns without calling `completionHandler`.
  - `:73-75`: a tag whose key or value isn't a `String` hits `return`, which leaves the whole
    closure, not just the loop. Again the handler is never called.
  - `:91, :98, :109, :116`: `Double(value)!` crashes on a non-numeric `*_therhold` tag (for
    example one set by hand in the OneSignal dashboard).
- **Every caller depends on this, with no timeout:**
  - FOX-31 `enableForNewFavourite` would never finish: no hint, no `station_alerts_on_favourite` event.
  - `SettingsRowViewModel` stays `isDisabled = true` (see M3).
  - `FavouriteAlerts.fetch` leaves the Favourites bells on their local guess.
  - Help "cancel all" never shows its confirmation.
- FOX-31 adds a read on every favourite, so this is hit more often than before.
- **Fix:** `continue` instead of `return`; call the handler on every path; `Double(value) ?? skip`.

### M3 — The promoted alerts card shows locked switches and "You can only enable at most for 2 stations" until OneSignal answers, and forever when it doesn't

- **Area:** FOX-25 IA / empty states.
- **Cause:**
  - `SettingsRowViewModel.isDisabled` starts as `true` (`SettingsRowViewModel.swift:28`).
  - It only changes when the OneSignal read succeeds (`:81`).
  - `SettingsRow.swift:54-60` shows the cap caption whenever `isDisabled` is true.
  - `:123` locks every switch that is off.
- **Effect:**
  - Every station page opens with a wrong "two stations" message and locked switches at the
    top. Since FOX-25 that is the first thing under the reading.
  - Offline, before OneSignal registers, or with M2's hang, the message stays.
- **Related:** the cap counts the station itself. With station A's "above" alert on and one other
  station alerted, A's "below" switch is locked even though turning it on adds no new station
  (`isDisabled = stationSettings.count >= 2` includes A; the lock is `isDisabled && !isOn`).
- **Fix:** keep a separate "unknown" state (switches disabled, no cap caption, maybe a small
  "Checking alerts…" line). Compute the cap as "other stations with alerts ≥ 2".

### M4 — Unfavouriting can leave alerts on when the device has no local record yet

- **Area:** favourites ↔ alerts invariant.
- **Where the "has alerts?" guess comes from before OneSignal has been read:** the mirror's
  local record (`FavouriteAlerts.locallyKnown`).
  - `DetailsViewModel.hasAlerts` (`DetailsViewModel.swift:74`) uses it.
  - So does `FavouriteListViewModel.alertedStationIds` (`FavouriteListViewModel.swift:63`).
- **That record is empty for:**
  - alerts switched on before the dual-write shipped, on a station not opened since;
  - a reinstall: the UserDefaults are gone, the Keychain id is kept, the OneSignal tags are kept.
- **In those cases:**
  - **Station page:** the alerts card, which is what reads OneSignal, only appears once `station`
    loads (`DetailsView.swift:132`). Offline, or before the read returns, `hasAlerts == false`.
    The heart then removes the station without asking and without `clear`
    (`DetailsViewModel.swift:170-174`).
  - **Favourites list:** a swipe-delete before `readAlerts` returns — or when it fails, or when
    the station is missing from `favouritePollutants` — removes the station without asking and
    without clearing (`FavouriteListViewModel.swift:97-109, 129-141`).
- **Result:** a station with live alerts that isn't a favourite.
- **Fix idea:** if the state is unknown, either read OneSignal before removing, or always clear
  both candidate tag codes. Clearing tags that were never set is harmless.

### M5 — One static Directus token in every app build can read and update the push collections

- **Area:** secrets/privacy. Verify on the server.
- **The token:**
  - `PushService.Config.current` (`PushService.swift:269-273`) uses `DirectusPushToken` or else
    `DirectusFeedbackToken`.
  - Both come from Info.plist via `getEnv`, so they are plain text in the shipped app.
  - The example config says the feedback role "already has that access": create, read and update
    on `twaqi_push_devices` / `twaqi_push_subscriptions` (`TWAQI/Config/example.xcconfig`, push section).
- **What the code needs from it:**
  - **Read:** `GET` filtered by any `device_id` or `device_token` (`PushService.swift:325-334`)
    and by any `device` (`:339-352`).
  - **Update:** `PATCH` on any row id (`:308, :360, :372`).
  - A shared token can't be limited to "this device's rows".
- **So anyone who pulls the token out of the app can:**
  - list subscription rows (station, threshold, device);
  - archive or edit other people's rows;
  - and, depending on field permissions, read push tokens, OneSignal player ids, time zones and
    DND windows.
- **Impact:**
  - **Today:** the Directus rows are only a copy; OneSignal still sends. But `web/privacy.html`
    says that copy is "only accessible to us".
  - **After FOX-13:** the same token would control real deliveries. That makes this a **blocker for FOX-13**.
- **To check:** the role's field and row permissions in Directus.
- **Longer term:** a Worker that does the device upsert, authenticated per device (for example a
  secret per device id), instead of a token shared by every install.
- **Separately:** the same token is used for feedback (create) and forecast (read). The forms
  already have their own optional `DirectusCooperateToken`. A separate push token that can't touch
  the forms would at least limit the damage.

### M6 — No empty or error state for alerts when the station record is missing or OneSignal can't be reached

- **Area:** error handling under the new IA.
- **Alerts card missing offline:** the card only renders if `viewModel.station` is set
  (`DetailsView.swift:132-135`). `station` comes only from the historical endpoint. When it fails,
  for example a station opened offline from the saved reading, the page shows `OfflineNotice` and
  the reading but no alerts card, with no explanation. That is a page FOX-25 rebuilt around alerts.
- **FOX-31 waits silently offline:** favouriting before `station` loads sets
  `enablesAlertsWhenStationLoads` (`DetailsViewModel.swift:193-195`). If the historical request
  fails, alerts are never switched on, and there is no hint.
- **`.notChanged` is silent:** the outcome for offline, unregistered, or OneSignal failure gives
  the reader nothing (`DetailsViewModel.swift:221-222`). So the heart fills, but alerts may or may
  not be on.
- **Fix idea:** show the card with a disabled "Alerts need a connection" state. Add one
  `.notChanged` hint ("Couldn't switch alerts on — try from the alerts card"), or retry once.

---

## Low

- **L1 — Two favourites at once can go past the cap.**
  - `newFavouriteDecision` counts from one OneSignal read (`FavouriteAlerts.swift:164-173`).
  - Two `enableForNewFavourite` calls in flight (for example the iPad two-pane, or favouriting
    quickly on two pushed pages) can each see one alerted station and both write. That gives three
    alerted stations.
  - The station page then locks, and the cap message is wrong.
- **L2 — The card says "On" when notifications are denied.**
  - `SettingsRow.swift:99` reads only the tags.
  - FOX-31 tells the reader when favouriting with notifications off. Flipping a switch on the card
    itself is never checked, so it can show "On" for alerts that can't arrive.
- **L3 — "Cancel all" doesn't update open screens.**
  - `HelpViewModel.disabledNotification` (`:122-135`) never posts `FavouriteAlerts.changed`. An open
    Favourites list or station page keeps its bells until it reloads.
  - It also shows the success alert even when every `sendTags` failed.
- **L4 — Sentry debug logging in release builds.**
  - `AppDelegate.swift:61-66` starts Sentry with `"debug": true` unconditionally, so release builds
    log verbosely.
- **L5 — Some favourites can't be seen or removed.**
  - A favourite with no current or saved reading (retired, or not reporting) is dropped from the
    list (`FavouriteListViewModel.swift:146-156`). It can't be removed, or have its alerts cleared,
    from Favourites.
  - The heart on its station page still works.
- **L6 — Docs list a different CI subset than CI runs.**
  - `ci.yml:213-222` also runs `FeedbackServiceTests` and `CooperateServiceTests`.
  - The lists in `README.md` (Tests) and `CLAUDE.md` don't mention them.
- **L7 — The screenshot lane collides with parallel worktrees.**
  - `capture_screenshots` defaults to `iPhone 18 Pro` and a shared `-derivedDataPath
    /tmp/twaqi-screenshots` (`fastlane/Fastfile:200-202`).
  - That clashes with other worktrees using the same simulator; the team note is to avoid iPhone
    18 Pro for parallel runs.
  - Pass a dedicated simulator and a per-worktree DerivedData path.
- **L8 — The screenshot harness doesn't enforce "writes nothing".**
  - `dismissSystemAlerts` taps "Allow" on the notification prompt (`AppStoreScreenshotTests.swift:148-158`).
    So each capture registers a OneSignal player under the debug app id.
  - "Nothing is written to OneSignal or Directus" holds only because no switch is tapped.
  - Nothing asserts that the alerts card stays "Off" or that the heart isn't tapped. A future step
    that taps the heart would switch on a real alert (FOX-31).
  - Consider a `-disablePushWrites` launch argument, or denying the notification prompt.

### Checked and found consistent (no finding)

- **IDFV:** only Feedback sends `anonymous_id`; Cooperate passes `anonymousId: false`
  (`FeedbackService.swift:93-106`, `CooperateService.swift:90`). This matches the privacy copy,
  and the `clientMeta` fields match the policy's list.
- **Keychain device id:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  (`DirectusPushMirror.swift:288-314`). "May persist after reinstall, not carried by backup"
  matches. Locked before first unlock → `nil` → `PushError.noDeviceId`; the flush skips and tries
  again later.
- **No ATT prompt**, which matches the Advertising section.
- **No secrets committed:**
  - `ci.yml:110` has a placeholder Maps key.
  - `example.xcconfig` has Firebase Storage download tokens for public example payloads only.
  - The real `*.xcconfig` and `GoogleService-Info.plist` are gitignored.
- **Localisation keys:** en and zh-Hant have identical key sets. FOX-25 removed
  `Details.notifications`; FOX-31's new keys exist in both.
- **Landing:** canonical, hreflang (en / zh-Hant / x-default) and OG on both index pages are
  consistent with each other. The Pro FAQ matches the app.
- **FOX-31 path:** OneSignal goes first; the mirror only runs on success; the decision honours
  `isStillFavourite`; the station page follows `changed` without writing back
  (`SettingsRowViewModel.swift:116-142`); unfavouriting mid-write is undone
  (`DetailsViewModel.swift:211-216`).
- **Main thread:** all `FavouriteAlerts`/OneSignal callbacks hop to main before touching
  `@Published`. The mirror is `@MainActor`.

---

## Test / CI gaps

| # | Sev | Gap | Where |
| --- | --- | --- | --- |
| T1 | Med | `FavouriteAlerts.clear` has no test. Nothing checks the order (OneSignal then Directus) or what happens on OneSignal failure (M1). It's in a CI-subset area. | `FavouriteAlerts.swift:111-127` |
| T2 | Med | `DetailsViewModel`'s FOX-31 steps have no tests: the deferred enable when `station` loads, undoing `.enabled` after an unfavourite, and mapping outcomes to hints. Only `FavouriteAlerts.enableForNewFavourite` is tested. | `DetailsViewModel.swift:165-225` |
| T3 | Med | `FavouriteListViewModel.needsConfirmation` / `remove` (choosing the tag code, falling back to candidates) has no tests, and nothing covers "reordering leaves alerts alone". | `FavouriteListViewModel.swift:122-141`, `FavouriteListView.swift:135-142` |
| T4 | Med | OneSignal tag parsing has no tests (M2: completion never called, force unwraps). It's a static over the SDK, so it would need the parsing pulled out into a pure function to test. | `OneSignalManager.swift:63-128` |
| T5 | Low | `SettingsRowViewModel.followClears` / `isDisabled` has no tests, so nothing guards M3. | `SettingsRowViewModel.swift:28-142` |
| T6 | Low | The `DirectusPushMirror` flush/`cancelAll` logic (wanted/synced bookkeeping, `archiveAll` retry) has no tests; only `knownAlerts` and `PushService.plan` do. | `DirectusPushMirror.swift:103-218` |
| T7 | Low | FOX-25 has no UI or snapshot check, and the screenshot harness doesn't assert the alerts card is present, so H3 wasn't caught. UI tests depend on the live network (timeouts up to 180 s) and are skipped unless `SCREENSHOT_DIR` is set. That's right for CI, but they only run when someone captures by hand. | `AppStoreScreenshotTests.swift:38-40, 78-91` |

CI notes:

- The subset in `ci.yml` covers `PushServiceTests` and `FavouriteAlertsTests` (both classes live in
  `PushServiceTests.swift`). The existing FOX-31 tests are deterministic: fakes answer
  synchronously and completion is checked on main.
- One shared-state risk: the tests post `FavouriteAlerts.changed` on `NotificationCenter.default`
  inside the host app, for station 126, which is also the registered default favourite. It's
  harmless today because nothing in the host app writes on that notification. If a future observer
  writes on it, these tests could end up calling OneSignal.
- CI picks the newest simulator named plainly "iPhone NN", so it never uses "iPhone 18 Pro". Fine.
- **Japanese pipeline:** not in this repo. The only reference is the DNS runbook in
  `docs/web-hosting.md` (`japanesedaily` → `kf-nihongo.web.app`). It needs its own review in that repo.

## Won't fix / defer

| Item | Why deferred | Ticket |
| --- | --- | --- |
| FCM cutover, replacing OneSignal | On hold. M5 (shared token) must be fixed before it. | FOX-13 |
| Welcome / onboarding: whether to ask for notification permission at first launch instead of in `AppDelegate:73` | On hold. It changes L2/M6 behaviour. | FOX-34 |
| Forecast tab | A separate feature; the details forecast card wasn't re-reviewed beyond its placement. | FOX-32 |
| Cleanup fixes for M1–M3, L3, L4 | Code changes; this ticket is findings only. | FOX-36 (do not start here) |
| Per-device Directus auth via a Worker (M5 long term) | Architecture work for the cutover. | file under FOX-13 |
| PRs #34 / #35 | On hold per instructions; not reviewed. | — |
| Legacy tag spelling `_therhold`, inverted `isDndStartEarlierThanEnd` | Server-side contract with OneSignal segments; renaming breaks existing devices. | won't fix |

## Mini LGTM blurb (ping-ready)

> **FOX-37 deep review: summary ready for LGTM (approving the review only, no code merge).**
> Master @ `2f07bf3`, findings in `docs/FOX-37-deep-review.md` on `feature/fox-37-deep-review` (not pushed).
> **3 High, all copy/assets, no code blockers:**
> (H1) privacy + landing still say favourites stay on the device; since FOX-31 the heart turns on an alert that goes to OneSignal/Directus.
> (H2) Terms/Privacy say "one-time purchase, no subscription", but the paywall sells auto-renewing plans and links to them. App Review risk.
> (H3) the FOX-29 station screenshots were taken before FOX-25 (no alerts card), so re-capture before upload.
> **6 Med:**
> (M1) Directus mirror doesn't wait for OneSignal success in unfavourite / switches / cancel-all.
> (M2) OneSignal tag read can hang or crash.
> (M3) alerts card shows the 2-station cap message and locked switches until OneSignal answers.
> (M4) unfavourite can leave alerts on with no local record.
> (M5) the shared Directus token can read/update all push rows; FOX-13 blocker.
> (M6) no offline state for the alerts card.
> **8 Low, 7 test gaps** (biggest: `FavouriteAlerts.clear`, DetailsViewModel FOX-31 steps, Favourites remove).
> Full `TWAQITests` not run (no Pods in the review worktree). Everything is from reading code and files. M5 needs a check of the Directus role.
> Proposed next: copy fix for H1+H2 (en/zh-Hant), re-capture for H3, file M1–M6 under FOX-36 / FOX-13. Nothing merged; FOX-34/13, #34/#35 untouched.


---

## Self-review (executor pass, same tip)

Independent read of the same `master` tip (`2f07bf3` / `cb7d78c`) against Claude’s draft. **H3 confirmed visually** on `fastlane/screenshots_raw/en-US/iPhone 02 station.png`: header → AQI scale → Live camera → Pollutants — **no alerts card** (pre–FOX-25 IA). H1/H2 privacy/terms strings verified with `rg` on `web/`.

**Severity adjust (for Mini):** keep H1–H3 as High (copy/assets / App Review). **Also treat M2 as High for code** (H4 / elevated): `OneSignalManager.getOneSignalSettings` nil-tags / bad-cast `return` never calls `completionHandler`, and `Double(value)!` can crash — now on every FOX-31 favourite path and on every station page open. Prefer fixing under FOX-36 before more IA work.

**Extra Low (not in draft):** `SettingsRowViewModel` sets `isDisabled` from `settings.stationSettings.count` (`SettingsRowViewModel.swift:81`) while FOX-31 / `FavouriteAlerts` count with `!StationAlerts(...).isOff`. Harmless if off stations are deleted from tags; **wrong if orphan off entries remain** (cap UI locks early). Prefer filter for consistency (tiny same-PR win later).

**#34 overlap:** open PR #34 (`feature/fox-35-privacy-pro-terms`) already targets terms/privacy subscription copy — likely **H2** (and maybe parts of H1). **Still hold merge** per brief; use it as the vehicle after Mini LGTM of this review, after adding FOX-31 favourite→alert language if missing.

**No code changes made.** No merges. FOX-36 not started. #34/#35 and FOX-34/13 held.

**Counts after self-review:** High 3 (+1 elevated code: M2→H4) / Med 5 remaining (M1, M3–M6) / Low 8+1 / Test gaps 7. **Blockers for Mini LGTM of the review summary: none.** Blockers for shipping 3.1.4 / ASC: H1–H3 (and preferably H4/M2).
