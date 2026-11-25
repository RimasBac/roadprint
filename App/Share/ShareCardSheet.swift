import PhotosUI
import SwiftUI
import RoadPrintCore

/// Share a trip as a picture or a short video (SCREENS.md S1). Layout B of the board's design study
/// (ROA-128): the big preview (swipe it to change style), a strip of every style as a small card, one
/// row that changes with the style (Picture/Video for the map cards, the backdrop for Print, a note for
/// Terrain), then the action. Print previews and shares on a backdrop, never on black; Terrain (Pro)
/// downloads elevation for the trip's area first (ADR 0006) and shows a sample while it loads or locked.
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
    @State private var format: Format = .picture
    @State private var cards: [ShareCardStyle: Prepared] = [:]
    @State private var exported: [ShareCardStyle: Image] = [:]
    @State private var video: URL?
    @State private var videoProgress = 0.0
    @State private var videoFailed = false
    @State private var paywall: PaywallTrigger?
    @State private var lastPaywall: PaywallTrigger?
    @State private var printCard: PrintPrepared?
    @State private var backdrop: PrintBackdrop = .nightSky
    @State private var printPhoto: UIImage?
    @State private var printPicker: PhotosPickerItem?
    @State private var printPhotoVersion = 0
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
        let pro: Bool
    }

    private struct PrintJob: Equatable {
        let backdrop: PrintBackdrop
        let photo: Int
        let ready: Bool
    }

    private struct Prepared {
        let style: ShareCardStyle
        let content: ShareCardContent
        let scene: MapScene?
        let elevation: ShareCardElevation?
    }

    private struct PrintPrepared {
        let input: PrintCardInput
        /// The full layout in both inks: the backdrop picks one.
        let light: PrintCardLayout
        let dark: PrintCardLayout
        let road: MainRoad?

        func layout(_ ink: PrintInk) -> PrintCardLayout { ink == .dark ? dark : light }
    }

    private enum TerrainState {
        case idle
        case loading(Double)
        case ready(TerrainPrepared)
        case offline
        case failed
    }

    private typealias M = ShareCardMetrics

    var body: some View {
        NavigationStack {
            VStack(spacing: RPSpace.m) {
                preview
                ShareStyleStrip(selection: $style, isLocked: isLocked)
                optionRow
                    .frame(minHeight: 34)
                shareButton
            }
            .padding(.horizontal, RPSpace.screenMargin)
            .padding(.bottom, RPSpace.m)
            .padding(.top, RPSpace.s)
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
            if !new.isMapCard { format = .picture }
        }
        .onChange(of: printPicker) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                printPhoto = image
                printPhotoVersion += 1
                backdrop = .photo
            }
        }
        .sheet(item: $paywall, onDismiss: {
            // Bought Pro from the Video or Terrain tap: go straight there.
            guard environment.pro.isPro else { return }
            switch lastPaywall {
            case .tappedVideo?: if style.isMapCard { format = .video }
            case .tappedTerrain?: terrainRetry += 1
            default: break
            }
        }) { PaywallSheet(trigger: $0) }
        .fullScreenCover(isPresented: $editingPrint) {
            if let printCard {
                PrintEditorView(input: printCard.input, road: printCard.road,
                                initialPhoto: ShareAssets.backdrop(backdrop, photo: printPhoto))
            }
        }
        .task(id: Job(style: style, format: format, retry: terrainRetry, pro: environment.pro.isPro)) {
            await prepare(style)
            if style.isMapCard, format == .video, !isLocked(.video) { await makeVideo() }
        }
        .task(id: PrintJob(backdrop: backdrop, photo: printPhotoVersion, ready: printCard != nil)) {
            await exportPrint()
        }
    }

    private func isLocked(_ format: Format) -> Bool {
        format == .video && !ProPolicy.isAllowed(.videoCard, entitlement: environment.pro.entitlement)
    }

    private func isLocked(_ style: ShareCardStyle) -> Bool {
        style == .terrain && !ProPolicy.isAllowed(.terrainCard, entitlement: environment.pro.entitlement)
    }

    // MARK: Preview

    /// Every style as a page: swipe to change style. Pages not prepared yet show their thumbnail.
    private var preview: some View {
        GeometryReader { proxy in
            let size = M.size
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
            TabView(selection: $style) {
                ForEach(ShareCardStyle.allCases) { page in
                    Group {
                        if scale > 0 {
                            content(page)
                                .frame(width: size.width, height: size.height)
                                .scaleEffect(scale)
                                .frame(width: size.width * scale, height: size.height * scale)
                                .clipShape(RoundedRectangle(cornerRadius: RPRadius.card))
                                .overlay {
                                    RoundedRectangle(cornerRadius: RPRadius.card)
                                        .strokeBorder(Color.RP.border, lineWidth: RPSize.hairline(displayScale: displayScale))
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("shareCardPreview")
        }
    }

    @ViewBuilder
    private func content(_ page: ShareCardStyle) -> some View {
        switch page {
        case .nightHighway, .roadAtlas:
            if let card = cards[page] {
                TimelineView(.animation(paused: !(page == style && format == .video))) { timeline in
                    ShareCard(style: card.style, content: card.content, scene: card.scene, elevation: card.elevation,
                              motion: page == style && format == .video ? CardMotion(time: Self.loop(timeline.date)) : .still)
                }
            } else {
                thumbnailPlaceholder(page)
            }
        case .print:
            if let printCard {
                let ink = backdrop.ink(photo: printPhoto)
                ZStack {
                    backdropView
                    PrintCardView(layout: printCard.layout(ink), road: printCard.road)
                }
            } else {
                thumbnailPlaceholder(page)
            }
        case .terrain:
            if isLocked(.terrain) {
                TerrainPlaceholder(kind: .locked)
            } else {
                switch terrain {
                case .ready(let card): TerrainCardView(card: card)
                case .offline, .failed: TerrainPlaceholder(kind: .offline)
                case .loading(let progress): TerrainPlaceholder(kind: .loading(progress))
                case .idle: TerrainPlaceholder(kind: .loading(nil))
                }
            }
        }
    }

    /// The style's bundled thumbnail, softened, with a spinner: while its card is being made.
    private func thumbnailPlaceholder(_ page: ShareCardStyle) -> some View {
        ZStack {
            Color.RP.Night.background
            if let image = ShareAssets.thumbnail(page) {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 6).opacity(0.6)
            }
            ProgressView().tint(Color.RP.Night.text)
        }
    }

    /// What the Print card sits on: the sample night or bright sky, the driver's photo, or a checkerboard.
    @ViewBuilder
    private var backdropView: some View {
        switch backdrop {
        case .clear:
            TransparencyGrid()
        case .nightSky, .brightSky, .photo:
            if let image = ShareAssets.backdrop(backdrop, photo: printPhoto) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: M.size.width, height: M.size.height).clipped()
            } else {
                Color.RP.Night.land
            }
        }
    }

    // MARK: Options and actions

    @ViewBuilder
    private var optionRow: some View {
        switch style {
        case .nightHighway, .roadAtlas:
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
        case .print:
            PrintBackdropRow(backdrop: $backdrop, pickerItem: $printPicker, hasPhoto: printPhoto != nil)
        case .terrain:
            Text(isLocked(.terrain)
                 ? String(localized: "The preview shows a sample trip.", comment: "Share sheet, Terrain without Pro: under the sample.")
                 : String(localized: "3D relief · downloads elevation once per area", comment: "Share sheet, Terrain: what it does."))
                .font(RPType.statLabel)
                .foregroundStyle(Color.RP.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            if let image = exported[style] {
                ShareLink(item: image, preview: SharePreview("RoadPrint trip card", image: image)) {
                    Text("Share")
                }
                .buttonStyle(.rpPrimary)
                .accessibilityIdentifier("shareCardButton")
                #if DEBUG
                .accessibilityValue(Text(verbatim: style.rawValue))
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

    /// Print: edit the layout (the editor, over this backdrop), or share what the preview shows.
    private var printButtons: some View {
        HStack(spacing: RPSpace.s) {
            Button {
                editingPrint = true
            } label: {
                Text("Edit layout", comment: "Share sheet: open the Print card editor (move and hide blocks).")
            }
            .buttonStyle(.rpSecondary)
            .disabled(printCard == nil)
            .accessibilityIdentifier("printEditButton")
            Group {
                if let printFile {
                    ShareLink(item: printFile, preview: SharePreview("RoadPrint trip card")) {
                        Text(backdrop == .clear
                             ? String(localized: "Share sticker", comment: "Share sheet: share the Print card as a transparent sticker.")
                             : String(localized: "Share"))
                    }
                    .buttonStyle(.rpPrimary)
                    .accessibilityIdentifier("shareCardButton")
                    #if DEBUG
                    .accessibilityValue(Text(verbatim: ShareCardStyle.print.rawValue))
                    #endif
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: RPSize.buttonHeight)
                }
            }
        }
    }

    @ViewBuilder
    private var terrainButton: some View {
        if isLocked(.terrain) {
            Button {
                paywall = .tappedTerrain
                lastPaywall = .tappedTerrain
            } label: {
                Text("Unlock Terrain with Pro", comment: "Share sheet: opens the paywall from the Terrain preview.")
            }
            .buttonStyle(.rpPrimary)
            .accessibilityIdentifier("terrainUnlock")
        } else {
            switch terrain {
            case .ready:
                if let image = exported[.terrain] {
                    ShareLink(item: image, preview: SharePreview("RoadPrint trip card", image: image)) {
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
                Button {} label: { Text("Share") }
                    .buttonStyle(.rpPrimary)
                    .disabled(true)
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
    }

    private var terrainMessage: String {
        if case .offline = terrain {
            return String(localized: "Terrain will be ready when you're back online. The other cards work offline.",
                          comment: "Share sheet: the Terrain card needs a connection to download elevation for the trip's area.")
        }
        return String(localized: "The Terrain card couldn't be drawn for this trip. Share another card instead.",
                      comment: "Share sheet: the Terrain card failed for another reason.")
    }

    // MARK: Making the cards

    /// Draws the chosen card's video into a temporary file for the share sheet.
    private func makeVideo() async {
        guard let card = cards[style] else { return }
        video = nil
        videoFailed = false
        videoProgress = 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoadPrint-trip-\(card.style.rawValue).mp4")
        do {
            try await CardVideo.write(to: url, size: M.size, scale: M.exportScale,
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
        case .terrain: if !isLocked(.terrain) { await prepareTerrain() }
        case .nightHighway, .roadAtlas: await prepareMapCard(style)
        }
    }

    /// The card is drawn only from the share summary, never from the trip (AGENTS.md §7b.3).
    private var summary: TripShareSummary? {
        TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true))
    }

    private func preparePrint() async {
        if printCard != nil { return }
        guard let summary else { return }
        let input = PrintCardContent.input(summary: summary, unit: environment.profile.distanceUnit,
                                           startLabel: startLabel, endLabel: endLabel, careerMeters: careerMeters)
        let (light, dark) = await Task.detached(priority: .userInitiated) {
            (PrintCard.layout(input, ink: .light, mode: .full, measurer: CoreTextMeasurer.shared),
             PrintCard.layout(input, ink: .dark, mode: .full, measurer: CoreTextMeasurer.shared))
        }.value
        guard !Task.isCancelled else { return }
        printCard = PrintPrepared(input: input, light: light, dark: dark, road: summary.mainRoad)
    }

    /// The Print picture as the preview shows it: 1080 × 1920, over the backdrop, or a transparent sticker.
    private func exportPrint() async {
        guard let printCard else { return }
        printFile = nil
        let image = ShareAssets.backdrop(backdrop, photo: printPhoto)
        let layout = printCard.layout(backdrop.ink(photo: printPhoto))
        let renderer = ImageRenderer(content: PrintCardView(layout: layout, road: printCard.road, photo: image))
        renderer.scale = M.exportScale
        renderer.isOpaque = image != nil
        guard let data = renderer.uiImage?.pngData(), !Task.isCancelled else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoadPrint-print-\(backdrop.rawValue).png")
        if (try? data.write(to: url, options: .atomic)) != nil { printFile = url }
    }

    private func prepareTerrain() async {
        if case .ready = terrain, exported[.terrain] != nil { return }
        guard let summary else {
            terrain = .failed
            return
        }
        terrain = .loading(0)
        do {
            let prepared = try await TerrainCardPipeline.prepare(
                summary: summary, unit: environment.profile.distanceUnit, startLabel: startLabel, endLabel: endLabel,
                progress: { value in Task { @MainActor in if case .loading = terrain { terrain = .loading(value * 0.8) } } })
            guard !Task.isCancelled else { return }
            let renderer = ImageRenderer(content: TerrainCardView(card: prepared))
            renderer.scale = M.exportScale
            if let image = renderer.uiImage { exported[.terrain] = Image(uiImage: image) }
            withAnimation(.easeOut(duration: 0.35)) { terrain = .ready(prepared) }
        } catch is CancellationError {
            if case .loading = terrain { terrain = .idle }
            return
        } catch TerrainCardPipeline.Failure.offline {
            terrain = .offline
        } catch {
            terrain = .failed
        }
    }

    private func prepareMapCard(_ style: ShareCardStyle) async {
        if cards[style] != nil, exported[style] != nil { return }
        let unit = environment.profile.distanceUnit
        guard let summary else { return }
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
        cards[style] = Prepared(style: style, content: content, scene: scene, elevation: elevation)
        let renderer = ImageRenderer(content: ShareCard(style: style, content: content, scene: scene, elevation: elevation))
        renderer.scale = M.exportScale
        if let image = renderer.uiImage { exported[style] = Image(uiImage: image) }
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
