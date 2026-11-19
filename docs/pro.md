# RoadPrint Pro policy

[Product plan §8](plan/RoadPrint_Final_Plan.md#8-pricing) defines the free tier and Pro. The app maps RevenueCat's `pro` entitlement to the core `Entitlement` and uses `ProPolicy` for access and paywall decisions. RevenueCat supplies the subscription prices and offers at runtime.

| Feature | Free | Pro |
|---|---|---|
| My Map | Rolling last 30 days | All time |
| Map filters | Last 30 days only | Other periods, year, place and road |
| Trip cards | Night Highway with watermark | All styles, no watermark |

`filterHeatTrips` applies `heatWindow` to trip start dates (falling back to creation dates when needed) before choosing map areas, rendering routes or computing map totals. The free window includes both endpoints and spans exactly 30 × 24 hours across time zones. Pro has an unrestricted window. Both tiers keep their trips, including those that age out of Free My Map.

Pro and drivers with zero completed trips never see the paywall. For Free drivers with at least one completed trip, tapping All time, a locked filter or a locked card style can show it. Evaluate the automatic trigger only after successfully ending and saving a trip, using the completed-trip count after that save. When the count is exactly three and the prompt is shown, set `hasSeenPaywallAfterThirdTrip` in `AppSettings`. Launching the app and importing trips do not trigger the paywall. Tap-triggered presentations leave the flag alone. This flow adds no trip data.
