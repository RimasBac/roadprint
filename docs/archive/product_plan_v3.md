# Product Plan v3: "Million Miles", a pride app for US truck drivers

- **Author:** Elephant session (with the founder)
- **Date:** 2026-11-06
- **Version:** 3. This replaces `product_plan.md` (v2) and includes the fixes from the Goldfish review v2 plus the founder's decisions.
- **Stage:** Idea. Nothing has been built, and no drivers have been interviewed yet.

---

## 1. Overview

A mobile app that lets truck drivers **record their trips like Strava**: tap **Start Trip** before rolling and **End Trip** when parked. Their career becomes something they're proud of and want to show off:

- a **career-miles counter** that starts at the driver's real lifetime number, entered at sign-up
- a **heatmap of US highways** they've driven
- **badges** for states and for ~20 legendary roads (Donner Pass, Cabbage Hill, the Grapevine, Monteagle, Eisenhower Tunnel and others)
- **repeatable goals** (yearly miles, monthly states, streaks) and milestones (100K → 1,000,000 miles)
- a **trip card** to share, with a small "Made with Million Miles" watermark

**One-line pitch:** "Strava for truckers: your miles, your map, your million."

**Decided by the founder:**
- **Launch on one platform first:** iPhone (reasons in section 4). Android follows once the iPhone version proves itself.
- **Manual tracking only.** Tracking runs only between Start Trip and End Trip. No always-on tracking and no automatic trip detection.
- **Free:** heatmap of the **last 30 days**. **Paid:** the **all-time map, with filters**.
- **No ads, no carrier or employer revenue, no year-end recap, no tax or compliance features.**

---

## 2. The user and the market

- **Who:** US truck drivers, mainly **long-haul (OTR)** drivers who are away for weeks and live in the truck. There are ~3.5M US truck drivers in total, roughly 2M of them heavy tractor-trailer drivers (approximate).
- **Why they'd care:** the work is invisible and thankless, but the pride culture is strong. Carriers give million-mile safe-driving awards, and drivers post odometer milestones on TikTok and YouTube.
- **Phone use while driving:** holding a phone while driving a commercial truck is banned by federal rules, and reading a device counts as texting. **Start Trip is tapped while parked, before rolling. End Trip is tapped after parking.** Siri voice commands ("Hey Siri, start trip") are available.
- **Trust:** company drivers already carry an employer-run electronic logging device (ELD) and dislike being watched. Phone GPS can be subpoenaed after a crash.

**Competition:**
- **Driver Tracer** (iPhone): logs trips automatically, with achievements, 17 driver ranks, and leaderboards showing truck drivers' company names. It's aimed at drivers in general, and its Product Hunt launch got 0 upvotes, so traction looks minimal.
- Fleet gamification (Samsara, Geotab's d2go, Azuga) is run by the employer.
- Generic travel maps (Places Been, GeoRecords) have no trucker identity.
- Trucker Path has a large user base and could copy the feature.
- **Our difference:** made only for truckers (road badges, million-mile culture), private by design (no rankings, no employer, nothing shared unless the driver chooses), and creator-led launch.

---

## 3. Product: version 1 scope (iPhone)

### Recording (free)
1. **Onboarding:** enter career miles (self-reported, optional odometer photo), years driving, and states driven so far (tap on a map).
2. **Start Trip / End Trip**, like Strava:
   - One big Start button, plus a Siri shortcut and a lock-screen widget.
   - While recording: a Live Activity on the lock screen showing only the elapsed miles, readable at a glance, with **nothing that needs a tap**.
   - **If the driver forgets to tap End:** when the truck has been stationary for 60+ minutes, the trip auto-pauses. After 10 hours stationary (a full rest break) it auto-ends, and the driver can adjust the end point afterward.
   - **If the driver forgets to tap Start:** a gentle reminder **only when the truck has been parked** ("Start your trip before rolling?"), based on a driver-chosen schedule. No automatic detection.
   - **Team drivers:** only the person who taps Start records. Pairing two phones is a v2 feature.
3. **Map:** simplified GPS lines (no map-matching server), shown as a heatmap.
4. **Badges:** states worked out on the phone from bundled boundary maps. Legendary roads detected by passing entry and exit points. **Awarded silently; the alert appears only after End Trip.**
5. **Repeatable goals:** yearly mileage goal, "new states this month," a weekly driving streak, seasonal roads (for example, a winter mountain passes collection). These keep the app worth opening once the lifetime map fills in.
6. **Trip card:** after End Trip, a shareable card with states, highways, miles and badges, watermarked. The driver previews and chooses whether to share each card.

### Free vs. Pro
| Free | Pro (~$14.99 one-time) |
|---|---|
| Unlimited trip recording | **All-time map** |
| **Heatmap of the last 30 days** | **Filters:** by year, month or date range, by state, by highway, by badge or legendary road, by trip |
| Career counter, milestones, all badges, goals | Full trip history and statistics |
| Trip cards with watermark | High-res cards without watermark, extra card themes |
| | "Experience résumé" view (states, roads, years), exported as a PDF the driver controls |

Physical prints of the map (posters, plaques) are an **optional v1.1 add-on**, made by a print-on-demand service.

### Privacy and safety rules (not negotiable)
- **No notifications or interactions needed while moving.** Everything appears after End Trip.
- **No rankings, no leaderboards, no speed shown.** Raw GPS points are turned into highway segments after each trip. **Speed and time of day are not stored; only the date is kept.**
- **Trimmed routes:** the first and last ~5 miles of each trip, **plus a radius around every stop over 30 minutes**, are removed from the stored route and from cards.
- **Data stays on the phone and is encrypted.** An **optional encrypted iCloud backup** that the driver controls. Wipe all data with one tap.
- **Privacy policy and the App Store privacy label are written before the beta.**
- Nothing is ever shared with employers. No account is needed in v1.

### Out of scope for v1
- Android (next platform)
- Social feed, followers, "honks" (tap-to-cheer reactions), clubs
- Automatic trip detection, always-on location
- Leaderboards, ads, tax and compliance features, carrier products, year-end recap
- Navigation, parking, load boards, ELD integration

---

## 4. Technical approach

- **Why iPhone first:**
  - background recording during a trip the user has started is reliable on iPhone
  - fewer device makers to test (Android brands kill background apps unpredictably)
  - iPhone users buy in-app upgrades more often
  - the founder's original target
  - **Android comes next** once the pilot and launch prove that drivers keep using it.
- **Build:** native SwiftUI, or React Native/Expo if Android will reuse the code soon. Founder to choose.
- **Location while recording:** a session the user starts, with **"While Using" permission only** (no "Always"), background location mode, and the blue location indicator.
  - Accuracy ~50–100 m, distance filter ~100–200 m.
  - Accuracy goes up while charging (phones are usually on a cab charger).
  - Tunnels and dead zones: fill gaps in between known points.
  - **No Always permission makes App Review simpler.**
- **No backend in v1:** RevenueCat for in-app purchases, crash reporting, and print-on-demand via a web link in v1.1.

---

## 5. Monetization (no ads, no carriers)

1. **Pro unlock**, ~$14.99 one-time. Run a price test at $9.99 / $14.99 / $24.99.
2. **Physical prints** (v1.1): map posters or canvas (~$30–60), metal milestone plaques (~$40–80). Often bought by **family as gifts** (Christmas, Father's/Mother's Day, retirements, Truck Driver Appreciation Week in September).

**Bottom-up year-one model (iPhone only). Assumptions to be replaced with pilot data.**

| | Downside | Base | Upside |
|---|---|---|---|
| Creator views | 1M | 3M | 8M |
| View → install | 1% | 1% | 1% |
| **Installs** | **10K** | **30K** | **80K** |
| Pro conversion | 2% | 3% | 4% |
| Pro revenue (net ~$12.74) | ~$2.5K | ~$11.5K | ~$41K |
| Prints (0.5% of installs, ~$18 profit) | ~$1K | ~$2.7K | ~$7K |
| Creator costs | –$3K | –$8K | –$15K |
| **Net** | **~$0.5K** | **~$6K** | **~$33K** |

**Honest read:** as a one-time-purchase niche app, iPhone-only year one is a **side-project-sized business** unless the upside case happens. Android, prints and a growing base of installs are the levers. Whether this is worth doing depends on the pilot's retention and purchase data.

---

## 6. Go-to-market

- **Creators first:** 10–20 trucker creators on TikTok and YouTube, set up before launch (free Pro, paid posts, or a revenue share).
- **The demo:** tap Start before a mountain pass → End → a "Donner Pass conquered" badge, and the career counter rolling up.
- **Trucker-family Facebook groups** for prints and gifts.
- **QR code flyers** at big truck stops.

---

## 7. Validation before building the full app

1. **Search the App Store and Google Play by hand** for look-alikes (30 minutes).
2. **Talk to 10–15 drivers at a truck stop:** career miles, whether they'd tap Start and End every day, what they'd pay, "would you open this in week 6?"
3. **4-week pilot:** a throwaway iPhone prototype that only does Start/End, a map and badges (TestFlight, ~20 drivers recruited through creators and truck stops).
   - Gate: ≥70% of driving days have a recorded trip (are they remembering to tap Start?)
   - Gate: ≥40% of drivers still recording weekly in week 4
   - Gate: ≥15% click Pro in a **fake-door price test** (the price is shown, no money is taken)
   - Gate: battery and recording reliability (≥95% of started trips recorded completely)
4. **Go / no-go:** pass all four gates. Otherwise change course (for example, add auto-detection or a different hook) or stop.

---

## 8. Timeline (1–2 people)

| Weeks | Work |
|---|---|
| 1 | App Store search, truck-stop interviews |
| 2–3 | Build the throwaway prototype |
| 4–7 | Pilot (4 weeks) |
| 8 | Go/no-go decision |
| 9–16 | Build v1 (iPhone), privacy policy, App Store submission |
| 17–18 | Launch with creators |
| +2–3 months | Prints (v1.1), Android, then social features |

**About 4–5 months to launch.**

---

## 9. Key risks and open questions

1. **Will drivers remember to tap Start every day?** This is now the riskiest assumption. Strava users are hobbyists who choose to record. Truckers would be recording a job, every day.
2. **Does manual tracking make the map feel incomplete** when drivers forget days, so they lose the motivation to keep it going?
3. **Will people keep using it** with no social features?
4. **Will $14.99 sell?** Is the all-time map with filters valuable enough to pay for?
5. **Copycats:** Trucker Path or Driver Tracer adding trucker badges.
6. **Credibility:** career miles are self-reported and there's no verification.
