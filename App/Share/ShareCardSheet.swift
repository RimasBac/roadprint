import SwiftUI
import RoadPrintCore

/// Share a trip as a picture or a short video (SCREENS.md S1): pick a card style and a format, then
/// the system share sheet. Print shares a transparent picture or opens the photo editor; Terrain (Pro)
/// downloads elevation for the trip's area first (ADR 0006).
struct ShareCardSheet: View {
    let trip: Trip
    let startLabel: String?
    let endLabel: String?
    /// The career distance after this trip, for the Print card's third stat; nil when the driver set no
    /// starting career distance (the card shows the highest point instead).
    var careerMeters: Double?

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var style: ShareCardStyle = .nightHighway
    @State private var lastAllowedStyle: ShareCardStyle = .nightHighway
    @State private var card: Prepared?
    @State private var exported: Image?
    @State private var format: Format = .picture
    @State private var video: URL?
    @State private var videoProgress = 0.0
    @State private var videoFailed = false
    @State private var paywall: PaywallTrigger?
    @State private var lastPaywall: PaywallTrigger?
    @State private var printCard: PrintPrepared?
    @State private var printFile: URL?
    @State private var editingPrint = false
    @State private var terrain: TerrainState = .idle
    @State private var terrainRetry = 0

    enum Format: String, CaseIterable, Identifiable {
        case picture, video
        var id: String { rawValue }
        var name: String {
            switch self {
            case .picture: String(localized: "Picture", comment: "Share sheet: share the card as a picture.")
            case .video: String(localized: "Video", comment: "Share sheet: share the card as a short video of the route drawing itself.")
            }
        }
    }

    private struct Job: Equatable {
        let style: ShareCardStyle
        let format: Format
        let retry: Int
    }

    private struct Prepared {
        let style: ShareCardStyle
        let content: ShareCardContent
        let scene: MapScene?
        let elevation: ShareCardElevation?
    }

    private struct PrintPrepared {
        let input: PrintCardInput
        let layout: PrintCardLayout
        let road: MainRoad?
    }

    private enum TerrainState {
        case idle
        case loading(Double)
        case ready(TerrainPrepared)
        case offline
        case failed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RPSpace.l) {
                preview
                Picker("Card style", selection: $style) {
                    ForEach(ShareCardStyle.allCases) { style in
                        if isLocked(style) {
                            Text("\(style.name) · Pro", comment: "Share sheet: a card style that needs RoadPrint Pro.").tag(style)
                        } else {
                            Text(style.name).tag(style)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: style)
                .accessibilityIdentifier("shareStylePicker")
                if style.isMapCard {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases) { format in
                            if isLocked(format) {
                                Text("\(format.name) · Pro", comment: "Share sheet: a format that needs RoadPrint Pro.").tag(format)
                            } else {
                                Text(format.name).tag(format)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: format)
                    .accessibilityIdentifier("shareFormatPicker")
                }
                shareButton
            }
            .padding(RPSpace.screenMargin)
            .background(Color.RP.background.ignoresSafeArea())
            .navigationTitle("Share trip card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: format) { _, new in
            // Video is Pro: the paywall opens and the picker goes back to Picture.
            if isLocked(new) {
                format = .picture
                paywall = .tappedVideo
                lastPaywall = .tappedVideo
            }
        }
        .onChange(of: style) { _, new in
            // Terrain is Pro: the paywall opens and the picker goes back to the last free style.
            if isLocked(new) {
                style = lastAllowedStyle
                paywall = .tappedTerrain
                lastPaywall = .tappedTerrain
            } else {
                lastAllowedStyle = new
                if !new.isMapCard { format = .picture }
            }
        }
        .sheet(item: $paywall, onDismiss: {
            // Bought Pro from the Video or Terrain tap: go straight there.
            guard environment.pro.isPro else { return }
            switch lastPaywall {
            case .tappedVideo?: if style.isMapCard { format = .video }
            case .tappedTerrain?: style = .terrain
            default: break
            }
        }) { PaywallSheet(trigger: $0) }
        .fullScreenCover(isPresented: $editingPrint) {
            if let printCard {
                PrintEditorView(input: printCard.input, road: printCard.road)
            }
        }
        .task(id: Job(style: style, format: format, retry: terrainRetry)) {
            await prepare(style)
            if style.isMapCard, format == .video, !isLocked(.video) { await makeVideo() }
        }
    }

    private func isLocked(_ format: Format) -> Bool {
        format == .video && !ProPolicy.isAllowed(.videoCard, entitlement: environment.pro.entitlement)
    }

    private func isLocked(_ style: ShareCardStyle) -> Bool {
        style == .terrain && !ProPolicy.isAllowed(.terrainCard, entitlement: environment.pro.entitlement)
    }

    @ViewBuilder
    private var shareButton: some View {
        switch style {
        case .print: printButtons
        case .terrain: terrainButton
        case .nightHighway, .roadAtlas: mapCardButton
        }
    }

    @ViewBuilder
    private var mapCardButton: some View {
        switch format {
        case .picture:
            if let exported {
                ShareLink(item: exported, preview: SharePreview("RoadPrint trip card", image: exported)) {
                    Text("Share")
                }
                .buttonStyle(.rpPrimary)
                .accessibilityIdentifier("shareCardButton")
                #if DEBUG
                .accessibilityValue(Text(verbatim: card?.style.rawValue ?? ""))
                #endif
            } else {
                ProgressView()
                    .frame(height: RPSize.buttonHeight)
            }
        case .video:
            if let video {
                ShareLink(item: video, preview: SharePreview("RoadPrint trip video")) {
                    Text("Share")
                }
                .buttonStyle(.rpPrimary)
                .accessibilityIdentifier("shareCardButton")
                #if DEBUG
                .accessibilityValue(Text(verbatim: Format.video.rawValue))
                #endif
            } else if videoFailed {
                Text("The video couldn't be made. Share the picture instead.")
                    .font(RPType.statLabel)
                    .foregroundStyle(Color.RP.textSecondary)
                    .frame(height: RPSize.buttonHeight)
            } else {
                VStack(spacing: RPSpace.xs) {
                    ProgressView(value: videoProgress)
                        .tint(Color.RP.accentText)
                    Text("Making your video…")
                        .font(RPType.statLabel)
                        .foregroundStyle(Color.RP.textSecondary)
                }
                .frame(height: RPSize.buttonHeight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("shareVideoProgress")
            }
        }
    }

    /// Print: put the card on a photo (the editor), or share it as it is: a transparent picture.
    @ViewBuilder
    private var printButtons: some View {
        if let printFile {
            HStack(spacing: RPSpace.s) {
                Button {
                    editingPrint = true
                } label: {
                    Text("Put on a photo", comment: "Share sheet: open the Print card editor over a photo.")
                }
                .buttonStyle(.rpPrimary)
                .accessibilityIdentifier("printEditButton")
                ShareLink(item: printFile, preview: SharePreview("RoadPrint trip card")) {
                    Text("Share", comment: "Share sheet: share the Print card as a transparent picture.")
                        .font(RPType.body.weight(.semibold))
                        .foregroundStyle(Color.RP.accentText)
                        .frame(height: RPSize.buttonHeight)
                        .padding(.horizontal, RPSpace.m)
                }
                .accessibilityIdentifier("shareCardButton")
                #if DEBUG
                .accessibilityValue(Text(verbatim: ShareCardStyle.print.rawValue))
                #endif
            }
        } else {
            ProgressView()
                .frame(height: RPSize.buttonHeight)
        }
    }

    @ViewBuilder
    private var terrainButton: some View {
        switch terrain {
        case .ready:
            if let exported {
                ShareLink(item: exported, preview: SharePreview("RoadPrint trip card", image: exported)) {
                    Text("Share")
                }
                .buttonStyle(.rpPrimary)
                .accessibilityIdentifier("shareCardButton")
                #if DEBUG
                .accessibilityValue(Text(verbatim: ShareCardStyle.terrain.rawValue))
                #endif
            } else {
                ProgressView()
                    .frame(height: RPSize.buttonHeight)
            }
        case .idle, .loading:
            VStack(spacing: RPSpace.xs) {
                if case .loading(let progress) = terrain {
                    ProgressView(value: progress)
                        .tint(Color.RP.accentText)
                } else {
                    ProgressView()
                }
                Text("Drawing the land…", comment: "Share sheet: the Terrain card is downloading elevation and rendering.")
                    .font(RPType.statLabel)
                    .foregroundStyle(Color.RP.textSecondary)
            }
            .frame(height: RPSize.buttonHeight)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("terrainProgress")
        case .offline, .failed:
            VStack(spacing: RPSpace.xs) {
                Text(terrainMessage)
                    .font(RPType.statLabel)
                    .foregroundStyle(Color.RP.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    terrainRetry += 1
                } label: {
                    Text("Try again", comment: "Share sheet: retry the Terrain card.")
                }
                .accessibilityIdentifier("terrainRetry")
            }
            .frame(minHeight: RPSize.buttonHeight)
            .accessibilityIdentifier("terrainOffline")
        }
    }

    private var terrainMessage: String {
        if case .offline = terrain {
            return String(localized: "Terrain will be ready when you're back online. The other cards work offline.",
                          comment: "Share sheet: the Terrain card needs a connection to download elevation for the trip's area.")
        }
        return String(localized: "The Terrain card couldn't be drawn for this trip. Share another card instead.",
                      comment: "Share sheet: the Terrain card failed for another reason.")
    }

    /// Draws the chosen card's video into a temporary file for the share sheet.
    private func makeVideo() async {
        guard let card else { return }
        video = nil
        videoFailed = false
        videoProgress = 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoadPrint-trip-\(card.style.rawValue).mp4")
        do {
            try await CardVideo.write(to: url, size: ShareCardMetrics.size, scale: ShareCardMetrics.exportScale,
                                      onProgress: { videoProgress = $0 }) { seconds in
                ShareCard(style: card.style, content: card.content, scene: card.scene, elevation: card.elevation,
                          motion: CardMotion(time: seconds))
            }
            guard !Task.isCancelled else { return }
            video = url
        } catch is CancellationError {
            return
        } catch {
            videoFailed = true
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let size = ShareCardMetrics.size
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
            Group {
                if scale > 0, let content = previewContent {
                    content
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: RPRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: RPRadius.card)
                                .strokeBorder(Color.RP.border, lineWidth: RPSize.hairline(displayScale: displayScale))
                        }
                        .accessibilityIdentifier("shareCardPreview")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var previewContent: AnyView? {
        switch style {
        case .print:
            guard let printCard else { return nil }
            // On the app's night ground: the card itself is transparent.
            return AnyView(ZStack {
                Color.RP.Night.land
                PrintCardView(layout: printCard.layout, road: printCard.road)
            })
        case .terrain:
            guard case .ready(let card) = terrain else {
                return AnyView(ZStack {
                    Color.RP.Night.background
                    if case .offline = terrain {
                        Image(systemName: "wifi.slash")
                            .font(.rpText(size: 28, weight: .semibold))
                            .foregroundStyle(Color.RP.Night.textSecondary)
                    } else {
                        ProgressView()
                    }
                })
            }
            return AnyView(TerrainCardView(card: card))
        case .nightHighway, .roadAtlas:
            guard let card, card.style == style else { return nil }
            return AnyView(TimelineView(.animation(paused: format != .video)) { timeline in
                ShareCard(style: card.style, content: card.content, scene: card.scene, elevation: card.elevation,
                          motion: format == .video ? CardMotion(time: Self.loop(timeline.date)) : .still)
            })
        }
    }

    /// Seconds into the video at `date`, looping, for the preview.
    private static func loop(_ date: Date) -> Double {
        #if DEBUG
        // Show the route mid-draw in the still store capture while the real video exports.
        if AppEnvironment.isAppStoreScreenshotCapture { return CardVideo.Timing.standard.time(atProgress: 0.88) }
        #endif
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: CardVideo.Timing.standard.duration)
    }

    private func prepare(_ style: ShareCardStyle) async {
        switch style {
        case .print: await preparePrint()
        case .terrain: await prepareTerrain()
        case .nightHighway, .roadAtlas: await prepareMapCard(style)
        }
    }

    /// The card is drawn only from the share summary, never from the trip (AGENTS.md §7b.3).
    private var summary: TripShareSummary? {
        TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true))
    }

    private func preparePrint() async {
        if printCard != nil, printFile != nil { return }
        guard let summary else { return }
        let input = PrintCardContent.input(summary: summary, unit: environment.profile.distanceUnit,
                                           startLabel: startLabel, endLabel: endLabel, careerMeters: careerMeters)
        let layout = await Task.detached(priority: .userInitiated) {
            PrintCard.layout(input, ink: .light, mode: .full, measurer: CoreTextMeasurer.shared)
        }.value
        guard !Task.isCancelled else { return }
        let prepared = PrintPrepared(input: input, layout: layout, road: summary.mainRoad)
        printCard = prepared
        // A transparent 1080 × 1920 PNG.
        let renderer = ImageRenderer(content: PrintCardView(layout: layout, road: prepared.road))
        renderer.scale = ShareCardMetrics.exportScale
        renderer.isOpaque = false
        guard let data = renderer.uiImage?.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoadPrint-print-card.png")
        if (try? data.write(to: url, options: .atomic)) != nil { printFile = url }
    }

    private func prepareTerrain() async {
        if case .ready = terrain, exported != nil, card == nil { return }
        guard let summary else {
            terrain = .failed
            return
        }
        exported = nil
        card = nil
        terrain = .loading(0)
        do {
            let prepared = try await TerrainCardPipeline.prepare(
                summary: summary, unit: environment.profile.distanceUnit, startLabel: startLabel, endLabel: endLabel,
                progress: { value in Task { @MainActor in if case .loading = terrain { terrain = .loading(value * 0.8) } } })
            guard !Task.isCancelled else { return }
            terrain = .ready(prepared)
            let renderer = ImageRenderer(content: TerrainCardView(card: prepared))
            renderer.scale = ShareCardMetrics.exportScale
            if let image = renderer.uiImage { exported = Image(uiImage: image) }
        } catch is CancellationError {
            return
        } catch TerrainCardPipeline.Failure.offline {
            terrain = .offline
        } catch {
            terrain = .failed
        }
    }

    private func prepareMapCard(_ style: ShareCardStyle) async {
        if card?.style == style, exported != nil { return }
        exported = nil
        let unit = environment.profile.distanceUnit
        guard let summary else {
            card = nil
            return
        }
        let elevation = summary.route
            .flatMap { ElevationProfile.make(segments: $0, summit: summary.summit, unit: unit,
                                             tripDistanceMeters: summary.distanceMeters) }
            .flatMap(ShareCardElevation.make)
        let hasElevation = elevation != nil
        let start = startLabel, end = endLabel
        let scene = await Task.detached(priority: .userInitiated) { () -> MapScene? in
            guard let places = try? PlaceIndex.bundled() else { return nil }
            let spec = ShareCardMetrics.map(style, hasElevation: hasElevation)
            // Both cards place their own small capitals, so the builder places no area names.
            let input = MapSceneInput(summary: summary)
            return try? MapSceneBuilder.build(
                input: input, places: places,
                size: (Double(ShareCardMetrics.size.width), Double(spec.height)),
                insets: spec.insets, labels: spec.labels)
        }.value
        guard !Task.isCancelled else { return }
        let altitude = summary.summitAltitudeMeters.map { TripMapView.altitudeText($0, unit: unit) }
        let content = ShareCardText.content(summary: summary, unit: unit, altitude: altitude,
                                            startLabel: start, endLabel: end)
        card = Prepared(style: style, content: content, scene: scene, elevation: elevation)
        let renderer = ImageRenderer(content: ShareCard(style: style, content: content, scene: scene, elevation: elevation))
        renderer.scale = ShareCardMetrics.exportScale
        if let image = renderer.uiImage { exported = Image(uiImage: image) }
    }
}

#if DEBUG
/// DEBUG-only: a card on the hard-coded I-80 fixture, for screenshots.
/// Launch with `-RPCardFixture i80` and, for another style, `-RPCardStyle roadAtlas|print|terrain`.
/// Print also takes `-RPPrintInk dark` and `-RPPrintLayout sticker`; Terrain downloads its tiles.
struct CardDebugView: View {
    let fixture: String
    @State private var scene: MapScene?
    @State private var ready = false
    @State private var printLayout: PrintCardLayout?
    @State private var terrain: TerrainPrepared?
    @State private var terrainFailed = false

    private var style: ShareCardStyle {
        UserDefaults.standard.string(forKey: "RPCardStyle").flatMap(ShareCardStyle.init(rawValue:)) ?? .nightHighway
    }

    private var printInk: PrintInk {
        UserDefaults.standard.string(forKey: "RPPrintInk").flatMap(PrintInk.init(rawValue:)) ?? .light
    }

    private var printMode: PrintLayoutMode {
        UserDefaults.standard.string(forKey: "RPPrintLayout").flatMap(PrintLayoutMode.init(rawValue:)) ?? .full
    }

    var body: some View {
        ScrollView {
            if ready {
                switch style {
                case .print:
                    if let printLayout {
                        ZStack {
                            // Dark ink is for bright photos: show it on the day ground.
                            printInk == .dark ? Color.RP.Day.background : Color.RP.Night.land
                            PrintCardView(layout: printLayout, road: Self.fixtureSummary?.mainRoad)
                        }
                        .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height)
                        .accessibilityIdentifier("shareCard")
                        .frame(maxWidth: .infinity)
                    }
                case .terrain:
                    if let terrain {
                        TerrainCardView(card: terrain)
                            .accessibilityIdentifier("shareCard")
                            .frame(maxWidth: .infinity)
                    } else if terrainFailed {
                        Text(verbatim: "Terrain failed").accessibilityIdentifier("terrainFixtureFailed")
                    }
                case .nightHighway, .roadAtlas:
                    ShareCard(style: style, content: Self.fixtureContent, scene: scene, elevation: Self.fixtureElevation,
                              motion: CardMotion(time: UserDefaults.standard.string(forKey: "RPCardProgress").flatMap(Double.init)
                                  .map { CardVideo.Timing.standard.time(atProgress: $0) }))
                        .accessibilityIdentifier("shareCard")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.RP.Night.background.ignoresSafeArea())
        .task {
            if style == .print, let summary = Self.fixtureSummary {
                let input = PrintCardContent.input(summary: summary, unit: .miles, startLabel: "Salt Lake City area",
                                                   endLabel: "Sacramento area", careerMeters: 1_284_961 * DistanceUnit.metersPerMile,
                                                   locale: Locale(identifier: "en_US"))
                printLayout = PrintCard.layout(input, ink: printInk, mode: printMode, measurer: CoreTextMeasurer.shared)
            }
            if style == .terrain, let summary = Self.fixtureSummary {
                ready = true
                do {
                    terrain = try await TerrainCardPipeline.prepare(summary: summary, unit: .miles, startLabel: "Salt Lake City area",
                                                                    endLabel: "Sacramento area", progress: { _ in })
                } catch {
                    terrainFailed = true
                }
                return
            }
            let chosen = style
            if let fixtureInput = MapDebugView.input(fixture: fixture) {
                scene = await Task.detached { () -> MapScene? in
                    guard let places = try? PlaceIndex.bundled() else { return nil }
                    let spec = ShareCardMetrics.map(chosen, hasElevation: true)
                    var input = fixtureInput
                    input.startLabel = nil
                    input.endLabel = nil
                    return try? MapSceneBuilder.build(
                        input: input, places: places,
                        size: (Double(ShareCardMetrics.size.width), Double(spec.height)),
                        insets: spec.insets, labels: spec.labels)
                }.value
            }
            ready = true
        }
    }

    /// A made-up profile shaped like I-80 westbound: the basin, Donner Summit, the drop to Sacramento.
    static let fixtureElevation: ShareCardElevation = {
        let points = (0...140).map { index -> CGPoint in
            let t = Double(index) / 140
            let basin = 0.42 + 0.09 * sin(t * 19) + 0.05 * sin(t * 47 + 1)
            let peak = 0.55 * exp(-pow((t - 0.86) / 0.035, 2))
            let drop = t > 0.9 ? (t - 0.9) / 0.1 : 0
            return CGPoint(x: t, y: min(1, max(0.02, basin * (1 - drop) + peak)))
        }
        return ShareCardElevation(series: [points], summit: points.max { $0.y < $1.y } ?? .zero)
    }()

    /// The bundled I-80 route (Salt Lake City → Sacramento) with a made-up altitude profile that peaks
    /// at Donner Summit, as a share summary: for the Print and Terrain fixtures.
    static var fixtureSummary: TripShareSummary? {
        guard let input = MapDebugView.input(fixture: "i80"), let points = input.segments.first?.points, points.count > 2 else { return nil }
        let n = Double(points.count - 1)
        let withAltitude = points.enumerated().map { index, p -> RoutePoint in
            let t = Double(index) / n
            let basin = 1_300 + 450 * (0.5 + 0.5 * sin(t * 19)) + 120 * sin(t * 47 + 1)
            let peak = 900 * exp(-pow((t - 0.86) / 0.035, 2))
            let drop = t > 0.9 ? (t - 0.9) / 0.1 : 0
            return RoutePoint(latitude: p.latitude, longitude: p.longitude, altitude: max(10, (basin + peak) * (1 - drop) + 10 * drop))
        }
        let summit = withAltitude.max { ($0.altitude ?? 0) < ($1.altitude ?? 0) }
        var trip = Trip(
            createdAt: Date(timeIntervalSince1970: 1_793_750_400), status: .completed,
            endedAt: Date(timeIntervalSince1970: 1_793_790_000),
            summary: TripStats(distanceMeters: 1_037_117.8, movingTimeSeconds: 37_336, elapsedSeconds: 39_000, gapCount: 0),
            route: ProcessedRoute(segments: [RouteSegment(points: withAltitude)], start: input.start, end: input.end, summit: summit),
            places: TripPlaces(
                countries: [PlaceRef(code: "US", name: "United States of America")],
                regions: [PlaceRef(code: "US-UT", name: "Utah"), PlaceRef(code: "US-NV", name: "Nevada"),
                          PlaceRef(code: "US-CA", name: "California")]))
        trip.mainRoad = MainRoad(network: .usInterstate, ref: "80", countryCode: "US")
        return TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true, timeZone: TimeZone(identifier: "UTC") ?? .current))
    }

    // The fixture's known numbers (RecordAndListTests): 1,037,117.8 m and 37,336 s moving.
    static var fixtureContent: ShareCardContent {
        let altitude = TripMapView.altitudeText(2206, unit: .miles)
        var trip = Trip(
            createdAt: Date(timeIntervalSince1970: 1_793_750_400), status: .completed,
            endedAt: Date(timeIntervalSince1970: 1_793_790_000),
            summary: TripStats(distanceMeters: 1_037_117.8, movingTimeSeconds: 37_336, elapsedSeconds: 39_000, gapCount: 0),
            route: ProcessedRoute(segments: [RouteSegment(points: [
                RoutePoint(latitude: 40.76, longitude: -111.89, altitude: 1300),
                RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206),
                RoutePoint(latitude: 38.58, longitude: -121.49, altitude: 10)])],
                                  summit: RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206)),
            places: TripPlaces(
                countries: [PlaceRef(code: "US", name: "United States of America")],
                regions: [PlaceRef(code: "US-UT", name: "Utah"), PlaceRef(code: "US-NV", name: "Nevada"),
                          PlaceRef(code: "US-CA", name: "California")]))
        trip.mainRoad = MainRoad(network: .usInterstate, ref: "80", countryCode: "US")
        let utc = TimeZone(identifier: "UTC") ?? .current
        guard let summary = TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true, timeZone: utc)) else {
            return ShareCardContent(distanceValue: "", distanceUnit: "", subtitle: "", chips: [], title: "", longDate: "",
                                    stats: [], crossedCodes: [])
        }
        return ShareCardText.content(summary: summary, unit: .miles, altitude: altitude,
                                     startLabel: "Salt Lake City area", endLabel: "Sacramento area")
    }
}
#endif
