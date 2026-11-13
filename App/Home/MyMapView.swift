import SwiftUI
import RoadPrintCore

/// One processed trip: as much of it as the heat map and its filters need.
struct HeatTrip: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let distanceMeters: Double
    let segments: [RouteSegment]
    let regions: [PlaceRef]
    let countries: [PlaceRef]
    /// "I-80", "E67": the trip's main road, when it is known.
    let road: String?
}

extension HeatTrip {
    /// Nil for a trip that is still recording or isn't processed yet.
    init?(_ trip: Trip) {
        guard trip.status != .recording, let route = trip.route else { return nil }
        self.init(id: trip.id, date: trip.startedAt ?? trip.createdAt,
                  distanceMeters: trip.summary?.distanceMeters ?? 0,
                  segments: route.segments.filter { $0.points.count > 1 },
                  regions: trip.places?.regions ?? [], countries: trip.places?.countries ?? [],
                  road: trip.mainRoad.map(ShareCardText.roadName))
    }
}

/// What "My map" shows.
struct MapFilter: Equatable, Sendable {
    enum Period: Hashable, Sendable { case last30Days, allTime }

    var period: Period = .allTime
    /// Only with `allTime`.
    var year: Int?
    /// A region or country code.
    var placeCode: String?
    var road: String?

    var isNarrowed: Bool { (period == .allTime && year != nil) || placeCode != nil || road != nil }
}

enum MyMapLogic {
    static func filtered(_ trips: [HeatTrip], by filter: MapFilter, now: Date, calendar: Calendar = .current) -> [HeatTrip] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        return trips.filter { trip in
            switch filter.period {
            case .last30Days:
                if trip.date < cutoff { return false }
            case .allTime:
                if let year = filter.year, calendar.component(.year, from: trip.date) != year { return false }
            }
            if let code = filter.placeCode, !(trip.regions + trip.countries).contains(where: { $0.code == code }) {
                return false
            }
            if let road = filter.road, trip.road != road { return false }
            return true
        }
    }

    /// Newest first.
    static func years(_ trips: [HeatTrip], calendar: Calendar = .current) -> [Int] {
        Set(trips.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }

    private static func distinct(_ refs: [PlaceRef]) -> [PlaceRef] {
        var seen = Set<String>()
        return refs.filter { seen.insert($0.code).inserted }
    }

    /// The countries when the trips cross more than one, otherwise the regions. By name.
    static func places(_ trips: [HeatTrip]) -> [PlaceRef] {
        let countries = distinct(trips.flatMap(\.countries))
        let refs = countries.count > 1 ? countries : distinct(trips.flatMap(\.regions))
        return refs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func roads(_ trips: [HeatTrip]) -> [String] {
        Set(trips.compactMap(\.road)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// (38, "states"): what the trips cross, with the right word.
    static func placeCount(_ trips: [HeatTrip]) -> (count: Int, noun: String)? {
        ShareCardText.placeCount(TripPlaces(countries: distinct(trips.flatMap(\.countries)),
                                            regions: distinct(trips.flatMap(\.regions))))
    }

    /// "1–2", "3–5", "6–9", "10–14", "15+".
    static func legendLabel(level: Int) -> String {
        let floors = HeatMap.levelFloors
        guard floors.indices.contains(level - 1) else { return "" }
        return level < floors.count ? "\(floors[level - 1])–\(floors[level] - 1)" : "\(floors[level - 1])+"
    }
}

/// The Map tab (SCREENS.md "My map", plan §4.5, mockup 3): every trip on one map, hotter where
/// the driver goes more often, with filters. The Pro lock on "All time" and the filters comes with M6.
struct MyMapView: View {
    let model: RecordingModel

    @Environment(\.appEnvironment) private var environment
    @State private var trips: [HeatTrip]?

    var body: some View {
        MyMapScreen(trips: trips, unit: environment.profile.distanceUnit)
            // The list changes when a trip is recorded or deleted.
            .task(id: model.rows) {
                let stored = (try? await environment.tripStore.allTrips()) ?? []
                trips = stored.compactMap { HeatTrip($0) }
            }
    }
}

struct MyMapScreen: View {
    /// Nil while loading.
    let trips: [HeatTrip]?
    let unit: DistanceUnit

    @State private var filter = MapFilter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.l) {
                VStack(alignment: .leading, spacing: RPSpace.xs) {
                    Text("My map").font(RPType.screenTitle)
                    Text(subtitle)
                        .font(RPType.subtitle)
                        .foregroundStyle(Color.RP.textSecondary)
                }
                if let trips {
                    if trips.isEmpty {
                        Text("Your map fills in as you drive. Every trip you record is drawn here, and the roads you drive most glow brightest.")
                            .font(RPType.body)
                            .foregroundStyle(Color.RP.textSecondary)
                            .accessibilityIdentifier("mapEmpty")
                    } else {
                        content(trips)
                    }
                }
            }
            .padding(RPSpace.screenMargin)
            .padding(.bottom, RPSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.RP.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func content(_ trips: [HeatTrip]) -> some View {
        let shown = MyMapLogic.filtered(trips, by: filter, now: Date())
        Picker("Period", selection: $filter.period) {
            Text("Last 30 days").tag(MapFilter.Period.last30Days)
            Text("All time").tag(MapFilter.Period.allTime)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("mapPeriod")
        chips(trips)
        if shown.isEmpty {
            VStack(alignment: .leading, spacing: RPSpace.m) {
                Text("No trips match.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)
                    .accessibilityIdentifier("mapNoMatch")
                if filter.isNarrowed {
                    Button("Clear filters") {
                        filter.year = nil
                        filter.placeCode = nil
                        filter.road = nil
                    }
                    .buttonStyle(.rpSecondary)
                }
            }
            .padding(.vertical, RPSpace.xl)
        } else {
            HeatMapView(trips: shown)
                .aspectRatio(1.05, contentMode: .fit)
                // The map runs edge to edge.
                .padding(.horizontal, -RPSpace.screenMargin)
            legend
            stats(shown)
        }
    }

    private var subtitle: String {
        guard let trips, !trips.isEmpty else {
            return String(localized: "Every road you drive, on one map.")
        }
        var parts: [String] = []
        if let code = filter.placeCode, let place = MyMapLogic.places(trips).first(where: { $0.code == code }) {
            parts.append(place.name)
        }
        if let road = filter.road { parts.append(road) }
        if filter.period == .allTime, let year = filter.year { parts.append(String(year)) }
        if !parts.isEmpty {
            return String(localized: "Filtered: \(parts.joined(separator: " · "))",
                          comment: "My map subtitle; the placeholder lists the filters, e.g. California · 2026.")
        }
        switch filter.period {
        case .last30Days:
            return String(localized: "Your last 30 days of trips")
        case .allTime:
            guard let first = trips.map(\.date).min() else { return "" }
            return String(localized: "Every recorded trip since \(first.formatted(.dateTime.month(.abbreviated).year()))",
                          comment: "My map subtitle; the placeholder is a month and year, e.g. Jan 2025.")
        }
    }

    // MARK: Filters

    private func chips(_ trips: [HeatTrip]) -> some View {
        let places = MyMapLogic.places(trips), roads = MyMapLogic.roads(trips)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RPSpace.s) {
                if filter.period == .allTime {
                    chip(filter.year.map { String($0) } ?? String(localized: "All years"),
                         active: filter.year != nil, identifier: "mapYearFilter") {
                        Picker("Year", selection: $filter.year) {
                            Text("All years").tag(Int?.none)
                            ForEach(MyMapLogic.years(trips), id: \.self) { year in
                                Text(verbatim: String(year)).tag(Int?.some(year))
                            }
                        }
                    }
                }
                if !places.isEmpty {
                    chip(places.first { $0.code == filter.placeCode }?.name ?? String(localized: "All places"),
                         active: filter.placeCode != nil, identifier: "mapPlaceFilter") {
                        Picker("Place", selection: $filter.placeCode) {
                            Text("All places").tag(String?.none)
                            ForEach(places, id: \.code) { place in
                                Text(verbatim: place.name).tag(String?.some(place.code))
                            }
                        }
                    }
                }
                if !roads.isEmpty {
                    chip(filter.road ?? String(localized: "All roads"),
                         active: filter.road != nil, identifier: "mapRoadFilter") {
                        Picker("Road", selection: $filter.road) {
                            Text("All roads").tag(String?.none)
                            ForEach(roads, id: \.self) { road in
                                Text(verbatim: road).tag(String?.some(road))
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip<Options: View>(_ title: String, active: Bool, identifier: String,
                                     @ViewBuilder options: () -> Options) -> some View {
        Menu {
            options()
        } label: {
            HStack(spacing: RPSpace.xs) {
                Text(verbatim: title)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(RPType.body)
            .foregroundStyle(active ? Color.RP.accentText : Color.RP.text)
            .padding(.horizontal, RPSpace.m)
            .padding(.vertical, RPSpace.s)
            .background(Color.RP.card, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.RP.accentText : Color.RP.border, lineWidth: 1))
            .frame(minHeight: RPSize.minTouch)
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: Legend and totals

    private var legend: some View {
        VStack(alignment: .leading, spacing: RPSpace.s) {
            Text("Times driven")
                .font(RPType.statLabel)
                .foregroundStyle(Color.RP.textSecondary)
            HStack(alignment: .top, spacing: RPSpace.xs) {
                ForEach(1...HeatMap.levelFloors.count, id: \.self) { level in
                    VStack(spacing: RPSpace.xs) {
                        Capsule()
                            .fill(HeatMapArt.color(level))
                            .frame(height: 6)
                        Text(verbatim: MyMapLogic.legendLabel(level: level))
                            .font(RPType.axis)
                            .foregroundStyle(Color.RP.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stats(_ shown: [HeatTrip]) -> some View {
        let distance = ShareCardText.distance(meters: shown.reduce(0) { $0 + $1.distanceMeters }, unit: unit)
        let places = MyMapLogic.placeCount(shown)
        return HStack(alignment: .top, spacing: RPSpace.l) {
            stat(distance.value, distance.unit, identifier: "mapDistance")
            if let places { stat(places.count.formatted(), places.noun, identifier: "mapPlaces") }
            stat(shown.count.formatted(),
                 shown.count == 1 ? String(localized: "trip", comment: "My map: after the number 1.")
                                  : String(localized: "trips", comment: "My map: after a number, e.g. 14 trips."),
                 identifier: "mapTrips")
        }
        .padding(.top, RPSpace.s)
    }

    private func stat(_ value: String, _ label: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.xs) {
            Text(verbatim: value)
                .font(RPType.statNumber)
                .contentTransition(.numericText())
            Text(verbatim: label)
                .font(RPType.statLabel)
                .foregroundStyle(Color.RP.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The trips' routes on RoadPrint's own map, coloured by how often each stretch was driven.
/// Static art, like the trip map: no pan or zoom yet.
struct HeatMapView: View {
    let trips: [HeatTrip]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        /// Trips too short to draw as routes.
        case nothing
        case ready(MapScene, [Int])
    }

    private struct Key: Equatable {
        let trips: [UUID]
        let size: CGSize
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.RP.background
                switch phase {
                case .loading:
                    ProgressView()
                case .nothing:
                    Text("These trips are too short to draw as routes.")
                        .font(RPType.body)
                        .foregroundStyle(Color.RP.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(RPSpace.xl)
                case .ready(let scene, let levels):
                    canvas(scene, levels)
                }
            }
            .task(id: Key(trips: trips.map(\.id), size: proxy.size)) { await build(size: proxy.size) }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map of your trips"))
        .accessibilityIdentifier("heatMap")
    }

    private func canvas(_ scene: MapScene, _ levels: [Int]) -> some View {
        var base = MapSceneRenderer(scene: scene, scheme: scheme, displayScale: displayScale,
                                    summitName: "", summitAltitude: "")
        base.only = [.landFill, .regionBorders, .countryBorders, .labels]
        let renderer = base, glow = RPTheme.draw(for: scheme).routeGlow
        return Canvas { context, _ in
            renderer.draw(&context)
            HeatMapArt.draw(scene, levels: levels, glow: glow, in: &context)
        }
    }

    private func build(size: CGSize) async {
        guard size.width > 100, size.height > 100 else { return }
        let routes = trips.map(\.segments)
        let width = Double(size.width), height = Double(size.height)
        let built = await Task.detached(priority: .userInitiated) { () -> (MapScene, [Int])? in
            let heat = HeatMap.make(routes: routes)
            guard !heat.runs.isEmpty, let places = try? PlaceIndex.bundled() else { return nil }
            var input = MapSceneInput(segments: heat.runs.map { RouteSegment(points: $0.points) })
            input.connectsSegments = false
            guard let scene = try? MapSceneBuilder.build(
                input: input, places: places, size: (width, height),
                insets: ViewportInsets(top: 20, left: 16, bottom: 20, right: 16)) else { return nil }
            return (scene, heat.runs.map(\.level))
        }.value
        guard !Task.isCancelled else { return }
        phase = built.map { .ready($0.0, $0.1) } ?? .nothing
    }
}

/// Canvas drawing for the heat map. Not a view: Canvas closures run off the main actor.
enum HeatMapArt {
    static func color(_ level: Int) -> Color {
        switch level {
        case ...1: Color.RP.heat1
        case 2: Color.RP.heat2
        case 3: Color.RP.heat3
        case 4: Color.RP.heat4
        default: Color.RP.heat5
        }
    }

    /// Hotter roads are thicker as well as brighter.
    static func width(_ level: Int) -> CGFloat {
        1.8 + 0.5 * CGFloat(min(max(level, 1), 5))
    }

    /// `levels[i]` belongs to the scene's i-th recorded route.
    static func draw(_ scene: MapScene, levels: [Int], glow: Bool, in context: inout GraphicsContext) {
        let lines = zip(scene.routes.filter { $0.kind == .recorded }, levels).map { (ShareCardArt.path($0.points), $1) }
        guard !lines.isEmpty else { return }
        if glow {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.opacity = 0.55
                for (path, level) in lines {
                    layer.stroke(path, with: .color(color(level)),
                                 style: StrokeStyle(lineWidth: width(level) * 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
        for (path, level) in lines {
            context.stroke(path, with: .color(color(level)),
                           style: StrokeStyle(lineWidth: width(level), lineCap: .round, lineJoin: .round))
        }
    }
}

#if DEBUG
/// DEBUG-only: "My map" on made-up trips along the I-80 fixture, some stretches driven more often,
/// so every heat level shows. Launch with `-RPHeatFixture i80`.
struct HeatDebugView: View {
    let fixture: String
    /// Made once: the trips get new ids every time they are built.
    @State private var trips: [HeatTrip]?

    var body: some View {
        MyMapScreen(trips: trips, unit: .miles)
            .task { trips = Self.trips(fixture: fixture) }
    }

    static func trips(fixture: String) -> [HeatTrip] {
        guard let points = MapDebugView.input(fixture: fixture)?.segments.first?.points, points.count > 20 else { return [] }
        let utah = PlaceRef(code: "US-UT", name: "Utah"), nevada = PlaceRef(code: "US-NV", name: "Nevada")
        let california = PlaceRef(code: "US-CA", name: "California")
        let usa = PlaceRef(code: "US", name: "United States of America")
        // (from, to, how many trips): shares of the route, from Salt Lake City to Sacramento.
        let plan: [(Double, Double, Int)] = [(0, 1, 2), (0, 0.6, 2), (0.2, 0.55, 4), (0.26, 0.45, 4), (0.3, 0.38, 5)]
        var trips: [HeatTrip] = []
        for (from, to, count) in plan {
            let slice = Array(points[Int(from * Double(points.count - 1))...Int(to * Double(points.count - 1))])
            let meters = zip(slice, slice.dropFirst()).reduce(0) { $0 + Geo.distance(from: $1.0, to: $1.1) }
            for _ in 0..<count {
                let index = trips.count
                trips.append(HeatTrip(
                    id: UUID(), date: Date().addingTimeInterval(-Double(index) * 23 * 86_400),
                    distanceMeters: meters, segments: [RouteSegment(points: slice)],
                    regions: to > 0.8 ? [utah, nevada, california] : [utah, nevada], countries: [usa],
                    road: index % 5 == 4 ? "US-50" : "I-80"))
            }
        }
        return trips
    }
}
#endif
