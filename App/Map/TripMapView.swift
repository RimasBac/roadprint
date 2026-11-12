import SwiftUI
import OSLog
import RoadPrintCore

/// The route on RoadPrint's own map. Static art: no pan, zoom or taps, so it never steals the summary's scroll.
struct TripMapView: View {
    let input: MapSceneInput
    var unit: DistanceUnit = .miles
    /// Play the route draw once (after End Trip). False when a saved trip is reopened.
    var animateDraw: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scene: MapScene?
    @State private var builtSize: CGSize = .zero
    @State private var routeProgress: Double = 0
    @State private var detailOpacity: Double = 0
    @State private var cached: CachedMap?
    @State private var showSpinner = false
    @State private var played = false
    @State private var buildStarted: ContinuousClock.Instant?
    @State private var loggedFirstFrame = false

    private static let log = Logger(subsystem: "com.rimasbac.roadprint", category: "map")

    private struct CachedMap {
        var image: Image
        var key: String
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.RP.background
                content(size: proxy.size)
                if showSpinner && scene == nil { ProgressView() }
            }
            .task(id: TaskKey(size: proxy.size, scheme: scheme, typeSize: clampedTypeSize)) { await build(size: proxy.size) }
        }
        .clipped()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("tripMap")
    }

    /// Canvas redraws per frame with interpolated progress values.
    private struct AnimatedMapCanvas: View, @preconcurrency Animatable {
        var base: MapSceneRenderer
        var progress: Double
        var detail: Double
        var animatableData: AnimatablePair<Double, Double> {
            get { .init(progress, detail) }
            set { progress = newValue.first; detail = newValue.second }
        }
        var body: some View {
            var r = base
            let _ = (r.routeProgress = progress, r.detailOpacity = detail)
            Canvas { context, _ in r.draw(&context) }
        }
    }

    private struct TaskKey: Equatable { let size: CGSize; let scheme: ColorScheme; let typeSize: DynamicTypeSize }

    /// Map labels are art: they stop growing at XXL (the VoiceOver label carries the same information).
    private var clampedTypeSize: DynamicTypeSize { min(typeSize, .xxLarge) }

    private var renderKey: String { "\(scheme)-\(clampedTypeSize)-\(Int(builtSize.width))x\(Int(builtSize.height))" }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let scene {
            if let cached, cached.key == renderKey, routeProgress >= 1, detailOpacity >= 1 {
                cached.image.resizable().frame(width: size.width, height: size.height)
            } else {
                AnimatedMapCanvas(base: renderer(scene), progress: routeProgress, detail: detailOpacity)
                    .onAppear { logFirstFrame() }
            }
        } else {
            Color.RP.land.opacity(0.0)
        }
    }

    private func renderer(_ scene: MapScene) -> MapSceneRenderer {
        let summitName = String(localized: "Highest point")
        let altitude = scene.summit.map { Self.altitudeText($0.altitudeMeters, unit: unit) } ?? ""
        return MapSceneRenderer(scene: scene, scheme: scheme, displayScale: displayScale, summitName: summitName,
                                summitAltitude: altitude, routeProgress: routeProgress, detailOpacity: detailOpacity)
    }

    private func build(size: CGSize) async {
        guard size.width > 100, size.height > 100 else { return }
        let started = ContinuousClock.now
        buildStarted = started
        let spinner = Task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { showSpinner = true } }
        let input = input
        let built: MapScene? = await Task.detached(priority: .userInitiated) {
            guard let places = try? PlaceIndex.bundled() else { return nil }
            return try? MapSceneBuilder.build(input: input, places: places, size: (size.width, size.height))
        }.value
        spinner.cancel(); showSpinner = false
        guard let built else { Self.log.error("Map scene build failed"); return }
        Self.log.info("map scene build \(started.duration(to: .now).description, privacy: .public)")
        scene = built; builtSize = size
        cached = nil
        let shouldAnimate = animateDraw && !played
        played = true
        if shouldAnimate && !reduceMotion {
            routeProgress = 0; detailOpacity = 0
            withAnimation(RPMotion.routeDraw) { routeProgress = 1 }
            try? await Task.sleep(for: .seconds(RPMotion.routeDrawDuration))
            withAnimation(RPMotion.standard) { detailOpacity = 1 }
            try? await Task.sleep(for: .seconds(RPMotion.standardDuration))
        } else if shouldAnimate {
            routeProgress = 1; detailOpacity = 0
            withAnimation(RPMotion.fast) { detailOpacity = 1 }
            try? await Task.sleep(for: .seconds(RPMotion.fastDuration))
        } else {
            routeProgress = 1; detailOpacity = 1
        }
        snapshot(built, size: size)
    }

    private func logFirstFrame() {
        guard !loggedFirstFrame, let start = buildStarted else { return }
        loggedFirstFrame = true
        Self.log.info("map first frame \(start.duration(to: .now).description, privacy: .public)")
    }

    /// Render the finished map once so scrolling never redraws the Canvas or the blur.
    @MainActor
    private func snapshot(_ scene: MapScene, size: CGSize) {
        let r = renderer(scene)
        let view = ZStack {
            Color.RP.background
            Canvas { context, _ in r.draw(&context) }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        let imageRenderer = ImageRenderer(content: view)
        imageRenderer.scale = displayScale
        guard let ui = imageRenderer.uiImage else { return }
        if !loggedFirstFrame { logFirstFrame() }
        Self.log.info("map image cached bytes=\(ui.pngData()?.count ?? 0, privacy: .public)")
        cached = CachedMap(image: Image(uiImage: ui), key: renderKey)
    }

    static func altitudeText(_ meters: Double, unit: DistanceUnit) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        let value = Measurement(value: meters, unit: UnitLength.meters)
        return formatter.string(from: unit == .miles ? value.converted(to: .feet) : value)
    }

    private var accessibilityLabel: String {
        guard let s = scene?.accessibilitySummary else { return String(localized: "Route map") }
        let list = ListFormatter.localizedString(byJoining: s.orderedRegionNames)
        var parts = [String(localized: "Route map.")]
        if let a = s.startName, let b = s.endName {
            parts.append(String(localized: "\(a) to \(b), through \(list).", comment: "Map accessibility: start to end, regions"))
        } else if !list.isEmpty {
            parts.append(String(localized: "Through \(list)."))
        }
        if let summit = scene?.summit {
            parts.append(String(localized: "Highest point \(Self.altitudeText(summit.altitudeMeters, unit: unit))."))
        }
        return parts.joined(separator: " ")
    }
}
