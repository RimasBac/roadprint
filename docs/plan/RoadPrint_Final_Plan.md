# RoadPrint: Final Plan

- **Date:** 2026-11-06
- **Status:** final draft. This replaces `product_plan_v4.md` and all earlier plan and brief versions.
- **Goal:** publish a first app and learn the whole process (design → build → App Store → subscriptions → launch). Revenue is a bonus.
- **Mockups:** `mockups/1-trip-summary.png` · `mockups/2-share-cards.png` · `mockups/3-heatmap-free-vs-pro.png`

---

## 1. The app in one paragraph

**RoadPrint** is an iPhone app that lets truck drivers **anywhere in the world** record trips **like Strava**. Tap **Start Trip** before rolling and **End Trip** after parking. Each trip becomes a summary screen with the route, elevation, countries and regions, and badges, plus a share card for TikTok or Instagram. Over time, the driver's trips build a **heatmap of every road they've driven**. Every trip is saved forever, for free. The free version **shows** the last 30 days; **Pro** unlocks the all-time map with filters. Trips sync through the driver's own **iCloud**, so a new phone restores everything. No server, no ads, no employer access.

**Name:** RoadPrint (App Store: "RoadPrint: Trucker Heatmap")

**Tagline:** "Your miles. Your map. Your million."

---

## 2. How we got here

### 2.1 Research
- **The user:** about 3.5M US truck drivers (and millions more worldwide). Long-haul drivers are away for weeks, live in the truck, and spend hours a day on their phones while off duty. Holding a phone while driving a truck is banned in the US and most countries, so the app can only be used while parked.
- **Pain points found:** parking, unpaid detention time, routing, health, loneliness, paperwork, broker fraud.
- **What works for simple apps** (from Starter Story case studies: Early, Cat on Chair, ONCE and others): a familiar app with one twist, a demo you get in 3 seconds, marketing from day one, tiny teams, $20–40/year pricing.
- **Why Strava works:** it makes invisible effort visible, and adds recognition, identity, legends, progress and shareable outputs. Everything that spreads the app is free; deeper value is paid.
- **The insight:** trucking work is invisible and thankless, but drivers have a strong pride culture (million-mile awards, odometer posts). **A Strava for truckers didn't exist.** The closest is Driver Tracer, a general driving app with little traction.

### 2.2 Ideas considered and dropped
| Idea | Why it was dropped |
|---|---|
| Detention-time clock | Already crowded (Detention Source, DMRG, WaitClaim, Trucker Tools). The real problem is getting paid, not timing the wait |
| Per diem and fuel-tax exports | W-2 company drivers can't deduct per diem. Fuel tax is handled by the carrier or the ELD. Cheap apps exist. Liability risk |
| Ads before sharing | ~1.5¢ per ad view, which would mean hobby money, and it would slow sharing (the free marketing) |
| Carrier or recruiter revenue | Contradicts the "never shared with employers" trust promise |
| Year-end "Trucker Wrapped" and a web Career Card | Founder's choice: dropped |
| Automatic trip detection and always-on location | Battery, privacy, App Review and car-vs-truck problems. **Replaced by manual Start/End** |
| Launching iPhone and Android together | Too much for 1–2 people. **iPhone first** |

### 2.3 Three Elephant-Goldfish reviews
Using Google's Elephant-Goldfish Model, independent reviewers with fresh context (different lenses, then different models: Opus, Sonnet, Haiku) attacked each version of the plan.

**What changed because of them:**
- Career miles are entered at sign-up, so the million-mile bar doesn't start at zero
- Tax features and carrier revenue removed
- Manual Start/End instead of always-on tracking (removes the "Always" permission, car-vs-truck confusion and team double-counting)
- No notifications or interaction while driving; badges appear only after End Trip
- Privacy rules: trim the start and end of each trip, no speed stored, data on the phone and encrypted, "hide route" on cards
- Removed fallbacks that iOS can't support (auto-end, "parked" reminders, an 8-hour+ Live Activity)
- Realistic timeline (14–20 weeks) and an honest view of the economics

**What the reviews still warn about** (accepted, because the goal is learning): a small market, drivers forgetting to tap Start, the map not changing much for drivers on repeat lanes, and copycats.

---

## 3. Decisions log (final)

| Topic | Decision |
|---|---|
| Platform | **iPhone first** (Swift/SwiftUI). Android maybe later |
| Tracking | **Manual Start Trip / End Trip only** |
| Geography | **Built for the whole world from day one; listed worldwide** (English first). Beta and marketing focus on **one region** (open decision, §13) |
| Units | **km or miles**, set by the phone's region and switchable |
| Monetization | **Subscription only:** $4.99/month or $39.99/year with a 7-day trial |
| Free tier | Unlimited recording **and storage forever**; *viewing* is limited to the last 30 days |
| Pro | All-time heatmap, filters, full history, all card styles, no watermark, HD export |
| Storage | **On-device database + iCloud sync (CloudKit) on by default**, sensitive fields encrypted, Export/Import as files. **No own server in v1** |
| Social | **None in v1** (no feed, follows or leaderboards). Built to be social-ready (AGENTS.md §7b). Revisit after the beta using the §12 engagement numbers: trips per driver per week and churn (board, ROA-6) |
| 3D terrain | **A 3D elevation card style** (Pro), rendered on the phone from bundled elevation data (board, ROA-6) |
| Ads / carriers / tax / recap | **None** |
| Name | **RoadPrint** (renamed from the working title "Million Miles"; "million miles" stays as the tagline and milestone) |
| Main effort | **Route visualization** |

---

## 4. Features: version 1

### 4.1 Onboarding (3 screens)
1. Career distance (self-reported; km or miles) and years driving
2. Tap the countries and regions you've already driven (they fill in as "previously driven")
3. Location permission ("While Using") with a plain-language explanation. iCloud sync is on, with a one-line privacy note

### 4.2 Recording
- **Start Trip:** one big button. Opens the app and starts recording (iOS needs the app open to start a location session).
- **While recording:** only "Recording · tap End when parked." No live stats, no alerts, no Live Activity in v1.
- **End Trip:** one tap, then the trip summary.
- **Forgot to tap End:** on next open, "This trip includes a 9-hour stop. End it there?"
- **iOS stopped the app mid-trip:** the gap is detected on next open. The trip is marked "partially recorded," with the gap drawn dotted.
- **In-app rule, shown in onboarding and settings:** "Start before rolling. End after parking. Never use your phone while driving."

### 4.3 Trip summary (mockup 1)
- **The route map:**
  - privacy trim: the first and last ~8 km / 5 mi aren't stored, and start and end show as approximate circles
  - countries and regions crossed are labeled
  - the highest point is marked
- **The stats row:** distance, moving time, countries and regions, and the main road shown as a **local-style road sign** (US interstate shield, green European E-road sign, Australian route marker and so on).
- **An elevation profile** with the summit labeled.
- **Below the stats:** new badges, the career counter with progress toward 1,000,000, and a **Share trip card** button.

### 4.4 Share cards (mockup 2)
- 9:16 at 1080×1920 for Stories and TikTok. **4 styles:** Night Highway (free), Road Atlas, Poster and Terrain (Pro). Terrain is a 3D relief of the land around the route, with the route drawn as a glowing ribbon at its recorded altitude and the summit labeled.
- **Update (board, 2026-11-10):** there are now **5 styles**: Night Highway and Print (a transparent overlay for the driver's own photo) are free; Road Atlas, Poster and Terrain are Pro. See [docs/design/DESIGN_PLAN.md](../design/DESIGN_PLAN.md) §3.3.
- Free cards carry a small "Made with RoadPrint" watermark; Pro removes it.
- A **"Hide route on card"** toggle shows only places and stats.

### 4.5 My Map: the heatmap (mockup 3)
- **Free:** last 30 days. **Pro:** all time.
- **Pro filters:** year or date range, country, region/state, road, legendary roads. Tap a road to see how many times and when.
- **Heat levels:** brighter, thicker lines = driven more often. Five levels: 1–2, 3–5, 6–9, 10–14, 15+.
- **Below the map:** stats (distance, countries, regions, trips, legendary roads) and top lanes.

### 4.6 Badges and milestones
- **Places:** countries (about 200), plus states, provinces and regions within them.
- **Legendary roads (starter list, about 30, grows over time):**
  - **USA:** Donner Pass, Cabbage Hill, the Grapevine, Monteagle, Eisenhower Tunnel, Tehachapi Pass, Vail Pass, Fancy Gap, Siskiyou Summit, Sherman Hill
  - **Canada:** Coquihalla Highway, Rogers Pass, Kicking Horse Pass
  - **Europe:** Brenner Pass, Gotthard Road Tunnel, Mont Blanc Tunnel, Fréjus Tunnel, Arlberg, E6 to Nordkapp, Øresund Bridge
  - **Australia:** Nullarbor and the 90 Mile Straight (Eyre Highway), Stuart Highway, Pacific Highway
  - **Africa:** N1 South Africa, Sir Lowry's Pass
  - **Asia:** Karakoram Highway
- **Milestones:** 100K, 250K, 500K, 750K, **1,000,000 miles** *and* **1,000,000 km** (each user sees their own unit, and both can be earned).
- **Repeatable goals:** a yearly distance goal and "new countries/regions this year."
- Badges appear **only after End Trip**.

### 4.7 Settings
Units (km/mi) · iCloud sync on/off · **Export all trips** (GPX/JSON) · **Import trips** · Delete all data · Restore purchases · Manage subscription · Privacy policy · Map data attribution

### 4.8 Out of scope for v1
Social feed, leaderboards, automatic detection, Live Activity, Android, Apple Watch, web dashboard, share links, physical prints, languages beyond English. Social features are designed for but not built (AGENTS.md §7b).

---

## 5. Visualization: the main effort

### 5.1 Visual style (as in the mockups)
- **Dark theme by default:**
  - background `#14161c`, land `#1d2029`, borders `#30353f`
  - route amber `#ffb547` with a soft glow
  - text `#f0efec`, secondary text `#a6aab4`
- **Heatmap ramp (one hue, dim → bright):** `#8a4a12 → #c2650f → #f08c1a → #ffb547 → #ffe1a0`. Validated: brightness rises evenly, and the dimmest step is still visible on the dark background.
- **Two themes (board, 2026-11-10):** the app has a night theme (the default, above) and a day theme on warm paper with the same amber family; the paired colours are in [docs/design/DESIGN_PLAN.md](../design/DESIGN_PLAN.md).
- **Fonts:** Inter for text, Barlow Condensed for big numbers.
- **Road signs:** a small set of SVG templates for each region, filled in with the road number.

### 5.2 Rendering, in two layers
| Where | Technique | Why |
|---|---|---|
| Share cards, heatmap overview | **Custom-drawn map** using bundled **world country and region outlines** (Natural Earth, public domain), drawn with SwiftUI Canvas | The mockup look, works offline, renders identically on every phone, quick to export |
| Terrain card | 3D relief from a bundled elevation grid, drawn on the phone (technique decided by the CTO spike) | Works offline, and the route never leaves the phone. |
| Zoomable detail | **MapKit** with a dark map style and custom route and heat overlays | Free, native, real streets worldwide |

### 5.3 Map projection
Each map view uses a projection fitted to the data:
- **a single trip:** zoomed to the route
- **the heatmap:** zoomed to the driver's area (a whole continent or the world)
- **the US:** an Albers-style projection
- **Europe:** a Lambert/LAEA-style projection
- **global views:** Natural Earth or Robinson projection

### 5.4 Data pipeline (all on the phone)
1. **Record:** a location fix about every 100 m, plus altitude (GPS combined with the barometer).
2. **Clean:** drop GPS jumps and fill tunnel gaps in between known points.
3. **Simplify:** reduce the route to its key points (Douglas–Peucker, 10–30 m tolerance), about 10x smaller.
4. **Trim:** remove the first and last ~8 km / 5 mi.
5. **Enrich:**
   - **countries and regions:** check which one each point falls in, using the bundled outlines
   - **road names:** match points to a bundled simplified major-road network (Natural Earth roads; OSM later, with attribution)
   - **legendary roads:** a badge when the trip passes both the entry and exit zones
   - **elevation:** from the phone's own sensors. No online elevation API, so the route never leaves the phone. The Terrain card also uses a bundled coarse elevation grid (DEM) for the land around the route. It is never fetched per trip from an online API.
6. **Heat index:** a grid of small cells (~1 km geohash). Count trips per cell; filters recount for the selected trips. **The index is rebuilt from the stored trips on each phone and never synced.**
7. **Store:** SwiftData. Simplified trips are kept, and raw points deleted after processing.

### 5.5 Visualization milestones
1. A hard-coded route (I-80 mockup data) drawn on the custom map
2. Elevation chart (Swift Charts)
3. Trip summary screen matching mockup 1
4. Three card styles matching mockup 2, exported at 1080×1920

4b. Terrain (3D relief) card for the I-80 and Brenner test routes, exported at 1080×1920.

5. Heatmap from 30+ sample trips with filters, matching mockup 3
6. **A Europe test** (for example Kaunas → Munich → Brenner → Verona) and an **Australia test** (Perth → Adelaide across the Nullarbor) to check projections, labels and road signs
7. A MapKit zoom view with heat lines
8. Performance: the heatmap for 1,000 trips renders in under 1 second

---

## 6. Data storage and sync (no server)

| Question | Answer |
|---|---|
| Where are trips stored? | On the phone (SwiftData), encrypted by iOS Data Protection |
| New phone? | **iCloud sync (CloudKit private database) is on by default.** Same Apple ID → everything restores automatically. No login screen |
| Who can read it? | Only the user. Data lives in **their** iCloud. Sensitive fields (route geometry) use `allowsCloudEncryption`, which Apple describes as end-to-end encrypted; verify during the build. **You never hold anyone's location data** |
| Cost? | **Free to you.** It uses the user's iCloud storage, and a year of trips is only a few MB |
| Free user who subscribes in month 3? | Every trip is already stored, so the all-time map appears instantly. Upgrade message: *"You've recorded 92 trips and 22,800 km. See them all with Pro."* |
| Subscription on a new phone? | Tied to the Apple ID. Restore purchases |
| Lost Apple ID, or switching to Android? | **Export all trips** (GPX/JSON) and **Import** |
| When would you need your own server? | iPhone ↔ Android sync, a web dashboard, share links, social features. That's v2 or later (Supabase or Firebase), which brings accounts, privacy-law duties and costs |

**Tests before launch:** delete and reinstall · restore onto a second iPhone · iCloud turned off · iCloud storage full · export, then import on a fresh install.

---

## 7. Global readiness

| Area | v1 approach |
|---|---|
| Map data | Natural Earth country and region outlines plus major roads, bundled (a few MB) |
| Units | km or mi by phone region, switchable; both million-milestones |
| Language | **English at launch.** Every string goes in a translation catalog from day one; add languages later based on where users come from |
| Dates and numbers | Formatted for the phone's region (11/04 vs 04.11; 1,000 vs 1.000) |
| Road signs | Per-region templates (US, Canada, EU/E-roads, UK, Australia; a generic sign elsewhere) |
| Pricing | Apple localizes $4.99 / $39.99 automatically in 175 storefronts |
| Privacy law | On-device data plus the user's own iCloud keeps GDPR and other privacy laws simple. The privacy policy covers the EU, UK and elsewhere |
| Phone-use laws | Handheld use while driving is banned in nearly every country; the same in-app rule applies |
| Availability | Listed in all App Store countries |

---

## 8. Pricing

| Plan | Price |
|---|---|
| **Monthly** | **$4.99** |
| **Yearly** | **$39.99** (about 33% off monthly, marked "Best value") with a **7-day free trial** |
| Free | $0: unlimited recording and storage, 30-day heatmap, trip summary, badges, career counter, Night Highway card with watermark |

- **The paywall appears** when the driver taps "All time" or a filter, and after their 3rd trip. Never on first launch.
- **Later experiment:** $49.99/year.
- **Implementation:** StoreKit 2 + RevenueCat (free under $2.5K/month in revenue).

---

## 9. Tech stack

| Area | Choice |
|---|---|
| Language and UI | Swift, SwiftUI |
| Location | Core Location: "While Using" permission and background location mode during a trip |
| Altitude | Core Location + `CMAltimeter` |
| Maps | SwiftUI Canvas (custom map) + MapKit (zoom) |
| Charts | Swift Charts |
| Storage and sync | SwiftData + CloudKit (iCloud), with `allowsCloudEncryption` on the route fields |
| Purchases | StoreKit 2 + RevenueCat |
| Crash reports | Xcode Organizer (free) or Sentry free tier |
| Bundled data | Natural Earth: countries, regions, roads (public domain); about 30 legendary-road zones (hand-drawn); a coarse global elevation grid (source and size decided by the CTO spike, public domain or attribution-only licence) |
| Needed | A Mac with Xcode, an **Apple Developer account ($99/year)**, an iPhone, car test drives at first |

---

## 10. Build plan (solo, learning pace)

| Weeks | Milestone |
|---|---|
| 1–2 | SwiftUI basics; Start/End recording in a car; save trips |
| 3–4 | Data pipeline: clean, simplify, trim, countries and regions; km/mi |
| 5–7 | **Visualization:** custom world map, trip summary, elevation |
| 8–9 | **Share cards** (4 styles) and **heatmap**, plus Europe and Australia test routes |
| 10 | **iCloud sync, Export/Import**, restore tests |
| 11 | Pro: all-time map, filters, paywall, subscriptions |
| 12 | Badges, career counter, onboarding, settings, data wipe |
| 13 | **TestFlight** with 5–10 drivers in the launch region |
| 14 | Fixes, App Store screenshots (from the mockups), privacy policy, submission |
| 15 | **Launch** |

Realistically this takes 15–20 weeks for a first app, and that's fine.

---

## 11. App Store and legal checklist
- [ ] Privacy policy page: location stays on the device and in the user's own iCloud; no tracking, no selling; GDPR wording
- [ ] App Store privacy label: precise location, not linked to the user, not used for tracking
- [ ] Location permission text: "RoadPrint records your route only between Start Trip and End Trip."
- [ ] Background location explained in the App Review notes, with a screen recording
- [ ] iCloud/CloudKit container set up; sync and restore tested
- [ ] Subscription terms, restore purchases, a manage-subscription link
- [ ] The "never use your phone while driving" rule shown in onboarding
- [ ] Map data attribution (Natural Earth; OSM if used)
- [ ] Optional: a one-time review by a transport-law attorney before scaling

---

## 12. Launch
1. **Pick the launch region** (§13). Recruit beta drivers there: local trucker Facebook groups, Reddit (r/Truckers, r/Truckers_EU-style groups), one truck-stop visit.
2. **App Store page:** the three mockups as screenshots, plus the tagline.
3. **Content:** your own TikTok and Reels using real beta share cards (with permission). Give free Pro to 5 trucker creators in the launch region.
4. **Measure and learn:**
   - downloads
   - trips per driver per week
   - forgotten-Start rate
   - trial starts, conversion and churn
   - top countries

   These are the lessons for app #2.

---

## 13. Open decisions
1. **Launch region:** wherever you can personally reach drivers for the beta.
   - **US:** biggest market, strong creator scene
   - **Europe:** the country-collecting hook is strongest there, but there are many languages
   - **Australia:** English, very visual roads, small market
2. **Name: decided, RoadPrint.** It works with km or miles, it's global, and it describes the heatmap ("your print of every road"). App Store listing: "RoadPrint: Trucker Heatmap", subtitle "Log trips · Million-mile club". Before committing: reserve the name in App Store Connect, run trademark searches (USPTO, EUIPO), and check the domain (roadprint.app / getroadprint.com) and @roadprint handles.
3. **Second language,** after launch, based on where users come from.
4. **Elevation data for the Terrain card:** source, resolution and app-size budget, decided by the CTO.

---

## 14. Known risks (accepted)
- **Drivers forget to tap Start** (the biggest manual-tracking risk). Mitigated by "previously driven" places and the career counter.
- **iOS stops recording mid-trip.** The gap is detected and shown honestly; tested on 11-hour drives.
- **The map stops changing** for drivers on repeat lanes. Brighter heat over time and repeatable goals help.
- **Copycats** (Driver Tracer, Trucker Path, ELD makers). Accepted; ship and learn.
- **Small niche, modest revenue.** Accepted; the goal is learning.

---

## 15. Definition of done
**The app is live on the App Store.** Real drivers in at least one region have recorded real trips. At least one person has paid for Pro. A trip restores correctly on a new iPhone. You know how to do it all again, faster, for app #2.

---

## Appendix A: files from this project
| File | What it is |
|---|---|
| `RoadPrint_Final_Plan.md` | **This document (current)** |
| `mockups/1-trip-summary.png` | Trip summary screen (real I-80 route and elevation) |
| `mockups/2-share-cards.png` | Night Highway, Road Atlas and Poster card styles |
| `mockups/3-heatmap-free-vs-pro.png` | Free 30-day map, Pro all-time map, Pro filtered |
| `product_plan_v4.md`, `product_plan_v3.md`, `product_plan.md`, `concepts_brief.md` | Earlier versions (replaced by this document) |
| `goldfish_review_report.md`, `goldfish_review_v2.md`, `goldfish_review_v3.md` | The three Elephant-Goldfish reviews |

## Appendix B: key sources
- Starter Story case studies: https://www.starterstory.com/stories/this-insanely-simple-app-makes-50k-month · https://www.starterstory.com/stories/i-make-13k-month-from-this-simple-app
- Google Elephant-Goldfish Model: https://github.com/google/elephant-goldfish-model
- Strava free vs paid: https://biketips.com/strava-free-vs-paid/
- Driver Tracer (closest competitor): https://apps.apple.com/app/driver-tracer/id6757180995
- RevenueCat State of Subscription Apps 2026: https://www.revenuecat.com/state-of-subscription-apps-2026/
- Apple, Live Activities limits: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- US phone-use rule for truck drivers (49 CFR 392.82): https://www.ecfr.gov/current/title-49/subtitle-B/chapter-III/subchapter-B/part-392/subpart-H/section-392.82
- Natural Earth (public-domain map data): https://www.naturalearthdata.com/
- Mockup data: OSRM routing (https://router.project-osrm.org) and Open-Meteo elevation (https://open-meteo.com)
