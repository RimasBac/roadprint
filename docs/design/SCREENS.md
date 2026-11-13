# RoadPrint screen and popup inventory

Status: board working list, 2026-11-10. It lists every page, sheet, alert and system prompt the app needs for v1, with the milestone that builds it. Source: plan §4 and §6, the mockups, and the [feel standard](/ROA/issues/ROA-20#document-app-feel). "Popup" here means anything that appears over a page: a sheet, an alert, a system prompt, a banner or a toast.

How to use it:
- When a milestone starts, the CTO checks its rows and makes sure each has an issue. A row without an issue is a gap, not an optional extra.
- Every page is built with its four states (loading, empty, error, content) and in both themes (feel standard §6 and §2a).
- Rows marked **Decide** need a board answer before they are built. They are collected in §6.

## 1. App structure (proposal)

Three tabs, the way Strava keeps a small fixed set:

| Tab | Holds | Why |
|---|---|---|
| **Drive** | Start Trip, the recording state, recent trips | The one action the driver came for is on the first screen |
| **Map** | The heatmap, filters, road detail | The long-term reward |
| **You** | Career counter, yearly goal, badges, all trips, Settings | Everything about the driver |

The trip summary, the share flow, onboarding and the paywall are not tabs: they are presented over the tabs.

## 2. Pages

| # | Page | What is on it | States that need their own design | Milestone | Issue |
|---|---|---|---|---|---|
| P1 | Launch screen | Background colour and the wordmark; no spinner | — | M3 | none yet |
| P2 | Onboarding 1: career | Career distance (km or mi) and years driving; skippable | empty input, invalid number | M7 | epic ROA-24 |
| P3 | Onboarding 2: places driven | Tap countries and regions already driven; search; skippable | none selected | M7 | ROA-24 |
| P4 | Onboarding 3: location and rules | Plain explanation, the "never while driving" rule, iCloud note, then the system prompt | permission denied | M7 | ROA-24 |
| P5 | Drive: ready | One large Start Trip button, last trip, career line | first run with no trips; location off; GPS not ready | M1 built, restyle in M3 | ROA-67 |
| P6 | Drive: recording | "Recording · tap End when parked", elapsed time, End Trip. No live stats, no map | GPS lost; recording resumed after the app was closed | M1 built, restyle in M3 | ROA-67 |
| P7 | Finishing trip | Shown only if processing takes over 300 ms | failure with "Try again" | M3 | ROA-56 |
| P8 | Trip summary | Map, stats row with road sign, elevation, badge (M7), career, Share and Done | no altitude; no main road; short trip without a route; partially recorded | M3 | ROA-56 (with ROA-54, ROA-55) |
| P9 | Trip detail | The same view opened from a list, with the date as title and a menu (share, delete) | — | M3 | ROA-56 |
| P10 | All trips | List by month: date, places, distance, road sign | empty; free plan shows 30 days with the rest locked | M3 (basic list exists), M6 for the lock | none yet |
| P11 | Map: heatmap | Custom map with heat lines; period switch (30 days / all time); stats and top lanes below | empty; free 30 days; Pro all time; filtered with no results | M4 | epic ROA-21 |
| P12 | Map: zoom view | MapKit with heat lines for street-level detail | no network for map tiles | M4 | ROA-21 |
| P13 | Badges | Grid by family: countries and regions, legendary roads, milestones, yearly goals; earned and not yet earned | nothing earned yet | M7 | ROA-24 |
| P14 | Badge detail | The badge, when and on which trip it was earned, a link to that trip | not earned (how to earn it) | M7 | ROA-24 |
| P15 | You | Career counter and progress to 1,000,000, yearly goal, badge strip, links to All trips and Settings | no career distance entered | M7 | ROA-24 |
| P16 | Settings | Units, appearance, iCloud sync, export, import, delete all data, restore purchases, manage subscription, privacy policy, credits, version | — | M7 | ROA-24 |
| P17 | Credits | Map data (Natural Earth, NOAA), fonts (Inter, Barlow Condensed), open-source notices | — | M7 | ROA-24 |
| P18 | Privacy policy and terms | Opens the hosted page in the in-app browser | offline | M9 | epic ROA-26 |
| P19 | Paywall | What Pro adds, monthly and yearly with the 7-day trial, Restore, terms links | products not loaded; purchase in progress | M6 | epic ROA-23 |

## 3. Sheets (ours)

| # | Sheet | Opens from | Notes | Milestone |
|---|---|---|---|---|
| S1 | Share card picker | "Share trip card" | Live preview, paging style picker, hide-route toggle, Share, Save to Photos, Copy | M4 |
| S2 | "Share cards arrive in the next build" | Share button before M4 ships | One sentence and OK; removed in M4 | M3 |
| S3 | Map filters | Filter button on the Map (Pro) | Date range, country, region, road, legendary roads; "Clear all" | M6 |
| S4 | Road detail | Tapping a road on the Map (Pro) | Times driven, list of dates, links to those trips | M6 |
| S5 | Forgot to end | Opening the app with a trip still recording and a long stop in it | "This trip includes a 9-hour stop. End it there?" with "End at the stop" and "Keep recording" | M3 (core: ROA-66) |
| S6 | Recording was interrupted | Opening the app after iOS stopped it mid-trip | Says the trip is partially recorded; "Continue trip" or "End trip here" | M3 (core: ROA-66) |
| S7 | Milestone reached | After End Trip when a career milestone is crossed | One calm full-height moment, then the normal summary | M7 |
| S8 | Edit career distance | You, Settings | The same input as onboarding 1 | M7 |
| S9 | Edit places driven | You, Settings | The same picker as onboarding 2 | M7 |
| S10 | Import preview | Settings → Import, after a file is chosen | "42 trips found, 3 already here"; Import or Cancel | M5 |
| S11 | Upgrade message | "All time" or a filter on the free plan; after the 3rd trip | "You've recorded 92 trips and 22,800 km. See them all with Pro." Leads to the paywall. Never on first launch | M6 |
| S12 | What's new | First open after an update that changes something visible | Optional; three lines at most | later |

## 4. Alerts and confirmations (ours)

| # | Alert | When | Buttons | Milestone | Issue |
|---|---|---|---|---|---|
| A1 | Location is off for RoadPrint | Start Trip with permission denied or restricted | Open Settings · Not now | M3 | ROA-67 |
| A2 | Precise location is off | Start Trip with approximate location only | Open Settings · Start anyway | M3 | ROA-67 |
| A3 | Waiting for GPS | No fix 15 s after Start | (inline state on P6, not a blocking alert) | M3 | ROA-67 |
| A4 | Delete this trip? | Trip detail menu, swipe in a list | Delete (destructive) · Cancel. Says it is also removed from iCloud | M3 | — |
| A5 | Trip too short to draw | End Trip when nothing is left after the privacy trim | OK. The trip's distance still counts (**Decide**, §6) | M3 | — |
| A6 | We couldn't finish this trip | Processing failed | Try again · Done. The recording is kept | M3 | — |
| A7 | Turn off iCloud sync? | Settings toggle | Turn off · Cancel. "Trips will stay only on this phone." | M5 | — |
| A8 | iCloud is not available | Not signed in to iCloud, or iCloud Drive off for the app | (banner on You and Settings) Open Settings | M5 | — |
| A9 | iCloud storage is full | Sync fails for quota | (banner) "Your trips are safe on this phone." | M5 | — |
| A10 | Export failed / Import failed | File could not be written, read, or is from a newer app version | OK, with the reason in plain words | M5 | — |
| A11 | Delete all data? | Settings | Two steps: a confirmation, then typing DELETE. Says it removes trips from this phone and iCloud and cannot be undone | M7 | — |
| A12 | Purchase result | After buying or restoring | Success, cancelled (silent), failed (plain reason), nothing to restore | M6 | — |
| A13 | Photos access is off | Save to Photos after the permission was denied | Open Settings · Cancel | M4 | — |
| A14 | Not enough storage | Saving a trip or exporting fails for disk space | OK | M5 | — |
| A15 | Low Power Mode is on | Start Trip while Low Power Mode is on (**Decide**, §6) | Start anyway | later | — |

Toasts (short, no button): "Saved to Photos", "Copied", "Trip deleted" with Undo for 5 seconds.

## 5. System prompts we trigger

We do not design these, but each needs its wording in `Info.plist` or the String Catalog, the right moment, and a planned path when the answer is no.

| # | System prompt | When we trigger it | If refused |
|---|---|---|---|
| Y1 | Location "While Using the App" | End of onboarding 3, or the first Start Trip | A1 on the next Start Trip |
| Y2 | Motion & Fitness | First Start Trip, only if the barometer (`CMAltimeter`) is used | Altitude comes from GPS only; no error shown |
| Y3 | Add to Photos | First "Save to Photos" | A13 the next time |
| Y4 | App Store purchase sheet | Buying or starting the trial on the paywall | A12 |
| Y5 | Manage subscription sheet | Settings → Manage subscription | — |
| Y6 | Share sheet | Sharing a card; sharing an export file | — |
| Y7 | File picker | Settings → Import | — |
| Y8 | Background location indicator | The blue status-bar pill while recording in the background | Mention it in onboarding 3 so it does not alarm the driver |
| Y9 | "RoadPrint has been using your location" reminder | iOS shows it by itself after some days of background use | Mention it in the privacy text |

Not used in v1: notifications, tracking permission, contacts, camera, microphone, Bluetooth, Live Activities, widgets.

## 6. Decisions the board has to make

1. **Tabs:** is Drive / Map / You the right structure?
2. **Ending a trip:** the plan says one tap. A mistaken tap ends a 10-hour recording. Options: one tap plus "Undo" for 5 seconds (recommended), or press and hold.
3. **Short trips:** the privacy trim removes the first and last 8 km, so a trip under about 16 km has no route to draw. Recommended: save it, count its distance, show the summary without a map, and say why.
4. **Low Power Mode warning (A15):** warn at Start, or stay silent?
5. **App Store rating prompt:** ask after the 5th trip, or never in v1?
6. **Where the trip list lives:** recent trips on Drive and the full list under You (recommended), or a fourth tab.

### Board decisions, 2026-11-12

- **1. Tabs:** yes, with Drive and You now. The Map tab joins when the heatmap ships (M4). The tab bar is hidden while a trip is recording.
- **3. Short trips:** saved and counted. The trip screen shows the approximate area on the map, without a route line, and says why.
- **6. Trip list:** the last trip on Drive, the full list under You.
- A first trip screen (P9), All trips (P10), You (P15) with units and location access (part of P16) and Credits (P17) exist as of this date. ROA-56 restyles the trip screen to mockup 1.
- **2026-11-13:** the trip screen has the elevation chart (ROA-55, first version) and "Share trip card": the Night Highway card (1080 × 1920, built from `TripShareSummary`), a Show route switch and the system share sheet (S1, first version). Other card styles, Save to Photos and the road sign are still open.
- **2026-11-13, later (board, after trying build 10 on the phone):** the share sheet has a style picker with three cards drawn in `App/Share/ShareCard.swift`: Night Highway, Road Atlas and Poster. Each fills the card: an elevation strip under the numbers, and a signature with the app's mark ("Made with RoadPrint"). The "Show route" switch is gone: a card always shows the route. The Night Highway card follows the Designer's review in ROA-60.
- **2026-11-13, later:** a third tab, **Map** ("My map", plan §4.5, mockup 3), between Drive and You. `App/Home/MyMapView.swift` draws every trip on RoadPrint's own map with the five heat colours (core `HeatMap`: cells of about 1 km, a count per cell of the trips through it; levels 1–2, 3–5, 6–9, 10–14, 15+). Controls: Last 30 days or All time, and year, place and road filters taken from the trips; a legend and totals below. First version: the map is static (no pan or zoom, no tap on a road), there is no "Top lanes" list, and nothing is locked for Pro yet (M6).
- **Temporary:** You → Testing → "Add a test trip" builds a made-up drive between two cities and stores it like a recorded trip. Remove it before the public beta (`TestTripView`, `RecordingModel.addTestTrip`, `TestRoute`, `AreaNamer.place(named:)`).

## 7. What exists today (build 3)

Drive (ready and recording), a basic trip list with distance and regions, and trip processing on End. Everything else in this list is still to be built.
