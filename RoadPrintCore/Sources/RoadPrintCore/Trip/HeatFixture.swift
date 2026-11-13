import Foundation

/// Made-up trips over a made-up road network between real cities, for testing the heat map with
/// 5 to 500 trips. Every drive between two cities follows the same road (plus a few metres of GPS
/// noise), and busy cities are picked more often, so some roads get driven dozens of times, as in
/// a real driver's history. Used by the tests and, TEMPORARILY, by the app's test tool
/// ("Sample maps"); take it out of the app with that tool.
public enum HeatFixture {
    public enum Area: String, Sendable, CaseIterable {
        case usa, europe, mixed
    }

    public struct Trip: Sendable, Equatable {
        public var segments: [RouteSegment]
        public var regions: [PlaceRef]
        public var countries: [PlaceRef]
        public var distanceMeters: Double
        public var daysAgo: Int
    }

    struct City: Sendable {
        var name: String
        var region: PlaceRef
        var country: PlaceRef
        var latitude: Double
        var longitude: Double
        var weight: Int
    }

    /// The same `area`, `count` and `seed` always give the same trips.
    public static func trips(_ area: Area, count: Int, seed: UInt64 = 7) -> [Trip] {
        switch area {
        case .usa: return trips(cities: usa, count: count, seed: seed)
        case .europe: return trips(cities: europe, count: count, seed: seed)
        case .mixed:
            let abroad = count * 2 / 5
            return trips(cities: europe, count: count - abroad, seed: seed)
                + trips(cities: usa, count: abroad, seed: seed &+ 1)
        }
    }

    // MARK: Random numbers

    struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        /// 0..<1
        mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
    }

    // MARK: Roads

    private static func distance(_ a: City, _ b: City) -> Double {
        Geo.distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    /// Each city is joined to its three nearest, and loose groups are joined by their closest pair.
    static func roads(_ cities: [City]) -> [[Int]] {
        var links = [Set<Int>](repeating: [], count: cities.count)
        for a in cities.indices {
            let nearest = cities.indices.filter { $0 != a }
                .sorted { distance(cities[a], cities[$0]) < distance(cities[a], cities[$1]) }
            for b in nearest.prefix(3) { links[a].insert(b); links[b].insert(a) }
        }
        while true {
            var group = [Int](repeating: -1, count: cities.count)
            var queue = [0]
            group[0] = 0
            while let a = queue.popLast() {
                for b in links[a] where group[b] < 0 { group[b] = 0; queue.append(b) }
            }
            guard let _ = group.firstIndex(of: -1) else { break }
            var best = (a: 0, b: 0, d: Double.infinity)
            for a in cities.indices where group[a] == 0 {
                for b in cities.indices where group[b] < 0 {
                    let d = distance(cities[a], cities[b])
                    if d < best.d { best = (a, b, d) }
                }
            }
            links[best.a].insert(best.b)
            links[best.b].insert(best.a)
        }
        return links.map { $0.sorted() }
    }

    /// The road from the lower-numbered city to the higher: a line with gentle bends that depend
    /// only on the two cities, so every trip over it takes the same path.
    static func road(_ cities: [City], _ low: Int, _ high: Int) -> [RoutePoint] {
        let a = cities[low], b = cities[high]
        let length = distance(a, b)
        let steps = max(4, Int(length / 4_000))
        let dLat = b.latitude - a.latitude, dLon = b.longitude - a.longitude
        let cosLat = max(cos((a.latitude + b.latitude) / 2 * .pi / 180), 0.05)
        // A unit vector across the road, in degrees of latitude and longitude.
        let alongNorth = dLat * 110_574, alongEast = dLon * 111_320 * cosLat
        let norm = max(hypot(alongNorth, alongEast), 1)
        let acrossNorth = -alongEast / norm, acrossEast = alongNorth / norm
        let amplitude = min(length * 0.03, 9_000)
        let slow = max(1, (length / 120_000).rounded()), quick = max(2, (length / 45_000).rounded())
        let phase1 = Double((low * 37 + high * 101) % 628) / 100, phase2 = Double((low * 53 + high * 71) % 628) / 100
        return (0...steps).map { index in
            let t = Double(index) / Double(steps)
            let wave = 0.8 * sin(2 * .pi * slow * t + phase1) + 0.2 * sin(2 * .pi * quick * t + phase2)
            let offset = amplitude * sin(.pi * t) * wave
            return RoutePoint(latitude: a.latitude + dLat * t + offset * acrossNorth / 110_574,
                              longitude: a.longitude + dLon * t + offset * acrossEast / (111_320 * cosLat))
        }
    }

    /// Shortest way over the roads, as city numbers.
    static func path(_ cities: [City], _ links: [[Int]], from: Int, to: Int) -> [Int] {
        var best = [Double](repeating: .infinity, count: cities.count)
        var previous = [Int](repeating: -1, count: cities.count)
        var open = Set(cities.indices)
        best[from] = 0
        while let current = open.min(by: { best[$0] < best[$1] }), best[current].isFinite {
            if current == to { break }
            open.remove(current)
            for next in links[current] where open.contains(next) {
                let d = best[current] + distance(cities[current], cities[next])
                if d < best[next] { best[next] = d; previous[next] = current }
            }
        }
        var out = [to]
        while let last = out.last, last != from, previous[last] >= 0 { out.append(previous[last]) }
        return out.reversed()
    }

    static func trips(cities: [City], count: Int, seed: UInt64) -> [Trip] {
        guard count > 0, cities.count > 1 else { return [] }
        let links = roads(cities)
        var geometry: [Int: [RoutePoint]] = [:]
        func road(_ a: Int, _ b: Int) -> [RoutePoint] {
            let low = min(a, b), high = max(a, b), key = low * 1_000 + high
            let points = geometry[key] ?? HeatFixture.road(cities, low, high)
            geometry[key] = points
            return a == low ? points : points.reversed()
        }
        let lottery = cities.indices.flatMap { [Int](repeating: $0, count: cities[$0].weight) }
        var random = Generator(state: seed &* 2_654_435_761 &+ UInt64(count))
        var out: [Trip] = []
        while out.count < count {
            let from = lottery[Int(random.next() % UInt64(lottery.count))]
            let to = lottery[Int(random.next() % UInt64(lottery.count))]
            guard from != to else { continue }
            let stops = path(cities, links, from: from, to: to)
            guard stops.count > 1 else { continue }
            var points: [RoutePoint] = []
            for (a, b) in zip(stops, stops.dropFirst()) {
                let leg = road(a, b)
                points.append(contentsOf: points.isEmpty ? leg : Array(leg.dropFirst()))
            }
            // A few metres of GPS noise: no two recordings of one road are identical.
            let noisy = points.map {
                RoutePoint(latitude: $0.latitude + (random.unit() - 0.5) * 0.000_2,
                           longitude: $0.longitude + (random.unit() - 0.5) * 0.000_3)
            }
            let meters = zip(noisy, noisy.dropFirst()).reduce(0.0) { $0 + Geo.distance(from: $1.0, to: $1.1) }
            var regions: [PlaceRef] = [], countries: [PlaceRef] = []
            for stop in stops {
                if !regions.contains(cities[stop].region) { regions.append(cities[stop].region) }
                if !countries.contains(cities[stop].country) { countries.append(cities[stop].country) }
            }
            out.append(Trip(segments: [RouteSegment(points: noisy)], regions: regions, countries: countries,
                            distanceMeters: meters, daysAgo: Int(random.next() % 700)))
        }
        return out
    }

    // MARK: Cities

    private static let unitedStates = PlaceRef(code: "US", name: "United States of America")

    private static func us(_ name: String, _ code: String, _ state: String, _ lat: Double, _ lon: Double, _ weight: Int) -> City {
        City(name: name, region: PlaceRef(code: "US-" + code, name: state), country: unitedStates,
             latitude: lat, longitude: lon, weight: weight)
    }

    private static func eu(_ name: String, _ code: String, _ country: String, _ lat: Double, _ lon: Double, _ weight: Int) -> City {
        // One region per city is enough for the place filter.
        City(name: name, region: PlaceRef(code: code + "-" + String(name.prefix(3)).uppercased(), name: name),
             country: PlaceRef(code: code, name: country), latitude: lat, longitude: lon, weight: weight)
    }

    static let usa: [City] = [
        us("Chicago", "IL", "Illinois", 41.88, -87.63, 9), us("Indianapolis", "IN", "Indiana", 39.77, -86.16, 4),
        us("Columbus", "OH", "Ohio", 39.96, -83.00, 3), us("Pittsburgh", "PA", "Pennsylvania", 40.44, -80.00, 2),
        us("New York", "NY", "New York", 40.71, -74.01, 5), us("Charlotte", "NC", "North Carolina", 35.23, -80.84, 3),
        us("Atlanta", "GA", "Georgia", 33.75, -84.39, 6), us("Nashville", "TN", "Tennessee", 36.16, -86.78, 4),
        us("Memphis", "TN", "Tennessee", 35.15, -90.05, 4), us("St. Louis", "MO", "Missouri", 38.63, -90.20, 5),
        us("Kansas City", "MO", "Missouri", 39.10, -94.58, 5), us("Dallas", "TX", "Texas", 32.78, -96.80, 7),
        us("Houston", "TX", "Texas", 29.76, -95.37, 4), us("San Antonio", "TX", "Texas", 29.42, -98.49, 2),
        us("Oklahoma City", "OK", "Oklahoma", 35.47, -97.52, 4), us("Denver", "CO", "Colorado", 39.74, -104.99, 5),
        us("Omaha", "NE", "Nebraska", 41.26, -95.93, 3), us("Minneapolis", "MN", "Minnesota", 44.98, -93.27, 3),
        us("Des Moines", "IA", "Iowa", 41.59, -93.62, 2), us("Salt Lake City", "UT", "Utah", 40.76, -111.89, 4),
        us("Las Vegas", "NV", "Nevada", 36.17, -115.14, 3), us("Los Angeles", "CA", "California", 34.05, -118.24, 6),
        us("Phoenix", "AZ", "Arizona", 33.45, -112.07, 3), us("Albuquerque", "NM", "New Mexico", 35.08, -106.65, 3),
        us("El Paso", "TX", "Texas", 31.76, -106.49, 2), us("Sacramento", "CA", "California", 38.58, -121.49, 3),
        us("Reno", "NV", "Nevada", 39.53, -119.81, 2), us("Portland", "OR", "Oregon", 45.52, -122.68, 2),
        us("Seattle", "WA", "Washington", 47.61, -122.33, 3), us("Boise", "ID", "Idaho", 43.62, -116.20, 2),
        us("Billings", "MT", "Montana", 45.78, -108.50, 1), us("Cheyenne", "WY", "Wyoming", 41.14, -104.82, 2),
        us("Jacksonville", "FL", "Florida", 30.33, -81.66, 2), us("Miami", "FL", "Florida", 25.76, -80.19, 2),
        us("New Orleans", "LA", "Louisiana", 29.95, -90.07, 2), us("Louisville", "KY", "Kentucky", 38.25, -85.76, 2),
        us("Detroit", "MI", "Michigan", 42.33, -83.05, 3), us("Cleveland", "OH", "Ohio", 41.50, -81.69, 2),
    ]

    static let europe: [City] = [
        eu("Kaunas", "LT", "Lithuania", 54.90, 23.90, 9), eu("Vilnius", "LT", "Lithuania", 54.69, 25.28, 5),
        eu("Klaipėda", "LT", "Lithuania", 55.71, 21.14, 4), eu("Riga", "LV", "Latvia", 56.95, 24.11, 4),
        eu("Tallinn", "EE", "Estonia", 59.44, 24.75, 2), eu("Warsaw", "PL", "Poland", 52.23, 21.01, 7),
        eu("Gdańsk", "PL", "Poland", 54.35, 18.65, 2), eu("Poznań", "PL", "Poland", 52.41, 16.93, 4),
        eu("Wrocław", "PL", "Poland", 51.11, 17.04, 3), eu("Kraków", "PL", "Poland", 50.06, 19.94, 2),
        eu("Berlin", "DE", "Germany", 52.52, 13.40, 6), eu("Hamburg", "DE", "Germany", 53.55, 9.99, 4),
        eu("Hannover", "DE", "Germany", 52.37, 9.73, 3), eu("Cologne", "DE", "Germany", 50.94, 6.96, 4),
        eu("Frankfurt", "DE", "Germany", 50.11, 8.68, 4), eu("Munich", "DE", "Germany", 48.14, 11.58, 4),
        eu("Nuremberg", "DE", "Germany", 49.45, 11.08, 2), eu("Prague", "CZ", "Czechia", 50.08, 14.44, 3),
        eu("Vienna", "AT", "Austria", 48.21, 16.37, 3), eu("Budapest", "HU", "Hungary", 47.50, 19.04, 2),
        eu("Bratislava", "SK", "Slovakia", 48.15, 17.11, 1), eu("Amsterdam", "NL", "Netherlands", 52.37, 4.90, 3),
        eu("Rotterdam", "NL", "Netherlands", 51.92, 4.48, 3), eu("Antwerp", "BE", "Belgium", 51.22, 4.40, 3),
        eu("Brussels", "BE", "Belgium", 50.85, 4.35, 2), eu("Paris", "FR", "France", 48.86, 2.35, 4),
        eu("Lyon", "FR", "France", 45.76, 4.84, 2), eu("Milan", "IT", "Italy", 45.46, 9.19, 3),
        eu("Verona", "IT", "Italy", 45.44, 10.99, 3), eu("Zurich", "CH", "Switzerland", 47.37, 8.54, 1),
        eu("Copenhagen", "DK", "Denmark", 55.68, 12.57, 2), eu("Innsbruck", "AT", "Austria", 47.27, 11.39, 2),
        eu("Bologna", "IT", "Italy", 44.49, 11.34, 1), eu("Barcelona", "ES", "Spain", 41.39, 2.17, 1),
        eu("Marseille", "FR", "France", 43.30, 5.37, 1),
    ]
}
