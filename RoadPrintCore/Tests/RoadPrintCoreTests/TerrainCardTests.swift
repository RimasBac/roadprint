import Foundation
import Testing
@testable import RoadPrintCore

// Terrain style 5 relief (TerrainCard.swift, TerrainRenderer.swift): framing and tile choice, the
// rasterised relief, the ribbon projection and visibility, the hide-route and flat variants, and the
// summit label. Synthetic Terrarium tiles stand in for AWS Terrain Tiles.

// MARK: - synthetic data

/// One separable gaussian bump: amp · g(lat; lat, latSigma) · g(lon; lon, lonSigma); sigma 0 = constant.
private struct Bump: Sendable {
    var amp: Double, lat: Double, latSigma: Double, lon: Double, lonSigma: Double
    static func g(_ x: Double, _ c: Double, _ s: Double) -> Double { s == 0 ? 1 : exp(-0.5 * (x - c) * (x - c) / (s * s)) }
}

/// Heights as a sum of separable bumps, so tiles are cheap to build.
private struct SyntheticRelief: Sendable {
    var bumps: [Bump]

    func tile(_ id: TerrainTileID) -> TerrainTile {
        let n: Double = Double(1 << id.z) * 256
        var lons = [Double](repeating: 0, count: 256), lats = lons
        for i in 0..<256 {
            let fx: Double = (Double(id.x * 256 + i) + 0.5) / n
            lons[i] = fx * 360 - 180
            let fy: Double = (Double(id.y * 256 + i) + 0.5) / n
            lats[i] = atan(sinh(Double.pi * (1 - 2 * fy))) * 180 / Double.pi
        }
        let cols: [[Double]] = bumps.map { b in lons.map { Bump.g($0, b.lon, b.lonSigma) } }
        var px = [UInt8](repeating: 0, count: 256 * 256 * 3)
        for r in 0..<256 {
            let rowTerms: [Double] = bumps.map { $0.amp * Bump.g(lats[r], $0.lat, $0.latSigma) }
            for c in 0..<256 {
                var h = 0.0
                for t in bumps.indices { h += rowTerms[t] * cols[t][c] }
                let v = max(h + 32768, 0)
                let o = (r * 256 + c) * 3
                px[o] = UInt8(min(Int(v / 256), 255))
                px[o + 1] = UInt8(Int(v) % 256)
                px[o + 2] = UInt8(Int((v - v.rounded(.down)) * 256))
            }
        }
        return TerrainTile(width: 256, height: 256, bytesPerPixel: 3, pixels: px)
    }

    func tiles(for plan: TerrainPlan) -> [TerrainTileID: TerrainTile] {
        Dictionary(uniqueKeysWithValues: plan.tiles.map { ($0, tile($0)) })
    }
}

/// A small land-cover grid: green land, with a Natural Earth white (water) block in the far south-west.
private let landCover: TerrainLandCover = {
    let w = 360, h = 180
    var rgb = [UInt8](repeating: 0, count: w * h * 3)
    for r in 0..<h { for c in 0..<w {
        let o = (r * w + c) * 3
        rgb[o] = 96; rgb[o + 1] = 124; rgb[o + 2] = 70
    } }
    return TerrainLandCover(width: w, height: h, rgb: rgb)
}()

/// A road from 45.00° N 9.9° E to 45.40° N 10.1° E, an east–west ridge (3,500 m) across it at
/// 45.20° N, a recording gap (segment break) after 45.15° and one point without altitude.
private let ridgeLat = 45.20
private let relief = SyntheticRelief(bumps: [
    Bump(amp: 300, lat: 0, latSigma: 0, lon: 0, lonSigma: 0),              // a 300 m plain
    Bump(amp: 3500, lat: ridgeLat, latSigma: 0.02, lon: 10.0, lonSigma: 0.6), // the ridge
    Bump(amp: 1800, lat: 45.05, latSigma: 0.05, lon: 10.25, lonSigma: 0.05),  // a mountain beside the road
])
private func roadPoint(_ lat: Double, _ alt: Double?) -> RoutePoint { RoutePoint(latitude: lat, longitude: 10 + (lat - 45.2) * 0.5, altitude: alt) }
private let summitLat = 45.10
private let route: [RouteSegment] = [
    RouteSegment(points: stride(from: 0, through: 15, by: 1).map { i -> RoutePoint in
        let lat = 45.0 + Double(i) * 0.01
        return roadPoint(lat, abs(lat - summitLat) < 1e-9 ? 2500 : 400)
    }),
    RouteSegment(points: stride(from: 17, through: 40, by: 1).map { i -> RoutePoint in
        let lat = 45.0 + Double(i) * 0.01
        return roadPoint(lat, i == 30 ? nil : 400)
    }),
]
private let routeRequest = TerrainRequest(mode: .route, route: route, places: [])

private struct Scene: Sendable {
    let plan: TerrainPlan
    let tiles: [TerrainTileID: TerrainTile]
    let render: TerrainRender
    let again: TerrainRender
    let seconds: Double
}

private let scene: Scene = {
    let plan = TerrainCard.plan(routeRequest)!
    let tiles = relief.tiles(for: plan)
    let clock = ContinuousClock()
    let t0 = clock.now
    let a = TerrainCard.render(routeRequest, plan: plan, tiles: tiles, landCover: landCover)
    let dt = clock.now - t0
    let b = TerrainCard.render(routeRequest, plan: plan, tiles: tiles, landCover: landCover)
    let secs = Double(dt.components.seconds) + Double(dt.components.attoseconds) / 1e18
    return Scene(plan: plan, tiles: tiles, render: a, again: b, seconds: secs)
}()

/// Fixed-advance fake: 0.55 em per character.
private struct FakeMeasurer: CardTextMeasuring {
    func ink(_ text: String, style: CardTextStyle) -> CardInkBox {
        CardInkBox(x: 0, width: Double(text.count) * style.size * 0.55, top: -style.size * 0.72, bottom: 0)
    }
}

/// FNV-1a, enough to compare two buffers.
private func fnv(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

private func line(_ pts: [(Double, Double)], altitude: Double? = 1000) -> [RouteSegment] {
    [RouteSegment(points: pts.map { RoutePoint(latitude: $0.0, longitude: $0.1, altitude: altitude) })]
}

// MARK: - plan

@Test func planI80ChoosesZoom7() throws {
    let pts = try Fixtures.points("i80-slc-sac")
    let req = TerrainRequest(mode: .route, route: [RouteSegment(points: pts.map {
        RoutePoint(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude)
    })], places: [])
    let plan = try #require(TerrainCard.plan(req))
    #expect(plan.zoom == 7)
    #expect(plan.tiles.count <= TerrainCard.maxTiles)
    #expect(Set(plan.tiles).count == plan.tiles.count)
    #expect(plan.tiles.allSatisfy { $0.z == 7 })
    // Width: the route (≈ 830 km wide) fits the safe width with padding, so the near edge is wide.
    #expect(plan.camera.groundWidth > 500_000 && plan.camera.groundWidth < 900_000)
}

@Test func planBrennerChoosesZoom10() throws {
    // Innsbruck → Brenner → Bolzano along A13/A22, ends trimmed.
    let req = TerrainRequest(mode: .route, route: line([(47.21, 11.40), (47.10, 11.45), (47.00, 11.51), (46.90, 11.45),
                                                        (46.80, 11.57), (46.71, 11.65), (46.60, 11.55), (46.55, 11.40)]), places: [])
    let plan = try #require(TerrainCard.plan(req))
    #expect(plan.zoom == 10)
    #expect(plan.tiles.count <= TerrainCard.maxTiles)
    // Short route: the 60 km minimum footprint sets the near width.
    #expect(abs(plan.camera.groundWidth - 72_000) < 15_000)
}

@Test func planLongFlatRouteChoosesZoom6() throws {
    // Norseman → Ceduna, Eyre Highway.
    let req = TerrainRequest(mode: .route, route: line([(-32.20, 121.70), (-32.35, 123.60), (-31.68, 128.88),
                                                        (-31.45, 130.90), (-32.13, 133.68)], altitude: 100), places: [])
    let plan = try #require(TerrainCard.plan(req))
    #expect(plan.zoom == 6)
    #expect(plan.tiles.count <= TerrainCard.maxTiles)
}

@Test func planNeedsSomethingToFrame() throws {
    #expect(TerrainCard.plan(TerrainRequest(mode: .route, route: [], places: [])) == nil)
    #expect(TerrainCard.plan(TerrainRequest(mode: .route, route: line([(45, 10), (45.1, 10)], altitude: nil), places: [])) == nil)
    #expect(TerrainCard.plan(TerrainRequest(mode: .flat, route: line([(45, 10), (45.1, 10)], altitude: nil), places: [])) != nil)
    #expect(TerrainCard.plan(TerrainRequest(mode: .places, route: [], places: [])) == nil)
    #expect(TerrainCard.plan(TerrainRequest(mode: .places, route: [], places: [GeoPoint(latitude: 45, longitude: 10)])) != nil)
}

@Test func planIsCodableAndDeterministic() throws {
    let a = try #require(TerrainCard.plan(routeRequest)), b = try #require(TerrainCard.plan(routeRequest))
    #expect(a == b)
    let back = try JSONDecoder().decode(TerrainPlan.self, from: JSONEncoder().encode(a))
    #expect(back == a)
}

// MARK: - render

@Test func renderIsOpaqueFullSizeAndDeterministic() {
    let r = scene.render
    #expect(r.width == 1080 && r.height == 1920)
    #expect(r.rgba.count == 1080 * 1920 * 4)
    #expect(stride(from: 3, to: r.rgba.count, by: 4).allSatisfy { r.rgba[$0] == 255 })
    #expect(fnv(r.rgba) == fnv(scene.again.rgba))
    #expect(r.ribbon == scene.again.ribbon)
    #expect(r.zoom == scene.plan.zoom)
    #expect(r.exaggeration >= TT.Camera.Exaggeration.min && r.exaggeration <= TT.Camera.Exaggeration.max)
    // The land is not one colour, and the top of the card is the dusk sky, not land.
    let px = { (x: Int, y: Int) in Array(r.rgba[((y * 1080 + x) * 4)..<((y * 1080 + x) * 4 + 3)]) }
    #expect(px(10, 0) == px(1000, 0))
    #expect(px(10, 0) != px(540, 1000))
    #expect(px(540, 1000) != px(540, 1700))
}

private typealias TT = CardTokens.Terrain

@Test func ribbonHasEveryPointWithGapsAndOcclusion() throws {
    let r = scene.render
    let all = route.flatMap(\.points)
    #expect(r.ribbon.count == all.count)
    // The segment break and the point without altitude are gaps; nothing else is.
    let breakIndex = route[0].points.count
    let noAlt = breakIndex + 13
    #expect(all[noAlt].altitude == nil)
    #expect(r.ribbon[breakIndex].gap && r.ribbon[breakIndex].elevation == 400)
    #expect(r.ribbon[noAlt].gap && r.ribbon[noAlt].elevation == nil)
    #expect(r.ribbon.enumerated().filter { $0.element.gap }.map(\.offset) == [breakIndex, noAlt])
    // A valley point just north of (behind) the ridge is hidden; the first point, in the open, is not.
    let behind = try #require(all.firstIndex { $0.latitude > ridgeLat + 0.025 })
    #expect(r.ribbon[behind].hidden)
    #expect(!r.ribbon[0].hidden)
    // North is up the card: later (northern) points are higher on screen; all land in the route band.
    #expect(r.ribbon.last!.position.y < r.ribbon[0].position.y)
    for p in r.ribbon where p.elevation != nil {
        #expect(p.position.y > TT.Layout.routeBandTop - 200 && p.position.y < TT.Layout.routeBandBottom + 100)
        #expect(p.position.x > TT.SafeArea.side && p.position.x < 1080 - TT.SafeArea.side)
    }
}

@Test func summitIsTheHighestValidAltitude() throws {
    let r = scene.render
    let idx = try #require(r.summitIndex)
    #expect(r.ribbon[idx].elevation == 2500)
    #expect(abs(route.flatMap(\.points)[idx].latitude - summitLat) < 1e-9)
}

@Test func summitLabelStaysInTheSafeAreaAndTheBand() throws {
    let r = scene.render
    let m = FakeMeasurer()
    for name in [nil, "Brenner Pass"] as [String?] {
        let label = try #require(TerrainCard.summitLabel(render: r, kicker: "Highest recorded point", value: "8,202 ft", name: name, measurer: m))
        let kickerW = m.ink(CardText.uppercased("Highest recorded point"), style: CardTextStyle(TT.Typography.summitKicker)).width
        let nameW = name.map { m.ink($0, style: CardTextStyle(TT.Typography.summitName)).width } ?? 0
        let bw = max(kickerW, nameW)
        #expect(label.baselines.count == (name == nil ? 2 : 3))
        #expect(label.x >= TT.SafeArea.side)
        #expect(label.x + bw <= 1080 - TT.SafeArea.side)
        #expect(label.baselines.first! - TT.Typography.summitKicker.size >= TT.Layout.routeBandTop - 150)
        #expect(label.baselines.last! <= TT.Layout.routeBandBottom + 40)
        let s = r.ribbon[r.summitIndex!].position
        #expect(label.marker == CardPoint(x: s.x, y: s.y - TT.Ribbon.lift))
        #expect(label.leaderEnd.x == label.marker.x)
        #expect(abs(label.leaderEnd.y - label.marker.y) >= TT.Summit.Leader.length)
        #expect(zip(label.baselines, label.baselines.dropFirst()).allSatisfy { $0 < $1 })
        // Off the ribbon: no drawn ribbon point inside the text block.
        let top = label.baselines.first! - TT.Typography.summitKicker.size, bottom = label.baselines.last!
        #expect(!r.ribbon.contains { p in
            p.elevation != nil && p.position.x > label.x && p.position.x < label.x + bw
                && p.position.y - TT.Ribbon.lift > top && p.position.y - TT.Ribbon.lift < bottom
        })
    }
}

@Test func placesModeHasPinsAndNoRibbon() throws {
    let req = TerrainRequest(mode: .places, route: route, places: [GeoPoint(latitude: 45.0, longitude: 9.9), GeoPoint(latitude: 45.4, longitude: 10.1)])
    let plan = try #require(TerrainCard.plan(req))
    let r = TerrainCard.render(req, plan: plan, tiles: relief.tiles(for: plan), landCover: landCover)
    #expect(r.places.count == 2)
    #expect(r.ribbon.isEmpty)
    #expect(r.summitIndex == nil)
    #expect(r.places[0].x < r.places[1].x && r.places[0].y > r.places[1].y)
    #expect(TerrainCard.summitLabel(render: r, kicker: "k", value: "v", name: nil, measurer: FakeMeasurer()) == nil)
}

@Test func flatModeHasNoRelief() throws {
    let req = TerrainRequest(mode: .flat, route: route, places: [])
    let plan = try #require(TerrainCard.plan(req))
    #expect(plan == scene.plan)
    let r = TerrainCard.render(req, plan: plan, tiles: scene.tiles, landCover: landCover)
    #expect(r.exaggeration == 0)
    #expect(r.summitIndex == nil)
    #expect(r.ribbon.count == route.flatMap(\.points).count)
    #expect(r.ribbon.allSatisfy { !$0.hidden })
    // Only the segment break is a gap; the point without altitude still sits on the plane.
    #expect(r.ribbon.filter(\.gap).count == 1)
}

@Test func missingTilesRenderAsSeaLevel() throws {
    let r = TerrainCard.render(routeRequest, plan: scene.plan, tiles: [:], landCover: TerrainLandCover(width: 0, height: 0, rgb: []))
    #expect(r.rgba.count == 1080 * 1920 * 4)
    #expect(r.ribbon.count == route.flatMap(\.points).count)
}

@Test func renderTiming() {
    var peak = ""
    if let s = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) {
        peak = s.split(separator: "\n").first { $0.hasPrefix("VmHWM") }.map(String.init) ?? ""
    }
    print("TerrainCard.render: \(String(format: "%.2f", scene.seconds)) s, z\(scene.plan.zoom), \(scene.plan.tiles.count) tiles, k \(String(format: "%.2f", scene.render.exaggeration)) \(peak)")
    #expect(scene.seconds > 0)
}

// MARK: - flat land (terrain.flatLand, option D)

@Test func flatnessFollowsTheReliefSpan() {
    let fl = CardTokens.Terrain.FlatLand.self
    #expect(TerrainRenderer.flatness(span: 3000) == 0)
    #expect(TerrainRenderer.flatness(span: fl.mountainSpanMeters) == 0)
    #expect(TerrainRenderer.flatness(span: fl.flatSpanMeters) == 1)
    #expect(TerrainRenderer.flatness(span: 40) == 1)
    #expect(abs(TerrainRenderer.flatness(span: (fl.mountainSpanMeters + fl.flatSpanMeters) / 2) - 0.5) < 1e-12)
    #expect(TerrainRenderer.flatness(span: .nan) == 0)
}

@Test func heightColourRampSpansTheTrip() {
    let ramp: [SIMD3<Double>] = [SIMD3(0, 0, 0), SIMD3(30, 30, 30), SIMD3(60, 60, 60), SIMD3(90, 90, 90)]
    #expect(TerrainRenderer.heightColor(100, low: 100, span: 300, ramp: ramp) == SIMD3(0, 0, 0))
    #expect(TerrainRenderer.heightColor(50, low: 100, span: 300, ramp: ramp) == SIMD3(0, 0, 0))   // below the low point
    let mid = TerrainRenderer.heightColor(250, low: 100, span: 300, ramp: ramp)                  // t 0.5: between stops 1 and 2
    #expect(abs(mid.x - 45) < 1e-6)
    let top = TerrainRenderer.heightColor(900, low: 100, span: 300, ramp: ramp)                  // above: the last stop
    #expect(abs(top.x - 90) < 1e-3)
}

/// The same route over a 120 m plain with 150 m of rolling hills: fully flat land.
private let flatRelief = SyntheticRelief(bumps: [
    Bump(amp: 120, lat: 0, latSigma: 0, lon: 0, lonSigma: 0),
    Bump(amp: 150, lat: 45.15, latSigma: 0.08, lon: 10.0, lonSigma: 0.3),
])

@Test func flatLandLiftsTheReliefAndStaysDeterministic() throws {
    let tiles = flatRelief.tiles(for: scene.plan)
    let a = TerrainCard.render(routeRequest, plan: scene.plan, tiles: tiles, landCover: landCover)
    let b = TerrainCard.render(routeRequest, plan: scene.plan, tiles: tiles, landCover: landCover)
    #expect(fnv(a.rgba) == fnv(b.rgba))
    // A 150 m swell gets more height than a 3,500 m ridge, within the flat-land cap.
    #expect(a.exaggeration > scene.render.exaggeration)
    #expect(a.exaggeration <= CardTokens.Terrain.FlatLand.exaggerationMax)
}

// MARK: - sea texture (terrain.water.waves, option C4)

@Test func waterNoiseMatchesTheReference() {
    // Golden values from terrain_relief.py (numpy): the app and the reference draw the same sea.
    #expect(TerrainRenderer.waterHash(0, 0, 11) == 1835566655.0 / 4294967296)
    #expect(TerrainRenderer.waterHash(-3, 7, 29) == 2739680969.0 / 4294967296)
    #expect(TerrainRenderer.waterHash(123456, -98765, 71) == 3868578682.0 / 4294967296)
    #expect(abs(TerrainRenderer.valueNoise(2.25, -1.5, 11) - 0.5207136808749055) < 1e-15)
    #expect(TerrainRenderer.valueNoise(4, 9, 3) == TerrainRenderer.waterHash(4, 9, 3))
}

@Test func wavesFadeBeforeTheyAlias() {
    #expect(TerrainRenderer.waveHeight(x: 1234, y: 5678, wavelength: 1000, footprint: 10_000) == 0)
    let a = TerrainRenderer.waveHeight(x: 1234, y: 5678, wavelength: 1000, footprint: 20)
    #expect(a == TerrainRenderer.waveHeight(x: 1234, y: 5678, wavelength: 1000, footprint: 20))
    #expect(abs(a) < 4)
}

@Test func seaHasWavesAndShallowsAlongTheCoast() {
    let rows = 40, cols = 40
    var water = [UInt8](repeating: 1, count: rows * cols)
    for i in 0..<rows { for j in 0..<5 { water[i * cols + j] = 0 } }   // land along the west edge
    let colT = (0..<cols).map { -1 + 2 * Double($0) / Double(cols - 1) }
    let rowHalf = [Double](repeating: 1000, count: rows), rowYg = (0..<rows).map { Double($0) * 50 }
    let c = TerrainRenderer.waterColors(rows: rows, cols: cols, water: water, colT: colT, rowHalf: rowHalf, rowYg: rowYg,
                                        cx: 0, groundWidth: 20_000, light: SIMD3(-0.79, 0.46, 0.41), key: SIMD3(1, 0.85, 0.66))
    #expect(c.count == rows * cols * 3)
    func mean(_ j: Int, _ q: Int) -> Double {
        var s = 0.0
        for i in 0..<rows { s += Double(c[(i * cols + j) * 3 + q]) }
        return s / Double(rows)
    }
    #expect(mean(6, 1) > mean(35, 1) + 10)   // teal by the land, deep blue in the open
    var sum = 0.0, sumSq = 0.0
    for i in 0..<rows {
        let b = Double(c[(i * cols + 30) * 3 + 2])
        sum += b; sumSq += b * b
    }
    let m = sum / Double(rows)
    let variance = sumSq / Double(rows) - m * m
    #expect(variance > 1)   // waves, not one flat colour
}

// MARK: - parity with terrain_relief.py (opt-in)

/// RP_TERRAIN_PARITY=<dir>: renders <dir>/route.txt ("lon lat alt" per line, alt "nan" for none; a line
/// "break" starts a new segment) from <dir>/tiles/<z>-<x>-<y>.rgb and <dir>/landcover.rgb
/// (<dir>/landcover.txt: "width height"), RP_TERRAIN_MODE route|flat|places (places: the first and last
/// point), and writes <dir>/out-<mode>.ppm.
@Test func parityRender() throws {
    guard let dir = ProcessInfo.processInfo.environment["RP_TERRAIN_PARITY"] else { return }
    let mode = TerrainMode(rawValue: ProcessInfo.processInfo.environment["RP_TERRAIN_MODE"] ?? "route") ?? .route
    var segs: [[RoutePoint]] = [[]]
    for l in try String(contentsOfFile: dir + "/route.txt", encoding: .utf8).split(separator: "\n") {
        if l == "break" { segs.append([]); continue }
        let f = l.split(separator: " ").map { Double($0) ?? .nan }
        segs[segs.count - 1].append(RoutePoint(latitude: f[1], longitude: f[0], altitude: f[2].isNaN ? nil : f[2]))
    }
    let all = segs.flatMap { $0 }
    var places = [all.first!, all.last!].map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
    if let s = try? String(contentsOfFile: dir + "/places.txt", encoding: .utf8) {
        places = s.split(separator: "\n").map { l in let f = l.split(separator: " ").compactMap { Double($0) }; return GeoPoint(latitude: f[1], longitude: f[0]) }
    }
    let req = TerrainRequest(mode: mode, route: segs.map { RouteSegment(points: $0) }, places: places)
    let plan = try #require(TerrainCard.plan(req))
    var tiles: [TerrainTileID: TerrainTile] = [:]
    for id in plan.tiles {
        if let d = FileManager.default.contents(atPath: "\(dir)/tiles/\(id.z)-\(id.x)-\(id.y).rgb") {
            tiles[id] = TerrainTile(width: 256, height: 256, bytesPerPixel: 3, pixels: [UInt8](d))
        }
    }
    let dims = try String(contentsOfFile: dir + "/landcover.txt", encoding: .utf8).split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
    let lc = TerrainLandCover(width: dims[0], height: dims[1], rgb: [UInt8](try Data(contentsOf: URL(fileURLWithPath: dir + "/landcover.rgb"))))
    let status = { (key: String) in (try? String(contentsOfFile: "/proc/self/status", encoding: .utf8))?.split(separator: "\n").first { $0.hasPrefix(key) }.map(String.init) ?? "" }
    try? "5".write(toFile: "/proc/self/clear_refs", atomically: false, encoding: .utf8)   // Linux: reset VmHWM
    let before = status("VmRSS")
    let clock = ContinuousClock()
    let t0 = clock.now
    let r = TerrainCard.render(req, plan: plan, tiles: tiles, landCover: lc)
    let dt = clock.now - t0
    var ppm = Data("P6\n\(r.width) \(r.height)\n255\n".utf8)
    var rgb = [UInt8](repeating: 0, count: r.width * r.height * 3)
    for i in 0..<(r.width * r.height) { rgb[i * 3] = r.rgba[i * 4]; rgb[i * 3 + 1] = r.rgba[i * 4 + 1]; rgb[i * 3 + 2] = r.rgba[i * 4 + 2] }
    ppm.append(contentsOf: rgb)
    try ppm.write(to: URL(fileURLWithPath: "\(dir)/out-\(mode.rawValue).ppm"))
    let pts = r.ribbon.map { "{\"sx\":\($0.position.x),\"sy\":\($0.position.y),\"gap\":\($0.gap),\"hidden\":\($0.hidden)}" } + r.places.map { "{\"sx\":\($0.x),\"sy\":\($0.y)}" }
    try ("[" + pts.joined(separator: ",") + "]").write(toFile: "\(dir)/out-\(mode.rawValue).json", atomically: true, encoding: .utf8)
    let peak = "before render " + before + ", peak " + status("VmHWM")
    print("parity \(mode): \(dt), z\(plan.zoom), \(plan.tiles.count) tiles (\(tiles.count) present), k \(r.exaggeration), gw \(plan.camera.groundWidth / 1000) km, gd \(plan.camera.groundDepth / 1000) km, hidden \(r.ribbon.filter(\.hidden).count)/\(r.ribbon.count), summit \(r.summitIndex.map(String.init) ?? "-") \(peak)")
}
