# Goldfish Review v2: `product_plan.md` (multi-model)

- **Date:** 2026-11-06
- **Method:** Elephant-Goldfish Model. Each reviewer started fresh, saw only the plan, and got **identical instructions**. Only the model changed.
- **Reviewers:**
  - **Opus 5.5:** used web search, and found a competitor
  - **Sonnet 5.5:** no web searches; reasoned from its own knowledge
  - **Haiku 5.5:** used web search on platform documentation
  - **Fable 5.1:** ❌ didn't run. The account needs usage credits for this model (HTTP 429).
- **Limitation:** a desk review is not evidence of demand.

---

## Verdicts

| Model | Would back it? | Verdict in one line |
|---|---|---|
| Opus | ❌ Not yet | "Validation would be passed by any creator-driven hype." It doesn't test the permission rate or week-6 retention. |
| Sonnet | ❌ Not as written | "Fund a 2-week tracking spike plus real driver conversations, not a 12-week launch." |
| Haiku | ❌ Not as written | "Reorder the work so a tracking spike on real trucks comes before any UI, creators or store listings." |

**All three models independently chose the same "one thing I'd change": test tracking with real drivers first, and make that the go/no-go gate.**

---

## Where the models agreed (high confidence)

| # | Severity | Finding | O | S | H | Elephant's call |
|---|---|---|---|---|---|---|
| A1 | 🔴 | **Validation tests hype, not the risks that can kill the idea.** Sign-ups and comments say nothing about whether drivers grant "Always" location, whether trips are captured, or whether people keep using it. | ✅ | ✅ | ✅ | **ACCEPT:** a tracking pilot becomes step 1 |
| A2 | 🔴 | **Six weeks to build for two platforms is not credible.** Background location, Android phone makers' battery management, store reviews. Estimates: 4–5 months total, or 12–16 weeks to build. | ✅ | ✅ | ✅ | **ACCEPT:** re-plan |
| A3 | 🟡/🔴 | **The map stops changing, so the habit dies.** Drivers repeat lanes, badges unlock early, and the only lever that keeps people coming back (social) is pushed to v2. **The paywall gates the lifetime map, the very thing that makes the app worth keeping.** | ✅ | ✅ | ✅ | **ACCEPT:** design repeatable goals for v1 |
| A4 | 🟡 | **The privacy trim protects the wrong places.** Long-haul days rarely start at home, and shippers and receivers are mid-day stops, so trimming the first and last 10 miles misses them. Timestamps reveal speed and hours of service, which can be subpoenaed. Weekly cards reveal lanes. | ✅ | ✅ | ✅ | **ACCEPT:** trim around every stop over 30 minutes, store dates without times, encrypt |
| A5 | 🟡 | **The 100K installs figure is invented,** a one-time unlock gives no recurring revenue, and creator costs aren't counted. About $33–58K can't support 1–2 people. | ✅ | ✅ | ✅ | **ACCEPT:** build the model bottom-up from pilot data |
| A6 | 🟡 | **Carrier revenue contradicts the trust promise** ("never shared with employers," "data stays on the phone"). | ✅ | ✅ | — | **ACCEPT:** redesign as a driver-sent certificate (no carrier dashboard), or remove it |
| A7 | 🟡 | **Confirming every trip causes fatigue,** and team-driving double-counting is unsolved. | ✅ | — | ✅ | **ACCEPT:** confirm once a day, auto-accept confident trips, pair team phones |
| A8 | 🟡 | **The go/no-go thresholds are arbitrary,** with no gates for permission rate, capture rate or retention. | ✅ | ✅ | ✅ | **ACCEPT:** new gates below |

## Where the models disagreed

| Topic | Opus | Sonnet | Haiku | Elephant's call |
|---|---|---|---|---|
| **One platform or both** | Android first (matches the plan's own audience claim) | Pick one platform, chosen from pilot data | One platform, wherever the validation drivers are | **CONTEST, because the founder chose both.** Keep both, but run the tracking spike on both and use a longer timeline. **Founder to decide.** |
| **Backups** | Encrypted cloud backup in v1, because "a lost phone erases a career" | — | Exclude data from cloud backups, for privacy | **Middle path:** an opt-in encrypted backup that the user controls |
| **Pilot design** | Paid 4-week pilot, 20–30 drivers | 2-week spike, 5–10 drivers | 2–3 week spike on real trucks | **4-week pilot, ~20 drivers, both platforms** |

## Findings from only one model

| Model | Finding | Elephant's check |
|---|---|---|
| **Opus** | **The "no competitor" claim is wrong:** **Driver Tracer** (App Store) logs trips automatically and has achievements, 17 driver ranks, and leaderboards that show truck drivers' company names. | **VERIFIED, it exists.** It's aimed at drivers in general, and its Product Hunt launch got 0 upvotes, so traction looks minimal. It's a weak competitor, but "first" is no longer a claim you can make. Differentiate on trucker identity and privacy. |
| **Sonnet** | Google Play requires **new personal developer accounts to run a closed test (12 testers, 14 days)** before going to production. | Plausible, but verify against current policy. It fits naturally into the pilot. |
| **Sonnet / Haiku** | **Pre-orders for an in-app unlock aren't supported,** and selling it through the web may break Apple's rule that digital purchases go through its own in-app payment system (guideline 3.1.1). | **ACCEPT:** use a "fake door" price test: show the price, record the click, take no money. |
| **Haiku** | On **Android 14+,** a location foreground service must declare its type, and starting it from the background is restricted. | **ACCEPT:** a technical item for the spike. |
| **Opus / Haiku** | Samsung and Xiaomi kill even foreground services. Test on at least 5 phone brands. | **ACCEPT.** |

## How the models reviewed differently

- **Opus** did the most outside research. It was the only one to find a real competitor, and it gave the most concrete numbers for the pilot gates.
- **Sonnet** didn't search at all, yet it was sharpest on platform policy (Play closed testing, pre-order rules) and on the plan's internal contradictions.
- **Haiku** was the most technical, focusing on Android 14 service rules, backup exclusion and a 95% capture gate.
- **Overlap:** the verdicts and the top fix were **the same across all three.** The differences were in what each noticed, not in the conclusion.

---

## Proposed changes to the plan (pending the founder's approval)

1. **New step 1, the tracking pilot (4 weeks, ~20 drivers, iPhone and Android, 5+ phone brands).**
   **Gates:**
   - ≥60% grant "Always" location
   - ≥90–95% of truck trips captured
   - ≥40% open the app weekly in week 4
   - ≥15% click the price in the fake-door test
2. **Timeline:** about 4–5 months to launch, not 12 weeks.
3. **Retention:** add repeatable goals in v1 (yearly mileage, lane and state streaks, seasonal roads, progress toward the next badge). **Make the lifetime map free**, and charge for extras (heatmap, résumé, high-res cards without the watermark, themes, physical products).
4. **Privacy:**
   - trim around every stop over 30 minutes
   - store dates without times, and no speed data
   - encrypt data at rest, with an opt-in encrypted backup
   - a one-tap wipe
   - write the privacy policy and store data-safety labels before the beta
5. **Monetization:** remove the carrier dashboard. If carriers come in at all, it's through a certificate the driver chooses to send. Model revenue with the pilot's conversion and retention numbers, minus creator costs.
6. **Trip confirmation:** confirm once a day, auto-accept confident trips, pair phones for team mode.
7. **Positioning:** acknowledge Driver Tracer, and differentiate on trucker identity, road badges and privacy.

## Decisions for the founder

1. Keep **both platforms at launch** (longer timeline), or launch on one first?
2. Approve the **pilot-first** reorder and its gates?
3. **Make the lifetime map free**, and charge for extras instead?
4. **Drop carrier revenue**, or keep the driver-sent certificate version?
5. Retry the **Fable** review after adding usage credits?

---

## Sources

- Driver Tracer: https://apps.apple.com/app/driver-tracer/id6757180995 · https://hunted.space/product/driver-tracer
- Google Play background location policy: https://support.google.com/googleplay/android-developer/answer/9799150
- Google Play policy (cited by Opus): https://support.google.com/googleplay/android-developer/answer/16965181?hl=en
- Android 14 foreground service types: https://developer.android.com/about/versions/14/changes/fgs-types-required
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Samsung foreground-service reports: https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/70748315/is-samsung-still-not-persisting-foreground-services
- Trucker Path ELD: https://www.truckinginfo.com/287795/trucker-path-launches-eld-solution
- FMCSA phone rules: https://www.fmcsa.dot.gov/driver-safety/distracted-driving/mobile-phone-restrictions-fact-sheet
