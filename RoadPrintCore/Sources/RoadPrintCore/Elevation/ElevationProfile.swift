import Foundation

/// Unit of an axis tick. The app turns `(value, unit, isThousands)` into locale text
/// ("8k ft", "200 mi"); the core never formats strings.
public enum ProfileUnit: String, Sendable, Codable, Equatable {
    case mile, kilometer, foot, meter
}

/// One axis tick as structured values.
public struct ProfileTick: Sendable, Equatable {
    public var value: Double
    public var unit: ProfileUnit
    /// True when `value` is a non-zero multiple of 1,000, so the app may print "8k".
    public var isThousands: Bool

    public init(value: Double, unit: ProfileUnit) {
        self.value = value
        self.unit = unit
        self.isThousands = value != 0 && value.truncatingRemainder(dividingBy: 1000) == 0
    }
}

/// Data for the elevation chart on the trip summary.
///
/// Distances are measured along the trimmed route in metres and converted once, in display
/// units (mi and ft, or km and m). Privacy: it uses only the trimmed route a share summary
/// already contains; altitudes carry no time or speed.
public struct ElevationProfile: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        /// Distance along the route, in miles or kilometres.
        public var distance: Double
        /// Altitude, in feet or metres.
        public var altitude: Double
    }

    /// One series per continuous segment. A break between series is a recording gap:
    /// the chart must not draw a line across it.
    public var series: [[Sample]]
    /// Equals the route's summit; its altitude is `route.summit.altitude` converted, unfiltered.
    public var summit: Sample
    /// Chart x extent: the trip distance in display units (the stats row's number).
    public var totalDistance: Double
    /// `yTicks.first` and `yTicks.last`.
    public var yMin: Double
    public var yMax: Double
    public var xTicks: [ProfileTick]
    public var yTicks: [ProfileTick]
    public var distanceUnit: ProfileUnit
    public var altitudeUnit: ProfileUnit

    static let metersPerFoot = 0.3048
    static let minLengthMeters = 5000.0
    static let minValidSamples = 20
    static let minValidFraction = 0.5
    static let spikeWindow = 5
    static let validAltitudeRange = -1000.0...10_000.0
    static let endTickDropFraction = 0.15

    public static func make(
        route: ProcessedRoute, unit: DistanceUnit, tripDistanceMeters: Double? = nil, maxSamples: Int = 200
    ) -> ElevationProfile? {
        make(segments: route.segments, summit: route.summit, unit: unit,
             tripDistanceMeters: tripDistanceMeters, maxSamples: maxSamples)
    }

    /// - Parameters:
    ///   - tripDistanceMeters: the trip's displayed distance. The chart's x axis is stretched
    ///     to end exactly there (the trim removes a few hundred metres at each end), so the end
    ///     tick and the stats row can't disagree. Defaults to the measured route length.
    ///   - maxSamples: upper bound of the returned sample count.
    /// - Returns: nil when under 50 % of the points have a valid altitude, fewer than 20 do, or
    ///   the trimmed route is shorter than 5 km. The app then hides the chart.
    public static func make(
        segments: [RouteSegment], summit: RoutePoint?, unit: DistanceUnit,
        tripDistanceMeters: Double? = nil, maxSamples: Int = 200
    ) -> ElevationProfile? {
        // Cumulative distance per point, metres, with the straight line across a gap included.
        struct P { var seg: Int; var dist: Double; var alt: Double?; var lat: Double; var lon: Double }
        var all: [P] = []
        var length = 0.0
        var prev: RoutePoint?
        var totalPoints = 0
        for (s, segment) in segments.enumerated() {
            for pt in segment.points {
                if let prev { length += Geo.distance(from: prev, to: pt) }
                prev = pt
                totalPoints += 1
                let valid = pt.altitude.flatMap { $0.isFinite && validAltitudeRange.contains($0) ? $0 : nil }
                all.append(P(seg: s, dist: length, alt: valid, lat: pt.latitude, lon: pt.longitude))
            }
        }
        let validCount = all.reduce(0) { $0 + ($1.alt == nil ? 0 : 1) }
        guard length >= minLengthMeters, validCount >= minValidSamples,
              Double(validCount) >= minValidFraction * Double(totalPoints) else { return nil }

        // Keep samples with an altitude only.
        var pts = all.filter { $0.alt != nil }

        // Summit sample: the point nearest the route's summit. It is exempt from despiking.
        var summitIndex: Int
        if let summit {
            summitIndex = pts.indices.min { a, b in
                Geo.distance(lat1: pts[a].lat, lon1: pts[a].lon, lat2: summit.latitude, lon2: summit.longitude)
                    < Geo.distance(lat1: pts[b].lat, lon1: pts[b].lon, lat2: summit.latitude, lon2: summit.longitude)
            }!
        } else {
            summitIndex = 0
        }

        // 5-sample running median within each segment removes single-sample GPS spikes.
        var smoothed = pts.map { $0.alt! }
        var start = 0
        while start < pts.count {
            var end = start
            while end + 1 < pts.count, pts[end + 1].seg == pts[start].seg { end += 1 }
            for i in start...end {
                let lo = max(start, i - spikeWindow / 2), hi = min(end, i + spikeWindow / 2)
                let window = pts[lo...hi].map { $0.alt! }.sorted()
                smoothed[i] = window[window.count / 2]
            }
            start = end + 1
        }
        if let summit, let alt = summit.altitude, alt.isFinite {
            smoothed[summitIndex] = alt
        } else {
            summitIndex = smoothed.indices.max { smoothed[$0] < smoothed[$1] }!
        }
        for i in pts.indices { pts[i].alt = smoothed[i] }

        // Distances: metres → display units once, stretched to the trip distance.
        let displayMeters = tripDistanceMeters.flatMap { $0 > 0 ? $0 : nil } ?? length
        let stretch = displayMeters / length
        let altUnitIsFeet = unit == .miles
        func dist(_ m: Double) -> Double { unit.convert(meters: m * stretch) }
        func alt(_ m: Double) -> Double { altUnitIsFeet ? m / metersPerFoot : m }

        // Downsample: per distance bucket keep the minimum and maximum in their original order,
        // always keep the first, last, summit and each segment's ends.
        var reserved: Set<Int> = [summitIndex]
        for i in pts.indices {
            let startsSegment = i == 0 || pts[i - 1].seg != pts[i].seg
            let endsSegment = i == pts.count - 1 || pts[i + 1].seg != pts[i].seg
            if startsSegment || endsSegment { reserved.insert(i) }
        }
        var kept = Set(pts.indices)
        if pts.count > maxSamples {
            let cap = max(maxSamples, reserved.count)
            var buckets = max(1, (cap - reserved.count) / 2)
            while true {
                kept = reserved
                var best: [Int: (lo: Int, hi: Int)] = [:]
                for i in pts.indices {
                    let b = min(buckets - 1, Int(pts[i].dist / length * Double(buckets)))
                    if let cur = best[b] {
                        best[b] = (pts[i].alt! < pts[cur.lo].alt! ? i : cur.lo, pts[i].alt! > pts[cur.hi].alt! ? i : cur.hi)
                    } else {
                        best[b] = (i, i)
                    }
                }
                for (_, v) in best { kept.insert(v.lo); kept.insert(v.hi) }
                if kept.count <= cap || buckets == 1 { break }
                buckets = max(1, buckets - max(1, (kept.count - cap + 1) / 2))
            }
        }

        var series: [[Sample]] = []
        var lastSeg = -1
        for i in pts.indices.sorted() where kept.contains(i) {
            if pts[i].seg != lastSeg { series.append([]); lastSeg = pts[i].seg }
            series[series.count - 1].append(Sample(distance: dist(pts[i].dist), altitude: alt(pts[i].alt!)))
        }
        let summitSample = Sample(distance: dist(pts[summitIndex].dist), altitude: alt(pts[summitIndex].alt!))

        // The last sample sits at the trip's displayed distance.
        let totalDistance = unit.convert(meters: displayMeters)
        let lows = series.flatMap { $0 }.map(\.altitude)
        let yAxis = niceYAxis(min: lows.min() ?? 0, max: Swift.max(lows.max() ?? 0, summitSample.altitude))
        let distUnit: ProfileUnit = unit == .miles ? .mile : .kilometer
        let altUnit: ProfileUnit = altUnitIsFeet ? .foot : .meter
        return ElevationProfile(
            series: series, summit: summitSample, totalDistance: totalDistance,
            yMin: yAxis.first!, yMax: yAxis.last!,
            xTicks: xTicks(total: totalDistance).map { ProfileTick(value: $0, unit: distUnit) },
            yTicks: yAxis.map { ProfileTick(value: $0, unit: altUnit) },
            distanceUnit: distUnit, altitudeUnit: altUnit)
    }

    /// Y ticks: steps are 1, 2 or 5 × 10ⁿ. The chosen step is the smallest that gives 2 to 4
    /// ticks including the bottom, with the top tick at or above `max`. The bottom is 0, or
    /// the "nice" tick at or below the minimum when the route dips below sea level.
    static func niceYAxis(min lo: Double, max hi: Double) -> [Double] {
        for step in niceSteps() {
            let bottom = lo < 0 ? (lo / step).rounded(.down) * step : 0
            var top = (hi / step).rounded(.up) * step
            if top <= bottom { top = bottom + step }
            let n = Int(((top - bottom) / step).rounded()) + 1
            if n <= 4 { return (0..<n).map { bottom + Double($0) * step } }
        }
        return [0, hi]
    }

    /// X ticks: from 0 in a 1/2/5 × 10ⁿ step giving 3 or 4 regular ticks (fewest that fits), then
    /// the end distance. A last regular tick within 15 % of the end is dropped so labels don't collide.
    static func xTicks(total: Double) -> [Double] {
        var step = niceSteps().first { Int(total / $0) + 1 <= 4 } ?? total
        if step <= 0 { step = 1 }
        var ticks = (0...Int(total / step)).map { Double($0) * step }
        if ticks.count > 1, (total - ticks[ticks.count - 1]) / total < endTickDropFraction { ticks.removeLast() }
        if ticks.last.map({ abs($0 - total) > 1e-9 }) ?? true { ticks.append(total) }
        return ticks
    }

    private static func niceSteps() -> [Double] {
        (-3...9).flatMap { e in [1.0, 2.0, 5.0].map { $0 * pow(10, Double(e)) } }
    }
}
