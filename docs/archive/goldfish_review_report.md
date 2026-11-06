# Goldfish Review Report: "Million Miles"

- **Document reviewed:** `concepts_brief.md` (2026-11-06)
- **Method:** Google's Elephant-Goldfish Model, adapted for an idea brief. Five fresh-context reviewers saw only the brief. The Elephant consolidated their findings, and the human decides.
- **Reviewers (lenses):**
  - **C:** comprehension
  - **U:** user personas (a 52-year-old company driver, a 34-year-old owner-operator, a 27-year-old #truckertok creator)
  - **Z:** zoom-out, contrarian, inventive catalyst
  - **M:** market and economics (with web search)
  - **F:** iOS feasibility, privacy and legal (with web search)
- **Limitation:** this is a desk review. It stress-tests the reasoning, but it is **not** evidence of real demand. Only real drivers can provide that.

---

## Verdict

**The pride idea held up. The business model and the first-version plan did not.**
No reviewer found a direct "Strava for truckers," and the map, badges and Wrapped hook was rated strong. But all five reviewers independently broke the paid tier, and four found the same fatal flaw in the million-mile hook.

---

## Consolidated findings

| ID | Severity | Finding | Raised by | Elephant's call |
|---|---|---|---|---|
| B1 | 🔴 Blocker | **The million-mile bar starts at zero.** Veterans with 500K–2M+ career miles see an almost empty bar, and new drivers need 8–10 years. The headline hook fails for the people who care most. | C, U, Z, F | **PROPOSE FIX:** ask for career miles at onboarding (self-reported, optional odometer photo). The bar starts at the driver's real number on day one. |
| B2 | 🔴 Blocker | **The paid tier is hollow and mostly applies to the wrong users.** Tax exports are listed as paid but scheduled for v2. Wrapped only matters in December, and the "lifetime map" is empty at launch. **W-2 company drivers can't deduct per diem** (suspended since 2018; reviewers say the 2025 tax law made it permanent, not verified against IRS text). Fuel-tax (IFTA) filing is done by the carrier or the owner-operator's ELD. Cheap competitors exist (IFTA Track: free; Per Diem Plus: $7.99/mo). And tax data creates liability. | C, U, Z, M, F | **PROPOSE FIX:** remove tax features from this product entirely. Monetize pride directly (see the decisions below). The Elephant's earlier claim that "long-haul drivers can deduct per diem" was wrong for company drivers. |
| B3 | 🔴 Blocker | **The revenue math is wrong.** The median freemium download-to-paid rate is about 2.1% (RevenueCat 2026). So 10K subscribers needs ~475K installs, which is roughly 25–50% of reachable iPhone long-haul drivers, not "0.5%." Net revenue after Apple's 15% cut is ~$212K/year. | Z, M | **PROPOSE FIX:** rebuild the model as installs → conversion → renewal for each segment. Treat a $25/year subscription as having a low ceiling. |
| B4 | 🔴 Blocker | **The phone can't tell the truck from the family car.** "Driving" detection is the same for the truck, the car on home time, riding as a passenger, or a co-driver asleep in the berth. Team drivers would both log the same miles. Totals and badges become untrustworthy. | U, F | **PROPOSE FIX:** after each trip, ask "Was this in your truck?" Add a team-driving toggle and length/highway heuristics. |
| M1 | 🟡 Major | **Tracking reads as evidence and surveillance.** Phone GPS can be subpoenaed after a crash, timestamps reveal speed, and "private by default" is only a promise. | U, F | **PROPOSE FIX:** keep data on the device only, with no server in v1. Collapse raw points into highway segments after each trip and delete speed data. Say this loudly in marketing. |
| M2 | 🟡 Major | **The paywall locks away the shareable parts,** which contradicts the brief's own Strava rule ("what spreads is free"). | C, U | **PROPOSE FIX:** make the shareable card, a basic Wrapped and the career-miles bar free. |
| M3 | 🟡 Major | **The demand test measures curiosity, not commitment.** A comment costs nothing. And the fake video shows Wrapped, which isn't in v1. | C, U, Z | **PROPOSE FIX:** use a landing page with an email or $25 pre-order plus the question "Would you allow location: Always? Y/N." Show only features you'll actually build. |
| M4 | 🟡 Major | **"Post only after delivery" can't be built.** The app can't detect deliveries, and there's no feed to post to anyway. | C, F | **PROPOSE FIX:** share to the camera roll, TikTok or Instagram. Show states and highways only, with a 72-hour delay and the first and last ~10 miles of each day trimmed. |
| M5 | 🟡 Major | **Notifications while driving are a legal trap.** Federal rules count *reading* a device as texting. A real-time "Donner Pass badge!" alert also invites badge-chasing on dangerous grades in winter. | F | **PROPOSE FIX:** send nothing until the truck has been stationary for 5+ minutes. Award badges silently afterward. |
| M6 | 🟡 Major | **The novelty fades.** Drivers run the same lanes, so the map stops changing after a few weeks, and the social layer (Strava's real hook) was cut. Renewal depends on December alone. | Z, M | **ACCEPT AS RISK:** ask drivers "Would you open this in week 6?" Consider one-time purchases instead of a subscription. |
| M7 | 🟡 Major | **The moat is thin.** Generic auto-filling travel maps already exist (Places Been, GeoRecords, GeoPin), and Trucker Path could copy the feature. | M | **PARTLY CONTEST:** this is true of every simple app, including Early and Cat on Chair. The defense is speed, trucker identity (road badges, million miles) and creator partnerships signed before launch. |
| M8 | 🟡 Major | **3–4 weeks is too tight.** Map-matching needs a server, and trip detection needs field testing with real drivers. | Z, F | **PROPOSE FIX:** draw simplified GPS lines with no map-matching. Detect legendary roads with entry and exit gates. Work out states on the device. Spend 2 of the 4 weeks testing with 5–10 drivers on TestFlight. |
| M9 | 🟡 Major | **The comparison apps don't fit.** Viral consumer apps sell to hundreds of millions of people. This is a niche with a ceiling. | Z, M | **PARTLY CONTEST:** the ceiling is real, but $100–250K/year for a 1–2 person team is a good outcome. Benchmark against niche vertical apps. |
| N1 | 🟢 Nit | Battery is the wrong worry, because cab phones are almost always plugged in. The real risk is iOS stopping background tracking and losing trips. | U, Z, F | **AGREE:** measure missed trips in field testing. |
| N2 | 🟢 Nit | App Review should approve "Always" location if you ask for When-In-Use first, upgrade after the first trip, keep a manual mode and send a demo video with the review notes. | F | **AGREE.** |
| N3 | 🟢 Nit | Undefined jargon ("honks," heatmap vs. lifetime map, "full" Wrapped). | C | **AGREE.** |

---

## Catalyst ideas (from the reviewers)

1. **Career Card web page (the smallest test):** a weekend-built web page. Enter career miles, tick the states and legendary roads you've driven, get a shareable poster. It needs no app, no location permission and no Apple review, and it works on Android. It could **ship "Trucker Wrapped 2026" this December**, about 7 weeks from now. (Z)
2. **A verified mileage résumé:** drivers change jobs often, and experience sets pay and insurance. A driver-owned record of miles, states and mountain-pass experience works as a credential. Recruiters and carriers pay to see it, and drivers use it free. (Z)
3. **The family is the audience:** a delayed weekly postcard to the family ("Dad crossed 7 states this week"). Families share on Facebook, it works as a gift, and trucker-spouse groups give you distribution. (Z)
4. **Carrier-sponsored recognition:** carriers already pay for million-mile awards and lose heavily to driver turnover. Offer a branded recognition program where drivers own their data and only opt-in milestones are shared. One carrier deal could be worth thousands of subscriptions. (Z)

---

## Decisions for the human

1. **Monetization:** (a) free app with one-time purchases (lifetime unlock, printed posters, family gifts); (b) carrier-sponsored recognition (B2B); (c) a separately validated owner-operator tool. **The Elephant recommends (a) now and (b) later.**
2. **First test:** the Career Card web page plus a December Wrapped, *or* a landing page with pre-order and the question "Would you allow location: Always?" **The Elephant recommends the Career Card.** It tests pride, sharing and creator distribution all at once, with no permissions needed.
3. **Who it's for:** driver-first, or family-first as a gift?
4. **Approve edits to `concepts_brief.md`** based on the fixes above?

---

## Sources cited by reviewers

- RevenueCat, State of Subscription Apps 2026: https://www.revenuecat.com/state-of-subscription-apps-2026/
- Per diem for W-2 drivers: https://ttlc.intuit.com/community/taxes/discussion/can-a-w2-employee-truck-driver-claim-per-diem-laundry-phone-expenses-the-company-does-not-offer-per/00/3309492 · https://jupid.com/blog/truck-driver-tax-deductions-2026 · https://landline.media/pair-of-bills-would-reverse-per-diem-changes-to-tax-code/
- Per diem rates: https://tax.thomsonreuters.com/news/irs-announces-special-per-diem-rates-for-travel-away-from-home-beginning-october-1-2026/
- Competing tax apps: https://apps.apple.com/us/app/ifta-track/id6450858602 · https://apps.apple.com/us/app/id6760213891 · https://apps.apple.com/us/app/per-diem-plus/id1151567391 · https://www.24-7pressrelease.com/press-release/531269/fleetcollect-launches-automated-ifta-mileage-tracking-app-for-motor-carriers
- Auto-filling map apps: https://apps.apple.com/app/id6670202865 · https://apps.apple.com/bb/app/georecords/id6743328334 · https://apps.apple.com/ph/app/id6754455283
- Trucker Path Diamond plan: https://helpcenter.truckerpath.com/hc/en-us/articles/9398625000717
- App Review on location: https://developer.apple.com/forums/thread/771202 · https://developer.apple.com/forums/thread/704032
- Federal texting rule: https://www.ecfr.gov/current/title-49/subtitle-B/chapter-III/subchapter-B/part-392/subpart-H/section-392.82
