# Concept Brief: "Million Miles": a Strava-style app for US truck drivers

- **Author:** Elephant session (drafted with the founder)
- **Date:** 2026-11-06
- **Stage:** Idea. Nothing has been built, and no drivers have been interviewed yet.

---

## Overview

An iPhone app that **automatically logs every mile a truck driver drives** and turns that record into pride and something to share:

- a US map that fills in with every highway they've driven
- badges for states and for legendary roads (Donner Pass, Cabbage Hill, the Grapevine, Monteagle, Eisenhower Tunnel and others)
- a progress bar toward **1 million miles**, a real milestone in the industry
- a weekly shareable stats card, and **"Trucker Wrapped"**, a year-end recap in the style of Spotify Wrapped, every December

The same location data powers a paid tier aimed at **money**: nights away from home for the per-diem tax deduction, and miles per state for quarterly fuel-tax (IFTA) filing.

**One-line pitch:** "Strava for truckers: your miles, your map, your million."

**Founder's constraints:** 1–2 people, a first version in about 3–4 weeks, simple pricing (~$25/year), growth through trucker creators on TikTok and YouTube rather than App Store search.

---

## Analysis

### Inspiration: the "simple app" formula
Recent Starter Story case studies of small consumer apps share a pattern. The figures are self-reported and the sample suffers from survivorship bias.
- **Early**, an alarm you turn off by doing pushups: ~$50K/month, solo founder, 19 days to first version, grown through TikTok micro-influencers.
- **Cat on Chair**, a focus timer with a cartoon cat: ~$18K/month, two-person team, grown through Instagram creators.
- **ONCE**, a disposable-camera app: ~$20K/month, demand tested before any code was written.

The common traits: a familiar app category with one twist; a demo you understand from a 3-second video; marketing that starts before or during the build; tiny teams; $20–30/year pricing.

### Why Strava works
Strava (100M+ users) succeeds less on GPS tracking than on emotion: it makes invisible effort visible, gives recognition (kudos), builds identity, creates legends (segments and famous climbs), rewards progress (streaks, badges), produces shareable outputs (maps, Year in Sport), and tracks automatically.

**Strava's free/paid split:** everything that spreads the app is free (recording, feed, kudos, clubs, challenges, badges). Deeper analysis is paid (full leaderboards, personal heatmaps, training analytics, route building, full history), at about $11.99/month or $79.99/year in the US.

### The user
- About 3.5M US truck drivers. Long-haul (OTR) drivers are away for 2–3 weeks at a time, live in the truck, and spend an estimated 3–6 hours a day on their phone while off duty. Owner-operators (~350K) choose their own tools and pay for anything that saves money.
- The work is **invisible and thankless**, but the pride culture is strong: carriers hand out million-mile safe-driving awards, and drivers post odometer milestones on TikTok and YouTube.
- Holding a phone while driving a commercial truck is **banned by federal rules**, so all logging must be automatic, and the driver uses the app only while parked.
- Company drivers already carry an employer-run electronic logging device (ELD) that tracks them.
- Probably more Android-heavy than the US average. There's no hard data. This version is iOS-only.

### Competitive scan (desk research, Nov 2026)
**No direct "Strava for truckers" was found.** Small App Store apps can slip past web searches, so a manual App Store search is still needed. Adjacent products:
- **Fleet gamification** (Samsara, Geotab's d2go, Rocket Start, Azuga): points, badges and leaderboards for safe-driving scores. Employers run these, so to drivers they read as surveillance.
- **Visited**: colors in the states you've visited, but you fill it in by hand. Generic travel, not trucking.
- **Truck Maps Navigation**: logs trips, distance and driving time; no history map, badges or sharing.
- **Trucker Path**: mileage reports in its paid Diamond plan, presented as a utility.
- **TripLog** and similar: miles per state for fuel-tax filing. Pure compliance.

A fleet-industry lesson: drivers lose interest in leaderboards when they feel the scoring is unfair to their situation ("leaderboard apathy").

### Key assumptions (unvalidated)
1. Drivers want to **celebrate** their miles, not only get paid for them.
2. Drivers will allow **always-on location tracking** and accept the battery drain on their personal phone.
3. A filling map, badges and Wrapped are **satisfying for a single user**, before any social network exists.
4. Trucker creators will post about it, and the 3-second demo (the map filling in) earns organic shares.
5. Enough drivers will pay ~$25/year. 10,000 subscribers would be ~$250K/year, about 0.5% of long-haul drivers.
6. The tax exports are valuable enough to drive the paid conversion.

---

## Goals vs. Non-Goals

### In-scope goals (first version)
- Automatic detection and logging of driving trips in the background
- A US map that fills in with driven routes
- Badges: all 50 states, plus about 20 legendary roads (badges only, no times)
- Lifetime miles and progress toward 1 million
- A weekly shareable stats card
- **Private by default:** never shared with the employer; routes post only after delivery, with pickup and delivery locations blurred

### Out-of-scope non-goals
- Speed or time leaderboards of any kind (a safety and legal problem)
- Live location sharing (a cargo-theft risk)
- A social feed, clubs, comments (version two)
- Navigation, load boards, parking (incumbents own these)
- Integrating with fleet ELDs
- Android (later)

---

## Alternatives Weighed

| Alternative | Why it wasn't chosen first |
|---|---|
| **Detention Clock** (times the wait at shippers and generates an invoice) | Several apps already do this (Detention Source, DMRG Detention Pay, Detention Pay Tracker, WaitClaim, Trucker Tools). Drivers say their ELD already records the times. The real problem is getting paid, which a timer doesn't solve. |
| **Per Diem Meter** (a counter of deduction dollars) | Strong money hook, but thin on its own. It's folded into the paid tier here. |
| **Road Second** (a one-second daily clip, auto-edited) | The output is shareable content, but it depends on a daily habit. Kept as a backup idea. |
| **Cab Pet** (a cartoon pet that lives in your cab) | Emotional pull, but it's uncertain that drivers want something cute. It may sell to spouses instead. |
| **Generic travel map app** (Visited-style) | No automatic tracking and no trucker identity. |

---

## Key Decisions & Staging for Next Steps

**Pricing:**
- **Free:** automatic logging, state and road badges, a map of the current month, the weekly card.
- **Paid (~$25/year):** the lifetime map and heatmap, the full Wrapped with a poster export, the million-mile tracker with full history, tax exports (per-diem nights and miles per state for fuel tax).

**Staging:**
1. **Test demand (before any code):** make a fake demo video of the map filling in plus a Wrapped card. Post it on a fresh #truckertok account and send it to 5–10 trucker creators. Success signal: comments like "where do I download this?" or "does it run in the background?", not "why would I want this?"
2. **Search the App Store** by hand for existing look-alikes.
3. **Talk to 10 drivers** at a truck stop about tracking, privacy and willingness to pay.
4. **Build the first version** (3–4 weeks), then do a creator launch.
5. **Version two:** social features ("honks"), clubs, tax exports, Wrapped in December.

**Open questions:**
- How bad is the battery drain from always-on location on a personal iPhone over 11-hour driving days?
- Will Apple approve always-on location for this purpose?
- Is the per-diem and fuel-tax data accurate enough to rely on for taxes, or is it a liability risk?
- Who is the real buyer: the driver, or the family giving it as a gift?
