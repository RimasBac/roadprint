import SwiftUI
import RoadPrintCore

/// A part of the world that fits one map. Trips in Europe and trips in America are never drawn on
/// one map: the lines would be specks on an ocean.
enum WorldArea: String, CaseIterable, Hashable, Sendable {
    case northAmerica, southAmerica, europe, africa, asia, oceania

    var name: String {
        switch self {
        case .northAmerica: String(localized: "North America", comment: "My map: part of the world.")
        case .southAmerica: String(localized: "South America", comment: "My map: part of the world.")
        case .europe: String(localized: "Europe", comment: "My map: part of the world.")
        case .africa: String(localized: "Africa", comment: "My map: part of the world.")
        case .asia: String(localized: "Asia", comment: "My map: part of the world.")
        case .oceania: String(localized: "Oceania", comment: "My map: part of the world.")
        }
    }

    /// Rough boxes: good enough to keep far-apart trips on separate maps.
    static func of(latitude: Double, longitude: Double) -> WorldArea {
        if longitude < -25 { return latitude >= 13 ? .northAmerica : .southAmerica }
        if longitude >= 110, latitude < 0 { return .oceania }
        if longitude >= 60 { return .asia }
        if latitude >= 36 { return .europe }
        if longitude >= 35, latitude >= 12 { return .asia }
        return .africa
    }
}

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
    /// Nil only for a trip with no position at all.
    let area: WorldArea?
}

extension HeatTrip {
    /// Nil for a trip that is still recording or isn't processed yet.
    init?(_ trip: Trip) {
        guard trip.status != .recording, let route = trip.route else { return nil }
        let segments = route.segments.filter { $0.points.count > 1 }
        var area: WorldArea?
        if let first = segments.first?.points.first {
            area = WorldArea.of(latitude: first.latitude, longitude: first.longitude)
        } else if let start = route.start {
            area = WorldArea.of(latitude: start.centerLatitude, longitude: start.centerLongitude)
        }
        self.init(id: trip.id, date: trip.startedAt ?? trip.createdAt,
                  distanceMeters: trip.summary?.distanceMeters ?? 0, segments: segments,
                  regions: trip.places?.regions ?? [], countries: trip.places?.countries ?? [],
                  road: trip.mainRoad.map(ShareCardText.roadName), area: area)
    }
}

/// What "My map" shows.
struct MapFilter: Equatable, Sendable {
    enum Period: Hashable, Sendable { case last30Days, allTime }

    /// Nil: the part of the world with the most trips.
    var area: WorldArea?
    var period: Period = .allTime
    /// Only with `allTime`.
    var year: Int?
    /// A region or country code.
    var placeCode: String?
    var road: String?

    var isNarrowed: Bool { (period == .allTime && year != nil) || placeCode != nil || road != nil }
}

enum MyMapLogic {
    /// The parts of the world the trips are in, busiest first.
    static func areas(_ trips: [HeatTrip]) -> [WorldArea] {
        var counts: [WorldArea: Int] = [:]
        for trip in trips { if let area = trip.area { counts[area, default: 0] += 1 } }
        return WorldArea.allCases.filter { counts[$0] != nil }.sorted { counts[$0, default: 0] > counts[$1, default: 0] }
    }

    /// The area on the map: the chosen one while it has trips, otherwise the busiest.
    /// Nil when every trip is in one part of the world.
    static func shownArea(_ trips: [HeatTrip], chosen: WorldArea?) -> WorldArea? {
        let all = areas(trips)
        guard all.count > 1 else { return nil }
        if let chosen, all.contains(chosen) { return chosen }
        return all.first
    }

    static func inArea(_ trips: [HeatTrip], _ area: WorldArea?) -> [HeatTrip] {
        guard let area else { return trips }
        return trips.filter { $0.area == nil || $0.area == area }
    }

    /// The trips of the shown area that pass the period, year, place and road filters.
    static func filtered(_ trips: [HeatTrip], by filter: MapFilter, now: Date, calendar: Calendar = .current) -> [HeatTrip] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        return inArea(trips, shownArea(trips, chosen: filter.area)).filter { trip in
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

    /// Width over height of the map, so a wide country gets a wide map and no empty band.
    static func aspect(_ trips: [HeatTrip]) -> Double {
        var south = Double.infinity, north = -Double.infinity, west = Double.infinity, east = -Double.infinity
        for trip in trips {
            for segment in trip.segments {
                for point in segment.points {
                    south = min(south, point.latitude); north = max(north, point.latitude)
                    west = min(west, point.longitude); east = max(east, point.longitude)
                }
            }
        }
        guard south.isFinite, west.isFinite, north > south else { return 1.15 }
        let width = (east - west) * cos((south + north) / 2 * .pi / 180)
        return min(1.55, max(0.9, width / (north - south)))
    }

    /// The right end of the legend: the busiest road, or the scale's floor when nothing is busy yet.
    static func legendMax(_ maxCount: Int) -> Int { max(maxCount, HeatMap.fullScaleCount) }

    /// "198 trips · 38 states".
    static func tripsLine(_ trips: [HeatTrip]) -> String {
        var parts = [trips.count == 1
            ? String(localized: "1 trip", comment: "My map share card.")
            : String(localized: "\(trips.count) trips", comment: "My map share card; the placeholder is a number above 1.")]
        if let places = placeCount(trips) { parts.append("\(places.count.formatted()) \(places.noun)") }
        return parts.joined(separator: " · ")
    }
}

/// The Map tab (SCREENS.md "My map", plan §4.5, mockup 3): every trip merged into one map, brighter
/// where the driver goes more often, with filters and a card to share. The Pro lock comes with M6.
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
    @State private var maxCount = 0
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.l) {
                header
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
        .sheet(isPresented: $showShare) {
            if let trips {
                MyMapShareSheet(trips: shown(trips), caption: subtitle, unit: unit)
            }
        }
    }

    private func shown(_ trips: [HeatTrip]) -> [HeatTrip] {
        MyMapLogic.filtered(trips, by: filter, now: Date())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: RPSpace.m) {
            VStack(alignment: .leading, spacing: RPSpace.xs) {
                Text("My map").font(RPType.screenTitle)
                Text(subtitle)
                    .font(RPType.subtitle)
                    .foregroundStyle(Color.RP.textSecondary)
            }
            Spacer(minLength: 0)
            if let trips, !shown(trips).isEmpty {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(RPType.subtitle.weight(.semibold))
                        .foregroundStyle(Color.RP.accentText)
                        .frame(width: RPSize.minTouch, height: RPSize.minTouch)
                        .background(Color.RP.card, in: Circle())
                        .overlay(Circle().strokeBorder(Color.RP.border, lineWidth: 1))
                }
                .accessibilityLabel(Text("Share my map"))
                .accessibilityIdentifier("shareMapIcon")
            }
        }
    }

    @ViewBuilder
    private func content(_ trips: [HeatTrip]) -> some View {
        let areas = MyMapLogic.areas(trips)
        let area = MyMapLogic.shownArea(trips, chosen: filter.area)
        let here = MyMapLogic.inArea(trips, area)
        let visible = shown(trips)
        if areas.count > 1, let area {
            Picker("Part of the world", selection: Binding(get: { area }, set: { newArea in
                // Places and roads belong to one part of the world.
                filter.area = newArea
                filter.placeCode = nil
                filter.road = nil
            })) {
                ForEach(areas, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mapArea")
        }
        Picker("Period", selection: $filter.period) {
            Text("Last 30 days").tag(MapFilter.Period.last30Days)
            Text("All time").tag(MapFilter.Period.allTime)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("mapPeriod")
        chips(here)
        if visible.isEmpty {
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
            HeatMapView(trips: visible) { maxCount = $0 }
                .aspectRatio(MyMapLogic.aspect(visible), contentMode: .fit)
                // The map runs edge to edge.
                .padding(.horizontal, -RPSpace.screenMargin)
            legend
            stats(visible)
            Button {
                showShare = true
            } label: {
                Text("Share my map")
            }
            .buttonStyle(.rpPrimary)
            .padding(.top, RPSpace.s)
            .accessibilityIdentifier("shareMap")
        }
    }

    private var subtitle: String {
        guard let trips, !trips.isEmpty else {
            return String(localized: "Every road you drive, on one map.")
        }
        let here = MyMapLogic.inArea(trips, MyMapLogic.shownArea(trips, chosen: filter.area))
        var parts: [String] = []
        if let code = filter.placeCode, let place = MyMapLogic.places(here).first(where: { $0.code == code }) {
            parts.append(place.name)
        }
        if let road = filter.road { parts.append(road) }
        if filter.period == .allTime, let year = filter.year { parts.append(String(year)) }
        if !parts.isEmpty {
            if filter.period == .last30Days { parts.append(String(localized: "Last 30 days")) }
            return parts.joined(separator: " · ")
        }
        switch filter.period {
        case .last30Days:
            return String(localized: "Your last 30 days of trips")
        case .allTime:
            guard let first = here.map(\.date).min() else { return "" }
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
            HeatLegend(maxCount: maxCount, palette: HeatMapArt.palette, text: Color.RP.textSecondary, font: RPType.axis)
        }
        .accessibilityElement(children: .combine)
    }

    private func stats(_ shown: [HeatTrip]) -> some View {
        let distance = ShareCardText.distance(meters: shown.reduce(0) { $0 + $1.distanceMeters }, unit: unit)
        let places = MyMapLogic.placeCount(shown)
        return HStack(alignment: .top, spacing: RPSpace.m) {
            stat(distance.value, distance.unit, identifier: "mapDistance")
            if let places { stat(places.count.formatted(), places.noun, identifier: "mapPlaces") }
            stat(shown.count.formatted(),
                 shown.count == 1 ? String(localized: "trip", comment: "My map: after the number 1.")
                                  : String(localized: "trips", comment: "My map: after a number, e.g. 14 trips."),
                 identifier: "mapTrips")
            if maxCount > 1 {
                stat("\(maxCount.formatted())×", String(localized: "top road", comment: "My map: under how many times the most driven road was driven, e.g. 37×."),
                     identifier: "mapTopRoad")
            }
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
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The heat scale as a bar: "1×" to the busiest road's count.
struct HeatLegend: View {
    let maxCount: Int
    let palette: [Color]
    let text: Color
    let font: Font

    var body: some View {
        HStack(spacing: RPSpace.s) {
            Text(verbatim: "1×")
            Capsule()
                .fill(LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            Text(verbatim: "\(MyMapLogic.legendMax(maxCount).formatted())×")
        }
        .font(font)
        .foregroundStyle(text)
    }
}

/// The trips merged into one road network on RoadPrint's own map, coloured by how often each
/// stretch was driven. Static art, like the trip map: the filters are the zoom.
struct HeatMapView: View {
    let trips: [HeatTrip]
    /// Called with the busiest road's count when the map is laid out.
    var onLaidOut: (Int) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        /// Trips too short to draw as routes.
        case nothing
        case ready(HeatScene)
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
                case .ready(let scene):
                    canvas(scene)
                }
            }
            .task(id: Key(trips: trips.map(\.id), size: proxy.size)) { await build(size: proxy.size) }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map of your trips"))
        .accessibilityIdentifier("heatMap")
    }

    private func canvas(_ scene: HeatScene) -> some View {
        let base = HeatMapArt.base(scene, scheme: scheme, displayScale: displayScale)
        let glow = RPTheme.draw(for: scheme).routeGlow
        let palette = HeatMapArt.palette
        return Canvas { context, _ in
            base.draw(&context)
            HeatMapArt.draw(scene.lines, palette: palette, glow: glow, in: &context)
        }
    }

    private func build(size: CGSize) async {
        guard size.width > 100, size.height > 100 else { return }
        let routes = trips.map(\.segments)
        let scene = await HeatMapArt.layout(routes: routes, size: size,
                                            insets: ViewportInsets(top: 22, left: 18, bottom: 22, right: 18))
        guard !Task.isCancelled else { return }
        phase = scene.map { .ready($0) } ?? .nothing
        onLaidOut(scene?.maxCount ?? 0)
    }
}

/// Canvas drawing for the heat map. Not a view: Canvas closures run off the main actor.
enum HeatMapArt {
    /// Cold to hot, following the phone's theme. A road driven once is already a clear orange.
    static let palette = [Color.RP.heat2, Color.RP.heat3, Color.RP.heat4, Color.RP.heat5]
    /// The same in the night palette, for share cards.
    static let nightPalette = [Color.RP.Night.heat2, Color.RP.Night.heat3, Color.RP.Night.heat4, Color.RP.Night.heat5]
    /// More region outlines than this would turn the map into a net (Europe's counties).
    static let maxRegionOutlines = 120

    /// Merges the routes and lays them out, off the main actor. Nil when there is nothing to draw.
    static func layout(routes: [[RouteSegment]], size: CGSize, insets: ViewportInsets) async -> HeatScene? {
        let width = Double(size.width), height = Double(size.height)
        return await Task.detached(priority: .userInitiated) { () -> HeatScene? in
            let heat = HeatMap.make(routes: routes)
            guard !heat.lines.isEmpty, let places = try? PlaceIndex.bundled() else { return nil }
            return try? MapSceneBuilder.buildHeat(heat, places: places, size: (width, height), insets: insets)
        }.value
    }

    /// The land, the borders and the labels under the heat lines.
    static func base(_ scene: HeatScene, scheme: ColorScheme, displayScale: CGFloat) -> MapSceneRenderer {
        var renderer = MapSceneRenderer(scene: scene.map, scheme: scheme, displayScale: displayScale,
                                        summitName: "", summitAltitude: "")
        var layers: Set<MapScene.Layer> = [.landFill, .countryBorders, .labels]
        if scene.map.outlines.filter({ $0.kind == .region }).count <= maxRegionOutlines { layers.insert(.regionBorders) }
        renderer.only = layers
        return renderer
    }

    static func color(_ heat: Double, palette: [Color]) -> Color {
        guard palette.count > 1 else { return palette.first ?? Color.RP.route }
        let position = min(max(heat, 0), 1) * Double(palette.count - 1)
        let index = min(Int(position), palette.count - 2)
        return palette[index].mix(with: palette[index + 1], by: position - Double(index))
    }

    /// Busier roads are thicker as well as brighter.
    static func width(_ heat: Double) -> CGFloat {
        1.5 + 2.3 * CGFloat(min(max(heat, 0), 1))
    }

    /// A line through the points with its corners rounded off.
    static func smooth(_ points: [PlanePoint]) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let corner = points[index], next = points[index + 1]
                path.addQuadCurve(to: CGPoint(x: (corner.x + next.x) / 2, y: (corner.y + next.y) / 2),
                                  control: CGPoint(x: corner.x, y: corner.y))
            }
        }
        path.addLine(to: CGPoint(x: last.x, y: last.y))
        return path
    }

    /// Cold roads first and hot ones on top. At night every road carries a soft orange light and a
    /// tighter one in its own colour, and the busiest get a pale core; by day a darker edge
    /// keeps the lines readable on the light land.
    static func draw(_ lines: [HeatScene.Line], palette: [Color], glow: Bool, scale: CGFloat = 1,
                     in context: inout GraphicsContext) {
        let levels = HeatMap.levels
        var paths = [Path](repeating: Path(), count: levels)
        for line in lines {
            let level = min(levels - 1, max(0, Int((line.heat * Double(levels - 1)).rounded())))
            paths[level].addPath(smooth(line.points))
        }
        let used = (0..<levels).filter { !paths[$0].isEmpty }
        guard !used.isEmpty, let hottest = palette.last else { return }
        func heat(_ level: Int) -> Double { Double(level) / Double(levels - 1) }
        func style(_ width: CGFloat) -> StrokeStyle {
            StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)
        }
        if glow {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 7 * scale))
                layer.opacity = 0.34
                for level in used {
                    layer.stroke(paths[level], with: .color(color(heat(level) * 0.5, palette: palette)),
                                 style: style(width(heat(level)) + 7))
                }
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.2 * scale))
                layer.opacity = 0.6
                for level in used {
                    layer.stroke(paths[level], with: .color(color(heat(level), palette: palette)),
                                 style: style(width(heat(level)) + 2.2))
                }
            }
        } else {
            for level in used {
                context.stroke(paths[level], with: .color(hottest.opacity(0.3)), style: style(width(heat(level)) + 1.6))
            }
        }
        for level in used {
            context.stroke(paths[level], with: .color(color(heat(level), palette: palette)), style: style(width(heat(level))))
        }
        if glow {
            for level in used where heat(level) > 0.55 {
                context.stroke(paths[level], with: .color(hottest.opacity((heat(level) - 0.55) / 0.45 * 0.9)),
                               style: style(width(heat(level)) * 0.4))
            }
        }
    }
}

#if DEBUG
/// DEBUG-only: "My map" on made-up trips over a road network of real cities.
/// Launch with `-RPHeatFixture usa-500` (`usa`, `europe` or `mixed`, then the number of trips).
struct HeatDebugView: View {
    let fixture: String
    /// Made once: the trips get new ids every time they are built.
    @State private var trips: [HeatTrip]?

    var body: some View {
        MyMapScreen(trips: trips, unit: .miles)
            .task { trips = Self.trips(fixture: fixture) }
    }

    static func trips(fixture: String) -> [HeatTrip] {
        let parts = fixture.split(separator: "-")
        guard parts.count == 2, let area = HeatFixture.Area(rawValue: String(parts[0])), let count = Int(parts[1]) else { return [] }
        let now = Date()
        return HeatFixture.trips(area, count: count).map { trip in
            let first = trip.segments.first?.points.first
            return HeatTrip(id: UUID(), date: now.addingTimeInterval(-Double(trip.daysAgo) * 86_400),
                            distanceMeters: trip.distanceMeters, segments: trip.segments,
                            regions: trip.regions, countries: trip.countries, road: nil,
                            area: first.map { WorldArea.of(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }
}
#endif
