# Goldfish Review v3: `product_plan_v3.md` (multi-model)

- **Date:** 2026-11-06
- **Reviewers:** Opus 5.5 (searched the web) · Sonnet 5.5 (no searches) · Haiku 5.5 (searched the web). Identical instructions, fresh context, no Fable.
- **Founder decisions kept fixed:** iPhone first · manual Start/End · free 30-day heatmap, paid all-time map with filters · no ads · no carrier revenue.
- **Limitation:** a desk review is not evidence of demand.

---

## Verdicts

| Model | Back it? | In one line |
|---|---|---|
| Opus | ❌ Build / ✅ a redesigned pilot | "The pilot as designed cannot test the chore or the paywall." |
| Sonnet | ❌ | "Fund only the interviews and a cheap prototype, not the build." |
| Haiku | ❌ | "Contradicts itself on passive detection and privacy." Back a cheaper test first. |

**What changed since v2:** always-on location, trip classification and App Store permission are **no longer the main concerns**. Manual Start/End fixed them. The remaining problems are **(1) contradictions the Elephant introduced, (2) a weak pilot, and (3) the economics.**

---

## Where the models agreed (high confidence)

| # | Severity | Finding | O | S | H | Elephant's call |
|---|---|---|---|---|---|---|
| A1 | 🔴 | **The "parked" reminder and the 60-minute and 10-hour auto-pause and auto-end need detection the plan forbids.** iOS sends no location updates while the truck is stopped, so the timers aren't guaranteed to fire, and the app can't know the truck is parked. The Elephant introduced this contradiction. | ✅ | ✅ | ✅ | **ACCEPT.** Remove auto-end. Handle idle gaps at the next tap ("Trim the 6-hour gap?"). Optionally gate reminders with **Motion data only (CoreMotion: driving vs. stationary, no location)**, and test that against manual-only. |
| A2 | 🔴 | **The pilot can't produce a usable signal.** With n=20, "15%" is 3 clicks. A fake-door click isn't a purchase. "70% of driving days" has no ground truth. Recruiting through creators biases the sample toward fans. | ✅ | ✅ | ✅ | **ACCEPT.** n≥40, recruit at truck stops as well as through creators, a daily one-tap "did I drive today?" diary as ground truth, and a **real charge**. |
| A3 | 🔴/🟡 | **The economics don't justify 4–5 months of work.** Base case ~$6K net. Sonnet says the 1% view-to-install rate is **10–100x too high**; at 0.05–0.1% the base case is a **net loss**. Founder time and refunds aren't counted. | ✅ | ✅ | ✅ | **ACCEPT.** Set a minimum-revenue kill threshold. Measure the creator funnel before modeling. **This is the third review in a row to flag thin economics.** |
| A4 | 🟡 | **Legal exposure is understated.** Phone data can be subpoenaed, including from iCloud backups. A glanceable miles counter may count as "reading" under the texting ban. **A one-tap wipe after a crash could count as destroying evidence** (Opus). Sharing routes may breach carrier confidentiality rules (Haiku). Badges for notorious grades gamify risky driving (Sonnet). | ✅ | ✅ | ✅ | **ACCEPT.** One paid review by a transportation attorney before the beta. Remove the live miles display while moving. Cards show no route by default. Use safety framing for road badges. |
| A5 | 🟡 | **Scope and timeline are still too big.** Live Activity, widget, Siri, road geofences, trimming, encryption, iCloud backup, billing and App Review in 8 weeks. | — | ✅ | ✅ | **ACCEPT.** Cut v1 to **Start/End, map, career counter, state badges, Pro paywall**. Legendary roads come after validation. |
| A6 | 🟡 | **Route accuracy is too low for road badges.** 100–200 m point spacing without map-matching can't separate frontage roads or old highways from the interstate, which matters most at mountain passes. | — | ✅ | ✅ | **ACCEPT.** Higher accuracy while recording (phones are on the charger). Corridor zones for the 20 roads. Run badge detection *before* trimming (Opus). |
| A7 | 🟡 | **Competition is underweighted.** Driver Tracer's listing names truck drivers, and 0 Product Hunt upvotes isn't evidence of no traction. **The driver's ELD and apps like IFTA Track already hold complete mileage data, automatically.** | ✅ | ✅ | ✅ | **ACCEPT.** Do the store search. Test an **import of past trips from an ELD or IFTA file to backfill the map** (Opus). Position on identity, not data. |

## Findings from only one model

| Model | Finding | Elephant's call |
|---|---|---|
| **Opus** | **A 4-week pilot never reaches day 31**, the moment the free 30-day map runs out and Pro should sell. | **ACCEPT. Excellent catch.** Run the pilot for 8 weeks, with a real charge at day 31. This directly tests your paid all-time map decision. |
| **Opus** | **iOS ends Live Activities after 8 hours**, and drivers can drive 11. If iOS kills the app mid-trip, a While-Using recording session can't restart itself. | **ACCEPT.** Test on real 11-hour days. Detect dead sessions and log the gap. Or drop the Live Activity in v1. |
| **Opus** | Sleeper-berth splits (7/3, 8/2) never reach 10 hours stationary, so trips merge across duty days. | Moot once auto-end is removed (A1). |
| **Opus** | Trimming around every 30-minute stop punches holes in the map at truck stops. | **ACCEPT:** trim only the displayed and shared versions. Keep simplified segments for the driver's own map. |
| **Haiku** | **"Time of day is not stored" contradicts** the timestamps needed for stops, trimming and elapsed time. | **ACCEPT.** Specify exactly what's kept (dates and stop durations; raw points deleted after processing). iCloud backup off by default. |
| **Haiku** | Team drivers lose miles when only the person who taps Start records. | **ACCEPT:** either driver can claim a trip. |
| **Sonnet** | **A Siri shortcut or widget can't start recording** under While-Using permission without opening the app. | **ACCEPT:** tapping Start opens the app. Verify in the prototype. |
| **Sonnet** | **Day-one map is empty, and pride is about the past.** | Partly handled by tapping in states driven at sign-up. **Plus the ELD/IFTA import (A7).** |
| **Sonnet** | **Charging for the all-time map means "paywalling the user's own data."** | **CONTEST, because you decided this.** The 8-week pilot's day-31 charge tests it directly. If conversion is low or reviews turn angry, revisit. |

---

## How the models reviewed differently

- **Opus:** the deepest iOS research (the 8-hour Live Activity limit, sessions that can't restart from the background), the sharpest pilot design (day 31), and a creative fix (importing ELD data).
- **Sonnet:** no searches, but the most skeptical numbers (view-to-install 10–100x too high) and the most product-level challenges (empty map, paywalling your own data).
- **Haiku:** the best at spotting the plan's internal contradictions (privacy vs. timestamps) and practical gaps (team drivers, carrier confidentiality).

---

## Proposed changes for v4 (pending the founder's approval)

1. **Step 0 (2 weeks, no code):** 15–20 interviews at truck stops plus a clickable prototype (including the empty day-one state). **Kill rule:** if fewer than ~8 of 15 say they'd tap Start every day, change course.
2. **Pilot:** **8 weeks, n≥40**, recruited from truck stops as well as creators, with a daily ground-truth diary and a **real charge at day 31**. Two groups: manual-only vs. Motion-gated reminders.
3. **v1 cut:** Start/End, map, career counter, state badges, Pro. Remove auto-end, the parked reminder and the Live Activity mileage readout. Legendary roads come after validation.
4. **Privacy spec:** keep dates and stop durations, delete raw points after processing, iCloud backup off by default, routes hidden on cards by default, an attorney review before the beta.
5. **Backfill test:** import trip history from an ELD or IFTA export so the map isn't empty on day one.
6. **Economics:** measure the creator funnel first, then set a **minimum-revenue kill threshold** before building v1.

## Decisions for the founder

1. Accept **interviews plus a clickable prototype before any code**?
2. Accept the **8-week pilot with a real charge on day 31**?
3. **Motion-gated reminders** (Motion permission, not location), or strictly manual?
4. What **minimum year-one revenue** makes this worth your time? That number sets the kill threshold.

---

## Sources (cited by reviewers)

- Apple, Live Activities (8-hour limit): https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple Developer Forums, background sessions: https://developer.apple.com/forums/thread/794480 · https://developer.apple.com/forums/thread/767460 · https://developer.apple.com/forums/thread/748098
- 49 CFR 392.80: https://www.law.cornell.edu/cfr/text/49/392.80 · 392.82: https://www.ecfr.gov/current/title-49/subtitle-B/chapter-III/subchapter-B/part-392/subpart-H/section-392.82
- Driver Tracer: https://apps.apple.com/app/driver-tracer/id6757180995 · https://hunted.space/product/driver-tracer
- IFTA Track: https://apps.apple.com/us/app/ifta-track/id6450858602
- Trucker Path installs: https://www.fleetowner.com/operations/drivers/article/21695474/trucker-path-app-surpasses-15-million-installs
