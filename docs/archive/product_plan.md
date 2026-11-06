# Product Plan: "Million Miles", a pride app for US truck drivers (iPhone + Android)

- **Author:** Elephant session (with the founder)
- **Date:** 2026-11-06
- **Version:** 2. This replaces `concepts_brief.md` and includes the fixes from the first Goldfish review.
- **Stage:** Idea. Nothing has been built, and no drivers have been interviewed yet.

---

## 1. Overview

A free mobile app for **iPhone and Android** that **automatically logs a truck driver's miles** and turns their career into something they're proud of and want to show off:

- a **career-miles counter** that starts at the driver's real lifetime number, entered at sign-up
- a **US map** that fills in with the highways they've driven
- **badges** for states and for ~20 legendary roads (Donner Pass, Cabbage Hill, the Grapevine, Monteagle, Eisenhower Tunnel and others)
- milestones (100K, 250K, 500K, **1,000,000 miles**)
- a **weekly trip card** to share on TikTok, Facebook or Instagram, with a small "Made with Million Miles" watermark

**One-line pitch:** "Strava for truckers: your miles, your map, your million."

**Decided by the founder:**
- **No ads.**
- **No year-end "Wrapped" recap.** Dropped.
- **No free web-page launch.** Mobile app only.
- **iPhone and Android from day one**, to reach the whole audience.
- **No tax or compliance features** (per diem, fuel-tax/IFTA). Most drivers can't use them, cheap tools already exist, and they create liability.

---

## 2. The user and the market

- **Who:** US truck drivers, mainly **long-haul (OTR)** drivers who are away for weeks and live in the truck. There are ~3.5M US truck drivers in total, roughly 2M of them heavy tractor-trailer drivers. These figures are approximate.
- **Why they'd care:** the work is invisible and thankless, but the pride culture is strong. Carriers hand out million-mile safe-driving awards, and drivers post odometer milestones on TikTok and YouTube.
- **When they'd use it:** only while off duty and parked. Holding a phone while driving a commercial truck is banned by federal rules, and reading a device counts as texting. Logging must be fully automatic.
- **Phones:** a mix of iPhone and Android. This audience is likely more Android-heavy than the US average, which is why both platforms ship in v1. Phones are usually plugged into a cab charger.
- **Trust:** company drivers already carry an employer-run electronic logging device (ELD) and dislike being watched. Phone GPS can be subpoenaed after a crash.

**Competitive scan (desk research):** there is no direct "Strava for truckers."
- Fleet gamification (Samsara, Geotab's d2go, Azuga) is run by the employer.
- Generic auto-filling travel maps (Places Been, GeoRecords) have no trucker identity.
- Trucker Path has a large user base and could copy the feature.
- **The defense** is trucker identity (road badges, million-mile culture), speed, and creator partnerships signed before launch.

---

## 3. Product: version 1 scope

### Core features (free)
1. **Onboarding:** enter career miles (self-reported, optional odometer photo), years driving, and the states driven so far (tap on a map).
2. **Automatic trip logging** in the background.
   - After each trip: **"Was this in your truck?"** (one tap). Unconfirmed trips don't count.
   - A **team-driving** setting, so co-drivers don't double-count.
   - Heuristics (trip length, share of highway driving) to pre-label likely truck trips.
3. **Map:** simplified GPS lines drawn on a US map (no map-matching server).
4. **Badges:** states are worked out on the device from bundled boundary maps. Legendary roads are detected when the truck passes entry and exit points.
5. **Milestones and career counter.**
6. **Weekly trip card:** states and highways only, shared to the camera roll or social apps.
   - **72-hour delay** before a trip can be shared.
   - The **first and last ~10 miles of each day are trimmed** to hide home, shipper and receiver locations.
   - Watermarked.

### Safety and privacy rules (not negotiable)
- **No notifications while moving.** Badges are awarded silently, and alerts wait until the truck has been stationary for 5+ minutes.
- **No live location, no speed data and no rankings.** Raw GPS points are collapsed into highway segments after each trip, then deleted.
- **Data stays on the phone in v1** (no account and no server), with an optional encrypted cloud backup later.
- Never shared with employers.

### Pro unlock (paid, one-time)
- **~$14.99 once** (no subscription), via the App Store and Google Play.
- Includes: the lifetime map and heatmap (free shows the last 30 days), full trip history, high-resolution cards without the watermark, extra card themes, an "experience résumé" view, and badge collections.

### Out of scope for v1
- Social feed, followers, "honks" (tap-to-cheer reactions), clubs (v2)
- Year-end recap, ads, tax and compliance features
- Navigation, parking, load boards
- ELD integration, carrier dashboards

---

## 4. Technical approach

- **One codebase for both platforms:** React Native (Expo) or Flutter, with native modules for location and motion.
- **iPhone:**
  - Significant-change and Visits monitoring wake the app. Motion activity confirms driving. Then live location updates start at ~100 m accuracy with a 100–200 m distance filter, and stop after ~10 minutes stationary. Accuracy goes up while charging and down in Low Power Mode.
  - Ask for "While Using" location first and upgrade to "Always" after the first logged trip, with an explainer screen. Keep a manual start/stop mode. Send a demo video with the App Review notes.
- **Android:**
  - The Activity Recognition API detects driving. A foreground service then logs location, which shows a persistent notification.
  - Google Play requires a **background-location declaration form and a demo video** for review.
  - Must handle **phone makers' aggressive battery management** (Samsung, Xiaomi, Motorola), which kills background apps. The app needs an onboarding guide for battery settings.
- **Tunnels and dead zones:** fill gaps in between known points.
- **No backend in v1:** the only external services are crash reporting, store billing (RevenueCat), and print-on-demand via the web.

---

## 5. Monetization (no ads)

| Stream | Model | When |
|---|---|---|
| **Pro unlock** | ~$14.99 one-time | v1 |
| **Physical products** | Map posters or canvas (~$30–60) and metal milestone plaques (~$40–80), made and shipped by a print-on-demand service. Often bought by **family as gifts** (Christmas, Father's/Mother's Day, retirements, Truck Driver Appreciation Week in September). | v1.1 |
| **Carrier recognition programs** | A branded milestone program sold to carriers, ~$1–3 per driver per month. The driver owns the data and shares only milestones they opt into. | After ~10K active drivers |
| **Opt-in verified experience profile** | Drivers choose to show their record to carriers that are hiring. Carriers pay per lead or per hire. | Later, once there's trust and scale |

**Illustrative year-one numbers (assumptions, not forecasts):** 100K installs across both platforms. 2–3% buy Pro (~$12.70 net each after the store cut) = $25–38K. 0.5–1% order a physical product (~$15–20 profit) = $8–20K. **Consumer total ~$33–58K.** One carrier pilot (1,000 drivers × $2/month) adds ~$24K/year. Android users typically buy less often than iPhone users.

---

## 6. Go-to-market

- **Creators first:** sign up 10–20 trucker creators on TikTok and YouTube before launch. Give them free Pro, paid posts, or a revenue share.
- **The demo:** a career counter rolling up to the driver's real number, and the map filling in with their states.
- **Spouse and family channel:** trucker-family Facebook groups for posters and plaques.
- **In person:** QR code flyers at big truck stops (Iowa 80 and others).

---

## 7. Validation before building

1. **Search the App Store and Google Play by hand** for look-alikes (30 minutes).
2. **Talk to 10–15 drivers at a truck stop:** career miles, whether they'd type them in, a mock "Allow location: Always" prompt (count yeses), what they'd pay, and "would you open this in week 6?"
3. **Landing page plus a demo video showing only v1 features.** Measure email sign-ups and **Pro pre-orders**, with one question: "Would you allow location: Always?"
4. **Go/no-go:** ≥500 waitlist sign-ups and ≥50 pre-orders within 3 weeks of posting through 3+ creators. These thresholds are guesses and need challenging.

---

## 8. Timeline (1–2 people)

| Weeks | Work |
|---|---|
| 1–3 | Validation (section 7) |
| 4–9 | Build v1 on both platforms |
| 10–11 | TestFlight and Play beta with 10–20 drivers: tune trip detection, count missed trips |
| 12 | Launch with creators |
| +1–2 months | Print shop (v1.1), then social features (v2) |

---

## 9. Key risks and open questions

1. **Will drivers allow always-on location?** This is the riskiest assumption.
2. **Will the background tracking work reliably,** especially with Android battery management, or will trips go missing?
3. **Will people keep using it** without a social feed once their map stops changing?
4. **Will enough people pay $14.99?** Will families buy physical products?
5. **Will Trucker Path or an ELD vendor copy it?**
6. **Is the self-reported career number credible enough** for a future "verified" profile?
