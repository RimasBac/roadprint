# Million Miles: Full Product Plan (v4)

- **Date:** 2026-11-06
- **Goal:** publish a first app and learn the whole process (design, build, App Store, subscriptions, launch). Revenue is a bonus, not the goal.
- **Mockups:** `mockups/1-trip-summary.png`, `mockups/2-share-cards.png`, `mockups/3-heatmap-free-vs-pro.png`

---

## 1. The product in one paragraph

**Million Miles** is an iPhone app for US truck drivers that records trips **like Strava**. Tap **Start Trip** before rolling and **End Trip** after parking. Each trip becomes a summary screen with the route, elevation, states and badges, plus a share card for TikTok or Instagram. Over time, the driver's trips build a **heatmap of every highway they've driven**. The free version shows the last 30 days. **Pro** unlocks the all-time map with filters.

**Founder decisions (fixed):**
- iPhone first. Android later, maybe.
- **Manual Start/End only.** No automatic trip detection, no always-on location.
- Subscription only. No ads, no carrier or employer products, no tax features, no year-end recap.
- **The biggest effort goes into route visualization.**

---

## 2. Who it's for

US truck drivers, mostly long-haul (OTR), who are proud of their miles and spend off-duty time on their phones. Rules the design must respect:

- **No phone interaction while driving.** Federal rules ban holding a phone while driving a commercial truck, and reading a device counts as texting. Start before rolling, End after parking, nothing on screen in between.
- **Privacy first.** Drivers dislike being tracked by employers, and phone GPS can be subpoenaed after a crash. Data stays on the phone.

---

## 3. Features: version 1

### 3.1 Recording
- **Onboarding (3 screens):** career miles (self-reported), years driving, tap the states you've driven before (they fill in as "previously driven" on the map), location permission with a plain-English explanation.
- **Start Trip:** one big button on the home screen. Opens the app and starts recording (iOS requires the app to be open to begin a location session).
- **While recording:** the screen shows only "Recording · tap End when parked." No live stats, no notifications, no Live Activity in v1 (iOS ends those after 8 hours anyway).
- **End Trip:** one tap, then the trip summary screen appears.
- **If the driver forgets to tap End:** the next time they open the app, it shows "This trip includes a 9-hour stop. End the trip there?" Nothing runs in the background to detect this.
- **If iOS stops the app mid-trip:** the app detects the gap on next open and marks the trip "partially recorded," with the gap drawn as a dotted line.

### 3.2 Trip summary screen (see mockup 1)
- Route map with **privacy trim**: the first and last 5 miles aren't stored, and start and end show as approximate circles.
- Stats: miles, moving time, states, main highway (interstate shield).
- **Elevation profile**, with the highest point labeled.
- New badges (states, legendary roads) and the career counter with progress toward 1,000,000 miles.
- **Share trip card** button.

### 3.3 Share cards (see mockup 2)
- 9:16 images for Stories and TikTok. **Styles:** Night Highway (free), plus Road Atlas and Poster (Pro).
- Free cards carry a small "Made with Million Miles" watermark. **Pro removes it and exports in high resolution.**
- Before sharing, the driver can toggle "Hide route on card," which shows only states and stats. This protects lanes they don't want public.

### 3.4 My Map: the heatmap (see mockup 3)
- **Free:** heatmap of the **last 30 days**, with stats for that period.
- **Pro:** **all-time heatmap** with **filters**: year or date range, state, highway, legendary roads. Tap a highway to see how many times and when.
- Brighter, thicker lines = driven more often (5 levels: 1–2, 3–5, 6–9, 10–14, 15+).
- Stats under the map: miles, states, trips, legendary roads, top lanes.

### 3.5 Badges and milestones
- **States:** all 48 contiguous states plus AK and HI.
- **Legendary roads (20):** Donner Pass, Cabbage Hill, the Grapevine, Monteagle, Eisenhower Tunnel, Tehachapi Pass, Vail Pass, Fancy Gap, Siskiyou Summit, Sherman Hill and others.
- **Career milestones:** 100K, 250K, 500K, 750K, **1,000,000 miles**.
- **Repeatable goals:** a yearly mileage goal and "new states this year," so there's always something next.
- Badges appear **only after End Trip**, never while driving.

### 3.6 Out of scope for v1
Social feed and followers, leaderboards, automatic detection, Live Activity, Android, Apple Watch, cloud sync, accounts, prints.

---

## 4. Visualization: the main effort

This is where the app wins or loses. The mockups were built from **real OSRM routes and real elevation data**, so they're a reliable target.

### 4.1 Visual style
- **Dark theme by default** (night cab, easy on the eyes). Background `#14161c`, land `#1d2029`, state borders `#30353f`.
- **Route color:** amber `#ffb547` with a soft glow. Text `#f0efec`, with secondary text `#a6aab4`.
- **Heatmap ramp (one hue, dim to bright):** `#8a4a12 → #c2650f → #f08c1a → #ffb547 → #ffe1a0`. Checked with a palette validator: the brightness steps are evenly spaced, and the dimmest step is still visible on the dark background.
- **Fonts:** Inter for text, Barlow Condensed for big numbers (the "highway sign" feel).

### 4.2 Map rendering: two layers
| Where | Technique | Why |
|---|---|---|
| **Share cards and the heatmap overview** | **Custom-drawn map** using bundled US state outlines (public domain, a few hundred KB), drawn with SwiftUI Canvas | Looks like the mockups, works offline, renders identically on every phone, and is fast to export as an image |
| **Zoomable trip and heatmap detail** | **MapKit** with a custom dark map style and a custom overlay for the route and heat lines | Free, native, and handles zoom and real streets |

### 4.3 Data pipeline (all on the phone)
1. **Record:** location fixes every ~100 m (accuracy ~20–50 m while charging), plus altitude.
2. **Clean:** drop GPS jumps (impossible speeds), fill tunnel gaps in between known points.
3. **Simplify:** reduce the route to its key points (Douglas–Peucker, ~10–30 m tolerance), roughly 10x smaller.
4. **Trim:** remove the first and last 5 miles from the stored and displayed route.
5. **Enrich:**
   - **States:** check which state each point falls in, using the bundled outlines.
   - **Highways:** match points to a bundled, simplified interstate network. Natural Earth roads are public domain; OSM-derived data needs attribution.
   - **Legendary roads:** a trip earns a badge when it passes through both the entry and exit zones of that road.
   - **Elevation:** GPS altitude smoothed with the iPhone's barometer. No online elevation API, so the route never leaves the phone.
6. **Heat index:** split the country into a grid of small cells (geohash, ~1 km). Store **how many trips passed through each cell** and which trips. The heatmap colors each piece of road by its cell's count, and filters just recount for the selected trips.
7. **Store:** encrypted on-device database (SwiftData or SQLite). Raw points are deleted after processing, and dates are kept only to the day.

### 4.4 Share card export
- Render with SwiftUI's `ImageRenderer` at **1080×1920**.
- Share through the iOS share sheet, with a direct "Instagram Stories" option.
- Each card style is a separate SwiftUI view, so adding styles later is cheap.

### 4.5 Visualization milestones
1. Draw a hard-coded route (the I-80 mockup data) on the custom map.
2. Elevation chart with Swift Charts.
3. Trip summary screen that matches mockup 1.
4. Three card styles that match mockup 2, exported at 1080×1920.
5. Heatmap from 30+ sample trips that matches mockup 3, including filters.
6. MapKit zoom view with heat lines.
7. Performance: the heatmap for 1,000 trips renders in under 1 second.

---

## 5. Pricing (subscription)

| Plan | Price | Notes |
|---|---|---|
| **Monthly** | **$4.99/month** | The most common entry price for single-purpose utility apps |
| **Yearly** | **$39.99/year** | About 33% off monthly, a common discount. Highlight it as "Best value." Includes a **7-day free trial** |
| Free | $0 | Unlimited recording, 30-day heatmap, trip summary, badges, career counter, Night Highway card with watermark |

- **Pro includes:** all-time heatmap, filters, full trip history, all card styles, no watermark, high-res export, future styles.
- Your suggested ~$50/year is reasonable too. Start at $39.99, and **try $49.99 later** as a learning experiment.
- **Implementation:** StoreKit 2 plus RevenueCat (free under $2.5K/month in revenue) for the paywall and analytics.
- **Show the paywall** when the driver taps "All time" or a filter, and after their 3rd trip, never on first launch.

---

## 6. Tech stack

| Area | Choice |
|---|---|
| Language and UI | **Swift and SwiftUI** (native; the best way to learn iOS properly) |
| Location | Core Location, with "While Using" permission and background location mode during a trip (the blue indicator shows) |
| Altitude | Core Location plus `CMAltimeter` (barometer) |
| Maps | SwiftUI Canvas (custom map) plus MapKit (zoom) |
| Charts | Swift Charts |
| Storage | SwiftData (encrypted with iOS Data Protection); optional iCloud backup, off by default |
| Purchases | StoreKit 2 plus RevenueCat |
| Crash reports | Xcode Organizer (free) or Sentry free tier |
| Bundled data | US state outlines (us-atlas / Census, public domain), simplified interstates (Natural Earth, public domain), 20 legendary-road zones (hand-drawn) |
| Needed | A Mac with Xcode, an **Apple Developer account ($99/year)**, an iPhone for testing, test drives in a car to start |

---

## 7. Build plan (solo, learning pace)

| Weeks | Milestone | What you'll learn |
|---|---|---|
| 1–2 | SwiftUI basics; Start/End recording in a car; save trips | Xcode, SwiftUI, Core Location, permissions |
| 3–4 | Data pipeline: clean, simplify, trim, states | Geometry, background modes, data storage |
| 5–7 | **Visualization:** custom map, trip summary, elevation chart | Canvas, Swift Charts, design work |
| 8–9 | **Share cards** (3 styles) and **heatmap** (free view) | ImageRenderer, share sheet, performance |
| 10 | Pro: all-time map, filters, paywall, subscriptions | StoreKit 2, RevenueCat, sandbox testing |
| 11 | Badges, career counter, onboarding, settings, data wipe | Polish, edge cases |
| 12 | **TestFlight** with 5–10 truck drivers | Beta distribution, feedback |
| 13 | Fixes; App Store screenshots (use the mockups); privacy policy; submission | App Review, App Store Connect |
| 14 | **Launch** | Release, monitoring |

Expect it to slip. For a first app, 14 weeks can easily become 20, and that's fine.

---

## 8. App Store and legal checklist
- [ ] Privacy policy (a simple web page) explaining that location is stored only on the phone, with no tracking and no selling of data
- [ ] App Store privacy label: precise location, "not linked to you," "not used for tracking"
- [ ] Location permission text: "Million Miles records your route only between Start Trip and End Trip."
- [ ] Background location mode explained in the App Review notes, with a short screen recording
- [ ] Subscription terms, restore purchases, and a manage-subscription link
- [ ] An in-app note: "Start before rolling, end after parking. Never use your phone while driving."
- [ ] Attribution screen for map data
- [ ] Optional: a one-time review by a transportation attorney before going big

---

## 9. Launch (simple, learning-focused)
1. **TestFlight drivers:** recruit from r/Truckers, trucker Facebook groups and one truck-stop visit.
2. **App Store page:** use the three mockups as screenshots, with the tagline "Your miles. Your map. Your million."
3. **Content:** post your own TikTok and Instagram videos using real share cards from beta drivers (with their permission). Reach out to 5 trucker creators with free Pro.
4. **Learn from the numbers:** downloads, trips per driver per week, trial starts, conversion, and churn. Those are your lessons for app #2.

---

## 10. Known risks (from three Goldfish reviews)
- **Drivers may forget to tap Start.** This is the biggest risk with manual tracking. Use the "previously driven" states and the career counter so a missed day doesn't feel like a loss.
- **iOS may stop recording mid-trip** (memory pressure, crashes). Detect the gap and show it honestly; test on 11-hour drives.
- **The map stops changing** for drivers who run the same lanes. The heat getting brighter and the repeatable goals help.
- **Copycats** (Driver Tracer, Trucker Path). It doesn't matter for a learning project; ship and learn.
- **Small market.** Revenue will likely be modest, which is accepted.

---

## 11. Definition of done
**The app is live on the App Store**, a handful of real drivers have recorded real trips, at least one person has paid for Pro, and you know how to do it all again faster for app #2.
