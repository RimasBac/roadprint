# RoadPrint Pro policy

[Product plan §8](plan/RoadPrint_Final_Plan.md#8-pricing) defines the free tier and Pro. The app maps RevenueCat's `pro` entitlement to the core `Entitlement` and uses `ProPolicy` for access and paywall decisions. RevenueCat supplies the subscription prices and offers at runtime.

| Feature | Free | Pro |
|---|---|---|
| My Map | Rolling last 30 days | All time |
| Map filters | Last 30 days only | Other periods, year, place and road |
| Trip cards | Picture in Night Highway and Road Atlas | Also as a video that draws the route |

Board decision, 2026-11-20: Pro is the all-time map (with its filters) and the video card. Recording, storage, the trip summary and picture cards in every style stay free. No watermark rule for now.

## App wiring (ROA-101)

`PurchaseService` (`App/Purchases/`) is the only code that knows a store. `RevenueCatPurchaseService` is used when the build setting `REVENUECAT_PUBLIC_KEY` (injected by CI, empty by default) is set; `StoreKitPurchaseService` is used otherwise, against `RoadPrint.storekit` in tests, and in a release without the key it buys the same App Store products through StoreKit 2 directly. The TestFlight lane passes the `REVENUECAT_PUBLIC_KEY` secret as a build setting. `ProStore` exposes `entitlement`, which views pass to `ProPolicy`. The Debug launch argument `-RPEntitlement pro|free` forces an entitlement for UI tests. The App Store product IDs are `com.rimasbac.roadprint.pro.yearly` and `.monthly` (ROA-99 must create the same IDs, and a RevenueCat offering with annual and monthly packages and the `pro` entitlement).

`filterHeatTrips` applies `heatWindow` to trip start dates (falling back to creation dates when needed) before choosing map areas, rendering routes or computing map totals. The free window includes both endpoints and spans exactly 30 × 24 hours across time zones. Pro has an unrestricted window. Both tiers keep their trips, including those that age out of Free My Map.

Pro and drivers with zero completed trips never see the paywall. For Free drivers with at least one completed trip, tapping All time, a locked filter or the Video format can show it. Evaluate the automatic trigger only after successfully ending and saving a trip, using the completed-trip count after that save. When the count is exactly three and the prompt is shown, set `hasSeenPaywallAfterThirdTrip` in `AppSettings`. Launching the app and importing trips do not trigger the paywall. Tap-triggered presentations leave the flag alone. This flow adds no trip data.
