# App Store listing — v3.0.0 draft for review

**Nothing here has been uploaded.** These are draft `.txt` files in `deliver`'s
directory layout so they are drop-in later. No App Store Connect credentials were
used or requested; `deliver download_metadata` was never run.

Files written:

```
fastlane/metadata/en-US/{name,subtitle,keywords,description,promotional_text,release_notes}.txt
fastlane/metadata/zh-Hant/{name,subtitle,keywords,description,promotional_text,release_notes}.txt
```

Every field was measured programmatically. All pass.

| Locale | Field | Chars | Limit |
|---|---|---:|---:|
| en-US | name | 23 | 30 |
| en-US | subtitle | 29 | 30 |
| en-US | keywords | 98 | 100 |
| en-US | promotional_text | 143 | 170 |
| en-US | description | 2515 | 4000 |
| en-US | release_notes | 1541 | 4000 |
| zh-Hant | name | 21 | 30 |
| zh-Hant | subtitle | 18 | 30 |
| zh-Hant | keywords | 92 | 100 |
| zh-Hant | promotional_text | 67 | 170 |
| zh-Hant | description | 916 | 4000 |
| zh-Hant | release_notes | 545 | 4000 |

Keyword fields contain no spaces and no trailing comma (both waste characters).

---

## 1. The current live listing

**Observed live** on 2026-08-08 via the public iTunes Lookup API for
`com.kfpun.twaqi`, TW and US storefronts. This is what is on the store today.

| | |
|---|---|
| Live version | **2.0.8**, released **2021-11-28** |
| Ratings | **4.78 ★ / 10,804** (TW) · 4.76 ★ / 46 (US) |
| Categories | Weather (primary), Travel |
| Price | Free, with IAP |
| Min iOS shown | 13.0 |
| Store languages listed | EN, ZH, TH, ZH |

**Live name (zh-Hant / TW storefront)**

```
台灣空污即時預報 - 您查詢 PM2.5 的必備工具
```

**Live name (en-US)**

```
Taiwan Air, check PM2.5 easier
```

**Live subtitle:** not exposed by the Lookup API. Not observed. If a subtitle is
set today, I could not see it — check App Store Connect before overwriting.

**Live release notes (zh-Hant):** `- 修正錯誤並提升效能 / 我們很需要您給點意見，我們會越做越好。`

**Live description (zh-Hant), verbatim:**

> 我們提供所有您需要知道的空氣質量信息，包括每小時監測的空氣品質指標 AQI，以及臭氧 O3、細懸浮微粒 PM2.5、懸浮微粒 PM10、一氧化碳 CO、二氧化硫 SO2 及二氧化氮 NO2 六項污染物的濃度數值。
>
> - 可設定「AQI 指數通知」，一旦數值超標即刻警示，及時採取防空污措施。
> -「空氣品質預報通知」推播，輕鬆預覽每日空氣情報。
> - 提供未來 3 天空氣品質預報，提早安排戶外對策。
> - 特設「風向強度指標」功能，一目了然空污擴散的可能方向。
> - 不佔記憶空間、不吃資源，簡單又易懂。
>
> （…健康風險段落、AQI 定義段落、環保署資料來源、info@dllm.io）

**Live description (en-US), verbatim:**

> All of the air quality information you need to know in Taiwan.
> We provide realtime AQI as well as the pollutant concentration of NO2, O3, SO2, CO, PM10, and PM2.5.
> Also, we will also notify you while the air gets significantly worse.
> Enjoying the app? Leave us feedback and a rating to let us know! …info@dllm.io

### What is wrong with the live copy

1. **It advertises the forecast three times** — the app name itself says
   「即時**預報**」, and the description promises 「未來 3 天空氣品質預報」 and
   「空氣品質預報通知」推播. All three are false in 3.0.0. This is the single
   biggest reason the listing has to change, not just an ASO opportunity.
2. The zh-Hant name spends 12 of its 30 characters on 「您查詢 PM2.5 的必備工具」,
   which is marketing filler, not search surface.
3. It says 環保署. The agency was upgraded to **環境部** (Ministry of Environment)
   in August 2023. The in-app string was already updated; the store copy was not.
4. The en-US description is four sentences and mentions no differentiator at all.
5. It uses 空氣質量 (mainland usage) in the first line of the Traditional Chinese
   copy. Taiwan says 空氣品質.

---

## 2. Feature set — verified against the code, not assumed

Everything claimed in the new copy was checked in the working tree on branch
`develop` (`MARKETING_VERSION = 3.0.0`, `CURRENT_PROJECT_VERSION = 130`).

**Confirmed present:**

| Claim | Evidence |
|---|---|
| Live map, one marker per station, coloured by health band | `TWAQI/Views/Main/GoogleMapController.swift`, `Marker.swift` |
| Map switches between all 7 indices (AQI, PM2.5, PM10, O3, CO, SO2, NO2) | `Views/Main/IndexSelectorView.swift`, `Constants/AirIndexTypes.swift` |
| Wind mode — markers become arrows rotated to direction, scaled by speed | `Views/Main/WindModeButton.swift`, `GoogleMapController.swift` |
| Nearest-station card with value, status and last-updated time | `Views/Main/ClosestStationView.swift` |
| Auto-refresh, camera position persisted across launches | `GoogleMapController.swift` |
| Favourites with health guidance per card | `Views/Favourites/FavouriteListView.swift` |
| Search grouped by air-quality region, matches name / township / county | `Views/Details/DetailsListView.swift` — `groupedStations`, first-seen (≈N→S) order |
| Station detail: all six pollutants, wind, address, coordinates, station type, region, publish time + "n hours ago" | `Views/Details/StationHeaderView.swift`, `StationInfoView.swift` |
| Threshold push, above **and** below, max 2 stations | `Views/Details/SettingsRow.swift`, `Utils/OneSignalManager.swift` |
| Do Not Disturb window | `Views/Help/HelpView.swift`, `Models/OneSignalSettings.swift` |
| Ad-free non-consumable IAP | `Utils/IAPManager.swift` (`com.kfpun.twaqi.adfree`) |
| 4 languages: en, zh-Hant, zh-Hans, th | `TWAQI/Localization/*.lproj/Localizable.strings` |
| **NEW** 24-hour AQI trend with plain verdict | `Models/AqiTrend.swift` + `Views/Details/DetailsHistoryView.swift` |
| Data source is 環境部 open data | `Help.data_provided_by_government` string, `context/api/endpoints.md` |

**Confirmed removed** — forecast. There is no `Forecast*` view, no forecast tab in
`ContentView.swift` (4 tabs: Main, Favourites, Search, Help), and
`context/features/feature-inventory.md` records that the `aqfn` government endpoint
is dead with no replacement. **No forecast claim appears anywhere in the new copy.**

**The 3.0.0 trend feature, precisely.** `AqiTrend.from(values:)` compares the mean
of the 3 most recent hourly readings against the mean of 3 readings ~6 hours
earlier; a delta under 5 AQI points is reported as steady. The copy says
"compares averaged windows rather than single readings, so a one-hour spike will
not flip it" — that is literally what the code does, and it is the honest
differentiator against every competitor that just draws a line chart.

Also worth knowing: the history chart is now **AQI-only**. The old 7-pollutant
segmented picker was removed because it wrote to the *global* selected index and
silently re-scored every marker on the map. The new copy does not promise a
per-pollutant history chart.

---

## 3. Proposed copy and rationale

### en-US

| Field | Proposed |
|---|---|
| **name** | `Taiwan Air: AQI & PM2.5` |
| **subtitle** | `Live air quality map & alerts` |

*Rationale.* Keeps **Taiwan Air** — that brand equity is 10,804 ratings deep,
throwing it away would be vandalism. Drops the weak verb phrase "check PM2.5
easier" and spends the characters on the two terms people actually type: **AQI**
and **PM2.5**. Between name and subtitle the indexed surface is now
*Taiwan · Air · AQI · PM2.5 · Live · quality · map · alerts*, which covers
"taiwan air quality", "taiwan aqi", "air quality map", "air quality alerts" and
"pm2.5 taiwan" without a single wasted word.

**keywords** (98/100)

```
pollution,pm10,ozone,smog,haze,dust,particulate,monitor,index,station,asthma,mask,taipei,kaohsiung
```

No term here repeats anything in the name or subtitle — Apple already indexes
those, and duplicating them is the most common way to waste the field. No
competitor names. `index` completes "air quality index" from the subtitle's
words; `monitor` and `station` complete "air quality monitor / monitoring
station". `asthma` and `mask` are intent keywords — someone searching those is
looking for exactly this app. `taipei` and `kaohsiung` are the two highest-volume
city queries; `taichung` did not fit.

**promotional_text** (143/170) — leads with the one genuinely new thing. This
field can be changed *without submitting a build*, so it is the right place to put
the 3.0.0 hook and the right thing to swap out later for seasonal copy (dust
storm season, etc.).

**description** (2515/4000) — restructured so the first two lines, which are all
that show before "more", carry the value proposition and the 3.0.0 news. Then
headed blocks: map, station detail, alerts, daily use, why it matters, data
source. The health-risk paragraph is kept from the live zh copy because it works
— but the IARC claim is stated accurately (Group 1 carcinogen, 2013, *outdoor*
air pollution) rather than loosely.

**release_notes** (1541/4000) — explicitly and unapologetically explains the
forecast removal. Users will notice a whole tab is gone; the choice is between
telling them why or reading about it in one-star reviews. Also states the iOS 15
requirement, because iOS 13/14 users will simply stop receiving updates.

### zh-Hant

| Field | Proposed |
|---|---|
| **name** | `台灣空氣品質 - PM2.5 空污即時監測` |
| **subtitle** | `全台測站即時 AQI 地圖、超標提醒` |

*Rationale.* 「預報」 is gone — it has to be. The 21 characters now carry six
searchable terms: 台灣 · 空氣品質 · PM2.5 · 空污 · 即時 · 監測, versus the live
name's three. 「您查詢…的必備工具」 was pure filler.

**keywords** (92/100)

```
空汙,空氣汙染,空品,紫爆,霧霾,沙塵,懸浮微粒,細懸浮微粒,臭氧,PM10,環境部,環保署,氣喘,過敏,口罩,清淨機,戶外,運動,跑步,兒童,長者,台北,台中,高雄,天氣,健康,呼吸
```

Deliberate choices:
- **空汙 with 汙** — the name uses 污. Both glyphs are in everyday Taiwanese use
  and Apple does not treat them as the same token. Covering both is cheap.
- **紫爆** — Taiwan-only slang for a hazardous-band reading. High intent, and
  nobody outside this market would think to bid on it.
- **環保署 and 環境部** — the agency renamed in 2023 but a large share of users
  still search the old name.
- **細懸浮微粒 and 懸浮微粒** kept separately; the longer official term for PM2.5
  will not necessarily be matched by the shorter one.
- 清淨機 / 口罩 / 氣喘 / 兒童 / 長者 are the purchase-intent terms — the moments
  when someone actually reaches for this kind of app.

**description / release_notes** — Taiwan-idiomatic throughout: 空氣品質 not
空氣質量, 測站 not 监测点, 推播 not 推送, 最愛 not 收藏, 環境部 not 環保署,
全形 punctuation and 「」 quotes. The wording matches the in-app strings, which
were themselves written to 環境部 conventions (see the header comment in
`zh-Hant.lproj/Localizable.strings`).

---

## 4. Open questions — things you need to decide

### ✅ 1. The Apple Watch app has been removed (resolved)

Both watch targets, their sources, schemes and the `watch Extension` Podfile
target are gone from the project as of v3.0.0. The description never claimed a
Watch app, so no copy needs changing.

The one thing that is *not* metadata: the live listing shows Watch support
(`supportedDevices` contains `Watch4-Watch4`) because the shipped 2.0.8 binary
embeds a watch app. That flag is derived from the binary, not from anything
editable — it clears itself once a build without the watch app is released.
Nothing to remove by hand.

Existing watch users keep the complication only until they update; on updating
to 3.0.0 it disappears. That is the intended outcome, but it is the one
user-visible loss in this release and is worth a release-note line if you want
to be explicit about it.

### 🟠 2. Changing the app name costs you existing search ranking

`台灣空污即時預報` has been the name for years and accumulated whatever ranking
10,804 ratings buys. Removing 預報 is *necessary* (the feature is gone), but if
you want to minimise disruption, a conservative alternative is a one-word swap:

```
台灣空污即時查詢 - PM2.5 空氣品質      (18 chars)
```

That keeps 台灣空污即時 intact and only replaces 預報→查詢. It is weaker on
search surface than my proposal but safer on continuity. **Your call.** I went
with the stronger version because 空氣品質 front-loaded is the highest-volume
query in this category.

### 🟠 3. The exact station count is unverified

You asked me to confirm "~84 stations". I could not verify it: the app gets the
list from your own backend, whose domain lives in a gitignored xcconfig, and the
government open-data endpoint did not return usable JSON when I tried it. The
only numbers in the repo are stale and both belong to *unused* code —
`TaiwanStationMapper` has 77 entries, the dead bundled `stations.json` has 82.

**I therefore put no station count anywhere in the copy** ("every official
monitoring station" / 「所有官方監測站」). If you can confirm the live number,
adding "84 stations" to the subtitle or first description line would be a
credibility win. Do not ship a number neither of us has checked.

### 🟡 4. Is there a subtitle set today?

The Lookup API does not return subtitles, so I could not see whether one exists.
If a subtitle is live today, uploading `subtitle.txt` will overwrite it. Worth a
glance at App Store Connect first.

### 🟡 5. No zh-Hant screenshots exist

`fastlane/screenshots/` contains **only `en-US/`** (2 iPhone 6.9", 2 iPad 13"),
and their banner copy is English: "Every station. One map." / "Know before you go
out." Taiwan is your primary market by a factor of ~235 on rating count, and it
will be shown English marketing banners over a Chinese UI. The `TITLES` hash in
`fastlane/Fastfile` is where that copy lives if you want a zh-Hant set. Suggested
zh-Hant banner copy:

- 「全台測站，一張地圖。」/ 「即時 AQI，一眼看完。」
- 「出門前，先看一眼。」/ 「AQI、六項污染物與健康建議。」

### 🟡 6. A date-formatting bug is visible in the current screenshots

Not a metadata issue, but you will ship these images: the station detail capture
in `screens/` renders last-updated as **「最後更新 佛曆 2569年8月8日 03:00」** —
the Buddhist calendar. Presumably a `SwiftDate`/locale calendar leak. It is
legible in the App Store screenshot at full size. Worth fixing before you
re-capture.

### 🟡 7. Claims I softened deliberately

- **"Readings refresh automatically"** — the timer is every 15 minutes. I did not
  state the interval, because the underlying government data is hourly and
  quoting "every 15 minutes" invites a "your data is an hour old" complaint.
- **"A single in-app purchase removes every ad, permanently"** — true in intent,
  but `context/decisions/known-issues.md` notes there is **no receipt validation**
  and the entitlement is a plain `UserDefaults` bool, lost on reinstall until the
  user taps "Restore purchase". "Permanently" is defensible since Restore works,
  but if you want zero exposure, change it to "removes every ad".
- I did not claim multi-country support (the map does lazily load other countries)
  because the listing, the name and the keywords are all Taiwan-focused. Adding it
  would dilute the positioning for a feature almost nobody in this market uses.

### 🟡 8. Not drafted: zh-Hans and th

The app ships four languages. I drafted the two you asked for. If you want the
Simplified Chinese and Thai storefront listings too, say so — note that zh-Hans
must not be a character-conversion of zh-Hant (空氣品質→空气质量, 測站→监测站,
最愛→收藏, and 紫爆 means nothing outside Taiwan).

---

## 5. How to use these files later

They are already in `deliver`'s layout, so a future upload is just
`deliver` with `skip_binary_upload` — but note `fastlane/Fastfile`'s existing
`upload_screenshots` lane sets `skip_metadata: true`, so it will **not** pick
these up as written. Uploading metadata is a separate, deliberate act and
requires App Store Connect credentials that are not currently configured.
