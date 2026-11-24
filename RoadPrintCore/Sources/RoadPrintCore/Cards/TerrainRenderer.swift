import Foundation

// Terrain style 5 relief: the implementation behind `TerrainCard` (TerrainCard.swift). A port of
// Tools/design/terrain_relief.py `render()` and the summit placement of terrain-previews.mjs.
// Hot loops run on flat Float/UInt8 buffers through unsafe pointers; everything is serial and
// deterministic (same input, same bytes).

private typealias TT = CardTokens.Terrain

/// Engineering configuration (not tokens): mesh size, footprint, supersampling.
enum TerrainConfig {
    static let width = Int(TT.Export.width)
    static let height = Int(TT.Export.height)
    static let meshRows = 820
    static let meshCols = 700
    /// ADR 0006 point 8.
    static let minFootprint = 60_000.0
    static let superSample = 2
    static let earthRadius = 6_371_008.8
    static let metresPerDegree = earthRadius * Double.pi / 180
    static let tileSize = 256
    /// Rows of the mesh start this far below the near edge; each row bleeds this far past each side.
    static let nearBleed = 120.0
    static let sideBleed = 60.0
}

/// Ground depth ↔ screen y for the perspective camera (terrain_relief.py `ys_of`, `d_of`, `fsc`).
struct TerrainProjection {
    let p = TT.Camera.perspective
    let elevation = TT.Camera.elevationDeg * Double.pi / 180
    let horizonY = TT.Layout.horizonY
    let nearY = TT.Layout.nearY
    var span: Double { nearY - horizonY }
    var lnP: Double { log1p(p) }
    /// Screen y of ground depth d at base height.
    func screenY(depth d: Double) -> Double { nearY - span * log1p(p * d) / lnP }
    /// Ground depth of screen y (at base height).
    func depth(screenY y: Double) -> Double { (pow(1 + p, (nearY - y) / span) - 1) / p }
    /// Perspective scale at depth d.
    func scale(depth d: Double) -> Double { 1 / (1 + p * d) }
}

/// Web Mercator in 256-px tile pixels at zoom z (terrain_relief.py `merc`).
@inline(__always) func terrainMercator(lon: Double, lat: Double, zoom z: Int) -> (x: Double, y: Double) {
    let n = Double(1 << z) * 256
    let la = min(max(lat, -85), 85) * Double.pi / 180
    return ((lon + 180) / 360 * n, (1 - log(tan(la) + 1 / cos(la)) / Double.pi) / 2 * n)
}

private struct RGBf { var r: Float; var g: Float; var b: Float }

private func hexColor(_ hex: String) -> RGBf {
    var s = Substring(hex)
    if s.hasPrefix("#") { s = s.dropFirst() }
    let v = UInt32(s, radix: 16) ?? 0
    return RGBf(r: Float((v >> 16) & 0xff), g: Float((v >> 8) & 0xff), b: Float(v & 0xff))
}

@inline(__always) private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

/// scipy.ndimage 'reflect' boundary (d c b a | a b c d).
@inline(__always) private func reflectIndex(_ i: Int, _ n: Int) -> Int {
    if i >= 0 && i < n { return i }
    let period = 2 * n
    var m = i % period
    if m < 0 { m += period }
    return m < n ? m : period - 1 - m
}

/// Bilinear sample with edge clamping (scipy `map_coordinates(order=1, mode='nearest')`).
@inline(__always) private func bilinear(_ a: UnsafePointer<Float>, _ w: Int, _ h: Int, _ u: Double, _ v: Double) -> Float {
    let uc = min(max(u, 0), Double(w - 1)), vc = min(max(v, 0), Double(h - 1))
    let x0 = Int(uc), y0 = Int(vc)
    let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
    let fx = Float(uc - Double(x0)), fy = Float(vc - Double(y0))
    let r0 = y0 * w, r1 = y1 * w
    let top = a[r0 + x0] * (1 - fx) + a[r0 + x1] * fx
    let bot = a[r1 + x0] * (1 - fx) + a[r1 + x1] * fx
    return top * (1 - fy) + bot * fy
}

/// Separable gaussian (scipy `gaussian_filter`, truncate 4, mode 'reflect'), in place.
func terrainGaussianBlur(_ a: inout [Float], width w: Int, height h: Int, sigma: Double) {
    let radius = Int(4 * sigma + 0.5)
    guard radius >= 1, w > 0, h > 0 else { return }
    var kd = (0...(2 * radius)).map { i -> Double in let x = Double(i - radius); return exp(-0.5 * x * x / (sigma * sigma)) }
    let sum = kd.reduce(0, +)
    kd = kd.map { $0 / sum }
    let kern = kd.map { Float($0) }
    let taps = 2 * radius + 1
    var tmp = [Float](repeating: 0, count: w * h)
    var line = [Float](repeating: 0, count: w + 2 * radius)
    kern.withUnsafeBufferPointer { k in
        a.withUnsafeMutableBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { dst in
                line.withUnsafeMutableBufferPointer { ln in
                    // horizontal: src -> dst
                    for y in 0..<h {
                        let row = y * w
                        for i in 0..<(w + 2 * radius) { ln[i] = src[row + reflectIndex(i - radius, w)] }
                        for x in 0..<w {
                            var acc: Float = 0
                            for t in 0..<taps { acc += k[t] * ln[x + t] }
                            dst[row + x] = acc
                        }
                    }
                    // vertical: dst -> src, row by row
                    for y in 0..<h {
                        let out = y * w
                        for x in 0..<w { src[out + x] = 0 }
                        for t in 0..<taps {
                            let sy = reflectIndex(y + t - radius, h) * w
                            let wt = k[t]
                            for x in 0..<w { src[out + x] += wt * dst[sy + x] }
                        }
                    }
                }
            }
        }
    }
}

/// Uniform grid of route segments (local metres) for the route light's distance query.
private struct SegmentGrid {
    var ax: [Double] = [], ay: [Double] = [], bx: [Double] = [], by: [Double] = []
    var minX = 0.0, minY = 0.0, cell = 1.0
    var nx = 0, ny = 0
    var start: [Int] = []
    var items: [Int32] = []

    init(xs: [Double], ys: [Double], cell: Double) {
        guard !xs.isEmpty else { return }
        let n = xs.count
        if n == 1 {
            ax = xs; ay = ys; bx = xs; by = ys
        } else {
            ax = Array(xs[0..<(n - 1)]); ay = Array(ys[0..<(n - 1)])
            bx = Array(xs[1..<n]); by = Array(ys[1..<n])
        }
        self.cell = max(cell, 1)
        minX = xs.min()!; minY = ys.min()!
        nx = Int((xs.max()! - minX) / self.cell) + 1
        ny = Int((ys.max()! - minY) / self.cell) + 1
        var counts = [Int](repeating: 0, count: nx * ny + 1)
        func range(_ s: Int) -> (Int, Int, Int, Int) {
            let x0 = Int((min(ax[s], bx[s]) - minX) / self.cell), x1 = Int((max(ax[s], bx[s]) - minX) / self.cell)
            let y0 = Int((min(ay[s], by[s]) - minY) / self.cell), y1 = Int((max(ay[s], by[s]) - minY) / self.cell)
            return (min(x0, nx - 1), min(x1, nx - 1), min(y0, ny - 1), min(y1, ny - 1))
        }
        for s in 0..<ax.count {
            let (x0, x1, y0, y1) = range(s)
            for gy in y0...y1 { for gx in x0...x1 { counts[gy * nx + gx + 1] += 1 } }
        }
        for i in 1..<counts.count { counts[i] += counts[i - 1] }
        start = counts
        items = [Int32](repeating: 0, count: counts[nx * ny])
        var fill = counts
        for s in 0..<ax.count {
            let (x0, x1, y0, y1) = range(s)
            for gy in y0...y1 { for gx in x0...x1 { items[fill[gy * nx + gx]] = Int32(s); fill[gy * nx + gx] += 1 } }
        }
    }

    /// Squared distance to the nearest segment if closer than `r`, else nil.
    func nearestSquared(_ x: Double, _ y: Double, within r: Double) -> Double? {
        guard nx > 0 else { return nil }
        let gx0 = Int(floor((x - r - minX) / cell)), gx1 = Int(floor((x + r - minX) / cell))
        let gy0 = Int(floor((y - r - minY) / cell)), gy1 = Int(floor((y + r - minY) / cell))
        if gx1 < 0 || gy1 < 0 || gx0 >= nx || gy0 >= ny { return nil }
        var best = r * r
        var found = false
        for gy in max(gy0, 0)...min(gy1, ny - 1) {
            for gx in max(gx0, 0)...min(gx1, nx - 1) {
                let c = gy * nx + gx
                var i = start[c]
                let e = start[c + 1]
                while i < e {
                    let s = Int(items[i]); i += 1
                    let dx = bx[s] - ax[s], dy = by[s] - ay[s]
                    let l2 = dx * dx + dy * dy
                    var t = l2 > 0 ? ((x - ax[s]) * dx + (y - ay[s]) * dy) / l2 : 0
                    t = min(max(t, 0), 1)
                    let ex = ax[s] + t * dx - x, ey = ay[s] + t * dy - y
                    let d2 = ex * ex + ey * ey
                    if d2 < best { best = d2; found = true }
                }
            }
        }
        return found ? best : nil
    }
}

enum TerrainRenderer {
    // MARK: plan

    @inline(__always) static func validAltitude(_ a: Double?) -> Double? {
        guard let a, a.isFinite else { return nil }
        return a
    }

    /// The points the card is framed on and the padding (route or the hide-route places).
    static func framing(_ request: TerrainRequest) -> (points: [GeoPoint], padding: Double)? {
        switch request.mode {
        case .places:
            let pts = request.places.filter { $0.latitude.isFinite && $0.longitude.isFinite }
            guard !pts.isEmpty else { return nil }
            return (pts, TT.HiddenRoute.framePadding)
        case .route, .flat:
            let pts = request.route.flatMap(\.points).filter { $0.latitude.isFinite && $0.longitude.isFinite }
            if request.mode == .route && !pts.contains(where: { validAltitude($0.altitude) != nil }) { return nil }
            guard !pts.isEmpty else { return nil }
            return (pts.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }, TT.Layout.routePadding)
        }
    }

    static func tileRange(lonMin: Double, latMin: Double, lonMax: Double, latMax: Double, zoom z: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        let a = terrainMercator(lon: lonMin, lat: latMax, zoom: z), b = terrainMercator(lon: lonMax, lat: latMin, zoom: z)
        let ts = Double(TerrainConfig.tileSize)
        return (Int(floor(a.x / ts)), Int(floor(b.x / ts)), Int(floor(a.y / ts)), Int(floor(b.y / ts)))
    }

    static func metresPerPixel(lat: Double, zoom z: Int) -> Double {
        2 * Double.pi * TerrainConfig.earthRadius * cos(lat * Double.pi / 180) / (256 * Double(1 << z))
    }

    static func plan(_ request: TerrainRequest) -> TerrainPlan? {
        guard let (pts, pad) = framing(request) else { return nil }
        let M = TerrainConfig.metresPerDegree
        let W = Double(TerrainConfig.width)
        let lats = pts.map(\.latitude), lons = pts.map(\.longitude)
        let lat0 = (lats.min()! + lats.max()!) / 2, lon0 = (lons.min()! + lons.max()!) / 2
        let kx = cos(lat0 * Double.pi / 180) * M
        let rx = lons.map { ($0 - lon0) * kx }, ry = lats.map { ($0 - lat0) * M }
        let pr = TerrainProjection()
        let L = TT.Layout.self
        let side = TT.SafeArea.side
        let dLo = pr.depth(screenY: L.routeBandBottom), dHi = pr.depth(screenY: L.routeBandTop)
        let dMid = pr.depth(screenY: (L.routeBandTop + L.routeBandBottom) / 2)
        let cx = (rx.min()! + rx.max()!) / 2, cy = (ry.min()! + ry.max()!) / 2
        // Ground depth gd sets the scale: s = A p / (sin(el) gd) px per metre at the near edge.
        let A = pr.span / pr.lnP
        var gd = max((ry.max()! - ry.min()!) * (1 + 2 * pad) / (dHi - dLo), 1.0)
        for _ in 0..<12 {
            let s = A * pr.p / (sin(pr.elevation) * gd)
            let y0 = cy - dMid * gd
            var wmax = 0.0
            for i in rx.indices { wmax = max(wmax, abs(rx[i] - cx) * pr.scale(depth: (ry[i] - y0) / gd)) }
            let wneed = max(wmax * 2 * (1 + pad) * s, 1e-9)
            let grow = max(wneed / (W - 2 * side), TerrainConfig.minFootprint / (W / s), 1.0)
            if grow < 1.001 { break }
            gd *= grow
        }
        let s = A * pr.p / (sin(pr.elevation) * gd)
        let y0 = cy - dMid * gd

        // The mesh's bounding box: rows from below the card to the horizon; the far row is widest.
        let rows = TerrainConfig.meshRows, cols = TerrainConfig.meshCols
        let nearRowY = L.nearY + TerrainConfig.nearBleed
        let dNear = pr.depth(screenY: nearRowY), dFar = pr.depth(screenY: L.horizonY)
        let halfOf = { (d: Double) in (W / 2 + TerrainConfig.sideBleed) / (s * pr.scale(depth: d)) }
        let halfFar = max(halfOf(dFar), halfOf(dNear))
        let lonMin = (cx - halfFar) / kx + lon0, lonMax = (cx + halfFar) / kx + lon0
        let latMin = (y0 + dNear * gd) / M + lat0, latMax = (y0 + dFar * gd) / M + lat0
        let rowStep = (L.horizonY - nearRowY) / Double(rows - 1)
        let spacing = 2 * halfOf(pr.depth(screenY: nearRowY + Double(rows / 3) * rowStep)) / Double(cols)

        // pick_zoom: the finest zoom whose pixel is about the mesh spacing, within the tile budget.
        // The budget counts the tiles actually fetched (the box plus 0.05°).
        let m = 0.05
        var zoom = 6
        for z in stride(from: 11, through: 6, by: -1) {
            let px = metresPerPixel(lat: lat0, zoom: z)
            let r = tileRange(lonMin: lonMin - m, latMin: latMin - m, lonMax: lonMax + m, latMax: latMax + m, zoom: z)
            let n = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1)
            if px >= spacing * 0.6 && n <= TerrainCard.maxTiles { zoom = z; break }
        }
        let r = tileRange(lonMin: lonMin - m, latMin: latMin - m, lonMax: lonMax + m, latMax: latMax + m, zoom: zoom)
        let n = 1 << zoom
        var tiles: [TerrainTileID] = []
        var seen = Set<TerrainTileID>()
        for ty in r.y0...r.y1 where ty >= 0 && ty < n {
            for tx in r.x0...r.x1 {
                let id = TerrainTileID(z: zoom, x: ((tx % n) + n) % n, y: ty)
                if seen.insert(id).inserted { tiles.append(id) }
            }
        }
        let camera = TerrainCamera(lon0: lon0, lat0: lat0, cx: cx, cy: cy, y0: y0, groundDepth: gd, scale: s,
                                   groundWidth: W / s, metresPerPixel: metresPerPixel(lat: lat0, zoom: zoom),
                                   tileX0: r.x0, tileX1: r.x1, tileY0: r.y0, tileY1: r.y1)
        return TerrainPlan(zoom: zoom, tiles: tiles, camera: camera)
    }

    // MARK: render

    static func render(_ request: TerrainRequest, plan: TerrainPlan, tiles: [TerrainTileID: TerrainTile],
                       landCover: TerrainLandCover) -> TerrainRender {
        let cam = plan.camera, z = plan.zoom
        let pr = TerrainProjection()
        let W = TerrainConfig.width, H = TerrainConfig.height, Wd = Double(W)
        let M = TerrainConfig.metresPerDegree
        let kx = cos(cam.lat0 * Double.pi / 180) * M
        let flat = request.mode == .flat, places = request.mode == .places
        let rows = TerrainConfig.meshRows, cols = TerrainConfig.meshCols, nv = rows * cols
        let el = pr.elevation, cosEl = cos(el)

        // ---- elevation mosaic (metres, float32), lightly smoothed against aliasing in far rows ----
        let ts = TerrainConfig.tileSize
        let ntx = max(cam.tileX1 - cam.tileX0 + 1, 1), nty = max(cam.tileY1 - cam.tileY0 + 1, 1)
        let mw = ntx * ts, mh = nty * ts
        var dem = [Float](repeating: 0, count: mw * mh)
        let nWorld = 1 << z
        dem.withUnsafeMutableBufferPointer { d in
            for ty in 0..<nty {
                let gy = cam.tileY0 + ty
                guard gy >= 0 && gy < nWorld else { continue }
                for tx in 0..<ntx {
                    let gx = (((cam.tileX0 + tx) % nWorld) + nWorld) % nWorld
                    guard let t = tiles[TerrainTileID(z: z, x: gx, y: gy)] else { continue }
                    let bpp = t.bytesPerPixel
                    guard bpp >= 3, t.width >= ts, t.height >= ts, t.pixels.count >= t.width * t.height * bpp else { continue }
                    t.pixels.withUnsafeBufferPointer { src in
                        for r in 0..<ts {
                            let row = (ty * ts + r) * mw + tx * ts
                            var o = r * t.width * bpp
                            for c in 0..<ts {
                                let h = Float(src[o]) * 256 + Float(src[o + 1]) + Float(src[o + 2]) / 256 - 32768
                                d[row + c] = max(h, -50)
                                o += bpp
                            }
                        }
                    }
                }
            }
        }
        terrainGaussianBlur(&dem, width: mw, height: mh, sigma: 0.8)

        // ---- occlusion blur: gaussian(dem, radiusMeters) on a block-averaged grid (same result, fast) ----
        let sigmaOcc = TT.Occlusion.radiusMeters / cam.metresPerPixel
        let f = max(1, Int(sigmaOcc / 2))
        let bw = (mw + f - 1) / f, bh = (mh + f - 1) / f
        var blur = [Float](repeating: 0, count: bw * bh)
        dem.withUnsafeBufferPointer { d in
            blur.withUnsafeMutableBufferPointer { b in
                for by in 0..<bh {
                    let ya = by * f, yb = min(ya + f, mh)
                    for bx in 0..<bw {
                        let xa = bx * f, xb = min(xa + f, mw)
                        var acc: Float = 0
                        for y in ya..<yb { for x in xa..<xb { acc += d[y * mw + x] } }
                        b[by * bw + bx] = acc / Float((yb - ya) * (xb - xa))
                    }
                }
            }
        }
        let sigmaCoarse = sqrt(max(sigmaOcc * sigmaOcc - Double(f * f - 1) / 12, 0.25)) / Double(f)
        terrainGaussianBlur(&blur, width: bw, height: bh, sigma: sigmaCoarse)
        let blurOffset = Double(f - 1) / 2, invF = 1 / Double(f)

        // ---- mesh: rows evenly spaced on screen (row 0 near, below the card; last row at the horizon) ----
        let nearRowY = TT.Layout.nearY + TerrainConfig.nearBleed
        let rowStep = (TT.Layout.horizonY - nearRowY) / Double(rows - 1)
        var rowD = [Double](repeating: 0, count: rows), rowF = rowD, rowHalf = rowD, rowYg = rowD, rowV = rowD, rowLC = rowD
        let ox = Double(cam.tileX0 * ts), oy = Double(cam.tileY0 * ts)
        let lcW = landCover.width, lcH = landCover.height
        let lcOK = lcW > 0 && lcH > 0 && landCover.rgb.count >= lcW * lcH * 3
        let cellX = lcOK ? 360 / Double(lcW) : 1, cellY = lcOK ? 180 / Double(lcH) : 1
        for i in 0..<rows {
            let d = pr.depth(screenY: nearRowY + Double(i) * rowStep)
            rowD[i] = d; rowF[i] = pr.scale(depth: d)
            rowHalf[i] = (Wd / 2 + TerrainConfig.sideBleed) / (cam.scale * rowF[i])
            rowYg[i] = cam.y0 + d * cam.groundDepth
            let lat = rowYg[i] / M + cam.lat0
            rowV[i] = terrainMercator(lon: 0, lat: lat, zoom: z).y - oy - 0.5
            rowLC[i] = (90 - lat) / cellY - 0.5
        }
        let colT = (0..<cols).map { -1 + 2 * Double($0) / Double(cols - 1) }
        let worldPx = Double(nWorld) * 256

        var hv = [Float](repeating: 0, count: nv)       // height, metres (≥ 0)
        var gxs = [Float](repeating: 0, count: nv)      // d(dem)/d(px), east
        var gys = [Float](repeating: 0, count: nv)      // d(dem)/d(row), south
        var occM = [Float](repeating: 0, count: nv)     // dem − blur
        var raw = [UInt8](repeating: 0, count: nv * 3)  // land cover
        var water = [UInt8](repeating: 0, count: nv)
        var landHeights: [Float] = []
        landHeights.reserveCapacity(nv)
        var allHeights: [Float] = []

        dem.withUnsafeBufferPointer { dp in
            let d = dp.baseAddress!
            blur.withUnsafeBufferPointer { bp in
                let b = bp.baseAddress!
                landCover.rgb.withUnsafeBufferPointer { lc in
                    // gradient of the dem at a pixel (numpy.gradient: central, one-sided at the edges)
                    @inline(__always) func gradX(_ x: Int, _ y: Int) -> Float {
                        let r = y * mw
                        if x == 0 { return d[r + 1] - d[r] }
                        if x == mw - 1 { return d[r + x] - d[r + x - 1] }
                        return (d[r + x + 1] - d[r + x - 1]) * 0.5
                    }
                    @inline(__always) func gradY(_ x: Int, _ y: Int) -> Float {
                        if y == 0 { return d[mw + x] - d[x] }
                        if y == mh - 1 { return d[y * mw + x] - d[(y - 1) * mw + x] }
                        return (d[(y + 1) * mw + x] - d[(y - 1) * mw + x]) * 0.5
                    }
                    for i in 0..<rows {
                        let v = rowV[i]
                        let vc = min(max(v, 0), Double(mh - 1))
                        let y0 = Int(vc), y1 = min(y0 + 1, mh - 1)
                        let fy = Float(vc - Double(y0))
                        let lr = rowLC[i]
                        for j in 0..<cols {
                            let k = i * cols + j
                            let X = cam.cx + colT[j] * rowHalf[i]
                            let lon = X / kx + cam.lon0
                            let u = (lon + 180) / 360 * worldPx - ox - 0.5
                            let h = bilinear(d, mw, mh, u, v)
                            let uc = min(max(u, 0), Double(mw - 1))
                            let x0 = Int(uc), x1 = min(x0 + 1, mw - 1)
                            let fx = Float(uc - Double(x0))
                            gxs[k] = (gradX(x0, y0) * (1 - fx) + gradX(x1, y0) * fx) * (1 - fy)
                                + (gradX(x0, y1) * (1 - fx) + gradX(x1, y1) * fx) * fy
                            gys[k] = (gradY(x0, y0) * (1 - fx) + gradY(x1, y0) * fx) * (1 - fy)
                                + (gradY(x0, y1) * (1 - fx) + gradY(x1, y1) * fx) * fy
                            occM[k] = h - bilinear(b, bw, bh, (u - blurOffset) * invF, (v - blurOffset) * invF)
                            // land cover (bilinear, rounded like ndimage on uint8)
                            var rmin: UInt8 = 255
                            if lcOK {
                                let lcU = min(max((lon + 180) / cellX - 0.5, 0), Double(lcW - 1))
                                let lcV = min(max(lr, 0), Double(lcH - 1))
                                let cx0 = Int(lcU), cy0 = Int(lcV)
                                let cx1 = min(cx0 + 1, lcW - 1), cy1 = min(cy0 + 1, lcH - 1)
                                let ax = lcU - Double(cx0), ay = lcV - Double(cy0)
                                for q in 0..<3 {
                                    let p00 = Double(lc[(cy0 * lcW + cx0) * 3 + q]), p01 = Double(lc[(cy0 * lcW + cx1) * 3 + q])
                                    let p10 = Double(lc[(cy1 * lcW + cx0) * 3 + q]), p11 = Double(lc[(cy1 * lcW + cx1) * 3 + q])
                                    let val = (p00 * (1 - ax) + p01 * ax) * (1 - ay) + (p10 * (1 - ax) + p11 * ax) * ay
                                    let c = UInt8(min(max(val.rounded(), 0), 255))
                                    raw[k * 3 + q] = c
                                    rmin = min(rmin, c)
                                }
                            } else {
                                raw[k * 3] = 128; raw[k * 3 + 1] = 128; raw[k * 3 + 2] = 128; rmin = 128
                            }
                            let sea = h <= 0 && !flat
                            let hp = max(h, 0)
                            hv[k] = hp
                            if !sea { landHeights.append(hp) }
                            water[k] = (sea || (rmin > 250 && hp < 2000)) ? 1 : 0
                        }
                    }
                }
            }
        }
        if landHeights.isEmpty { allHeights = hv }

        // ---- exaggeration from the land's height span ----
        func percentile(_ sorted: [Float], _ q: Double) -> Double {
            let pos = q / 100 * Double(sorted.count - 1)
            let lo = Int(pos.rounded(.down)), hi = min(lo + 1, sorted.count - 1)
            return Double(sorted[lo]) + (Double(sorted[hi]) - Double(sorted[lo])) * (pos - Double(lo))
        }
        let sortedLand = (landHeights.isEmpty ? allHeights : landHeights).sorted()
        landHeights = []; allHeights = []
        let pLo = percentile(sortedLand, 2), pHi = percentile(sortedLand, 99.5)
        let span = max(pHi - pLo, TT.Land.minSpanMeters)
        let ex = TT.Camera.Exaggeration.self
        let k = flat ? 0 : min(max(ex.targetReliefRatio * cam.groundWidth / (span * cosEl), ex.min), ex.max)
        let hbase = pLo

        // ---- light, colour, water, route light, haze, sky fade; screen positions ----
        let hs = TT.Hillshade.self
        let az = hs.lightAzimuthDeg * Double.pi / 180, alt = hs.lightAltitudeDeg * Double.pi / 180
        let lx = sin(az) * cos(alt), ly = cos(az) * cos(alt), lz = sin(alt)
        let key = hexColor(hs.keyColor), ambRaw = hexColor(hs.ambientColor)
        let ambMax = Double(max(ambRaw.r, ambRaw.g, ambRaw.b))
        let amb = SIMD3<Double>(Double(ambRaw.r), Double(ambRaw.g), Double(ambRaw.b)) / ambMax
        let keyC = SIMD3<Double>(Double(key.r), Double(key.g), Double(key.b)) / 255
        func v3(_ c: RGBf) -> SIMD3<Double> { SIMD3(Double(c.r), Double(c.g), Double(c.b)) }
        let snowArr = v3(hexColor(TT.Snow.color)), waterArr = v3(hexColor(TT.Water.color))
        let routeArr = v3(hexColor(TT.RouteLight.color)), hazeArr = v3(hexColor(TT.Haze.color))
        let skyC = hexColor(TT.Sky.horizon), skyArr = v3(skyC)
        let lcTok = TT.LandCover.self
        let oc = TT.Occlusion.self
        let pxm = cam.metresPerPixel

        // route in local metres, all points in order (gaps included, like the reference)
        let routePts = request.route.flatMap(\.points).filter { $0.latitude.isFinite && $0.longitude.isFinite }
        let routeX = routePts.map { ($0.longitude - cam.lon0) * kx }, routeY = routePts.map { ($0.latitude - cam.lat0) * M }
        let rl = TT.RouteLight.self
        let cutoff = 6.0   // gaussian sigmas; beyond this the light is < 1e-7
        let grid: SegmentGrid? = places || routePts.isEmpty ? nil
            : SegmentGrid(xs: routeX, ys: routeY, cell: cutoff * rl.radius / cam.scale)

        var color = [Float](repeating: 0, count: nv * 3)
        var sx = [Double](repeating: 0, count: nv), sy = [Double](repeating: 0, count: nv)
        let ssd = Double(TerrainConfig.superSample)
        for i in 0..<rows {
            let d = rowD[i], fr = rowF[i]
            let ysBase = pr.screenY(depth: d)
            let yScale = k * cosEl * fr * cam.scale
            let dc = min(max(d, 0), 1)
            let haze = TT.Haze.farOpacity * pow(dc, TT.Haze.curve)
            let far = smoothstep(1 - TT.EdgeFade.far, 1, dc)
            let sig = rl.radius / (cam.scale * fr)
            let Yg = rowYg[i]
            for j in 0..<cols {
                let idx = i * cols + j
                let h = Double(hv[idx])
                sx[idx] = (Wd / 2 + colT[j] * (Wd / 2 + TerrainConfig.sideBleed)) * ssd
                sy[idx] = (ysBase - (h - hbase) * yScale) * ssd
                // light
                var light = SIMD3<Double>(repeating: 1)
                var occ = 1.0
                if !flat {
                    let dzdx = k * Double(gxs[idx]) / pxm, dzdy = -k * Double(gys[idx]) / pxm
                    let nx = -dzdx, ny = -dzdy
                    let len = (nx * nx + ny * ny + 1).squareRoot()
                    let lam = max(0, (nx * lx + ny * ly + lz) / len)
                    light = pointwiseMin(SIMD3(repeating: hs.max), hs.ambient * amb + (hs.diffuse * lam) * keyC)
                    occ = min(max(1 + oc.strength * Double(occM[idx]) / span, oc.min), oc.max)
                }
                // land-cover grade: lum + (c − lum)·saturation, ^gamma ·brightness
                let c0 = SIMD3<Double>(Double(raw[idx * 3]), Double(raw[idx * 3 + 1]), Double(raw[idx * 3 + 2])) / 255
                let lum = c0.x * 0.299 + c0.y * 0.587 + c0.z * 0.114
                var g = lum + (c0 - lum) * lcTok.saturation
                g = pointwiseMin(pointwiseMax(g, SIMD3(repeating: 0)), SIMD3(repeating: 1))
                var c = SIMD3(pow(g.x, lcTok.gamma), pow(g.y, lcTok.gamma), pow(g.z, lcTok.gamma)) * (lcTok.brightness * 255)
                let snow = flat ? 0 : smoothstep(TT.Snow.startMeters, TT.Snow.fullMeters, h) * TT.Snow.opacity
                c = c * (1 - snow) + snowArr * snow
                c = c * light * occ
                // water: 3×3 mean of the mask (uniform_filter, reflect), smoothstep 0.25..0.75
                var wsum = 0
                for di in -1...1 {
                    let ii = min(max(i + di, 0), rows - 1)
                    for dj in -1...1 { wsum += Int(water[ii * cols + min(max(j + dj, 0), cols - 1)]) }
                }
                let wq = smoothstep(0.25, 0.75, Double(wsum) / 9)
                c = c * (1 - wq) + waterArr * wq
                // route light: warm gaussian spill around the route
                if let grid, let d2 = grid.nearestSquared(cam.cx + colT[j] * rowHalf[i], Yg, within: cutoff * sig) {
                    c += routeArr * (rl.intensity * exp(-0.5 * d2 / (sig * sig)))
                }
                c = c * (1 - haze) + hazeArr * haze
                c = c * (1 - far) + skyArr * far
                c = pointwiseMin(pointwiseMax(c, SIMD3(repeating: 0)), SIMD3(repeating: 255))
                color[idx * 3] = Float(c.x); color[idx * 3 + 1] = Float(c.y); color[idx * 3 + 2] = Float(c.z)
            }
        }
        hv = []; gxs = []; gys = []; occM = []; raw = []; water = []

        // ---- paint far -> near, two flat triangles per quad, 2× supersampled ----
        let ss = TerrainConfig.superSample
        let bufW = W * ss, bufH = H * ss
        var buf = [UInt8](repeating: 0, count: bufW * bufH * 3)
        let bg = hexColor(CardTokens.Color.background)
        let horizonY = TT.Layout.horizonY
        buf.withUnsafeMutableBufferPointer { bp in
            let p = bp.baseAddress!
            let skyRows = Int((horizonY + TT.Sky.bandAbove) * ssd)
            for yy in 0..<bufH {
                var r = bg.r, g = bg.g, b = bg.b
                if yy < skyRows {
                    let t = Float(smoothstep(horizonY - TT.Sky.bandAbove, horizonY + 40, Double(yy) / ssd))
                    r = (bg.r + (skyC.r - bg.r) * t).rounded(.towardZero)
                    g = (bg.g + (skyC.g - bg.g) * t).rounded(.towardZero)
                    b = (bg.b + (skyC.b - bg.b) * t).rounded(.towardZero)
                }
                let ru = UInt8(r), gu = UInt8(g), bu = UInt8(b)
                var o = yy * bufW * 3
                for _ in 0..<bufW { p[o] = ru; p[o + 1] = gu; p[o + 2] = bu; o += 3 }
            }
            color.withUnsafeBufferPointer { cp in
                let col = cp.baseAddress!
                sx.withUnsafeBufferPointer { sxp in
                    sy.withUnsafeBufferPointer { syp in
                        let X = sxp.baseAddress!, Y = syp.baseAddress!
                        let maxX = Double(bufW), maxY = Double(bufH)
                        @inline(__always) func tri(_ a: Int, _ b: Int, _ c: Int) {
                            let r = UInt8((col[a * 3] + col[b * 3] + col[c * 3]) / 3)
                            let g = UInt8((col[a * 3 + 1] + col[b * 3 + 1] + col[c * 3 + 1]) / 3)
                            let bl = UInt8((col[a * 3 + 2] + col[b * 3 + 2] + col[c * 3 + 2]) / 3)
                            terrainFillTriangle(p, bufW, bufH, X[a], Y[a], X[b], Y[b], X[c], Y[c], r, g, bl)
                        }
                        for i in stride(from: rows - 2, through: 0, by: -1) {
                            var lo = Double.infinity, hi = -Double.infinity
                            for j in 0..<cols {
                                let ya = Y[i * cols + j], yb = Y[(i + 1) * cols + j]
                                lo = min(lo, ya, yb); hi = max(hi, ya, yb)
                            }
                            if lo > maxY + 8 || hi < -8 { continue }
                            for j in 0..<(cols - 1) {
                                let a = i * cols + j
                                if X[a + 1] < 0 || X[a] > maxX { continue }
                                let b = a + 1, c = a + cols + 1, dd = a + cols
                                tri(a, c, dd)
                                tri(a, b, c)
                            }
                        }
                    }
                }
            }
        }
        color = []; sx = []; sy = []

        // ---- 2 × 2 box downsample to RGBA ----
        var rgba = [UInt8](repeating: 255, count: W * H * 4)
        buf.withUnsafeBufferPointer { bp in
            rgba.withUnsafeMutableBufferPointer { op in
                for y in 0..<H {
                    let r0 = (2 * y) * bufW * 3, r1 = (2 * y + 1) * bufW * 3
                    for x in 0..<W {
                        let a = r0 + 6 * x, b = r1 + 6 * x, o = (y * W + x) * 4
                        for q in 0..<3 {
                            let sum = Int(bp[a + q]) + Int(bp[a + 3 + q]) + Int(bp[b + q]) + Int(bp[b + 3 + q])
                            op[o + q] = UInt8((sum + 2) / 4)
                        }
                    }
                }
            }
        }
        buf = []

        // ---- route projection and visibility (bounded ray march toward the camera) ----
        let heightAt: (Double, Double) -> Double = { x, y in
            let lon = x / kx + cam.lon0, lat = y / M + cam.lat0
            let m = terrainMercator(lon: lon, lat: lat, zoom: z)
            return dem.withUnsafeBufferPointer { Double(bilinear($0.baseAddress!, mw, mh, m.x - ox - 0.5, m.y - oy - 0.5)) }
        }
        func project(_ x: Double, _ y: Double, _ zz: Double) -> CardPoint {
            let d = (y - cam.y0) / cam.groundDepth
            let fr = pr.scale(depth: d)
            return CardPoint(x: Wd / 2 + (x - cam.cx) * cam.scale * fr,
                             y: pr.screenY(depth: d) - (zz - hbase) * k * cosEl * fr * cam.scale)
        }
        var ribbon: [TerrainRibbonPoint] = []
        var placePts: [CardPoint] = []
        var summit: Int?
        if places {
            for pl in request.places where pl.latitude.isFinite && pl.longitude.isFinite {
                let x = (pl.longitude - cam.lon0) * kx, y = (pl.latitude - cam.lat0) * M
                placePts.append(project(x, y, heightAt(x, y)))
            }
        } else {
            let bias = TT.Ribbon.depthBias / (cam.scale * cosEl)
            let steps = 200, tanEl = tan(el)
            let stepM = cam.groundDepth * 0.5 / Double(steps - 1)
            for seg in request.route {
                for (pi, pt) in seg.points.enumerated() where pt.latitude.isFinite && pt.longitude.isFinite {
                    let x = (pt.longitude - cam.lon0) * kx, y = (pt.latitude - cam.lat0) * M
                    let segmentStart = pi == 0 && !ribbon.isEmpty
                    let rec = validAltitude(pt.altitude)
                    if flat {
                        ribbon.append(TerrainRibbonPoint(position: project(x, y, hbase), gap: segmentStart, hidden: false, elevation: rec))
                        continue
                    }
                    guard let zz = rec else {
                        ribbon.append(TerrainRibbonPoint(position: project(x, y, hbase), gap: true, hidden: false, elevation: nil))
                        continue
                    }
                    var hidden = false
                    for t in 1..<steps {
                        let tm = Double(t) * stepM
                        if heightAt(x, y - tm) * k - (zz * k + tm * tanEl) > bias { hidden = true; break }
                    }
                    if let s = summit, let e = ribbon[s].elevation, e >= zz {} else { summit = ribbon.count }
                    ribbon.append(TerrainRibbonPoint(position: project(x, y, zz), gap: segmentStart, hidden: hidden, elevation: zz))
                }
            }
        }
        return TerrainRender(width: W, height: H, rgba: rgba, ribbon: ribbon, places: placePts,
                             summitIndex: summit, zoom: z, exaggeration: k)
    }

    // MARK: summit label

    static func summitLabel(render: TerrainRender, kicker: String, value: String, name: String?,
                            measurer: some CardTextMeasuring) -> TerrainSummitLabel? {
        guard let si = render.summitIndex, render.ribbon.indices.contains(si) else { return nil }
        let S = TT.Summit.self, ty = TT.Typography.self
        let W = TT.Export.width, side = TT.SafeArea.side, lift = TT.Ribbon.lift
        let p = render.ribbon[si].position
        let mx = p.x, my = p.y - lift, lead = S.Leader.length
        let gap = S.Label.gapToLeader, lg = S.Label.lineGap, pp = S.Label.platePadding
        var lines: [(CardTypeToken, String, Double)] = [(ty.summitKicker, kicker, ty.summitKicker.size),
                                                         (ty.summitValue, value, ty.summitValue.size * 0.8)]
        if let name, !name.isEmpty { lines.append((ty.summitName, name, ty.summitName.size)) }
        let bw = lines.map { tok, s, _ in measurer.ink(tok.uppercase ? CardText.uppercased(s) : s, style: CardTextStyle(tok)).width }.max() ?? 0
        let bh = lines.reduce(0) { $0 + $1.2 } + lg * Double(lines.count - 1)
        let onRibbon = render.ribbon.filter { $0.elevation != nil || !$0.gap }.map { ($0.position.x, $0.position.y - lift) }
        let frameTop = TT.Layout.routeBandTop - 150, frameBot = TT.Layout.routeBandBottom + 40
        let open: Double = mx < W / 2 ? 1 : -1
        var best: (tx: Double, ly: Double, dir: Double, top: Double)?
        search: for mult in [1.0, 1.5, 2.0] {
            for dir in [-1.0, 1.0] {
                for sideSign in [open, -open] {
                    let ly = my + dir * lead * mult
                    let tx = sideSign > 0 ? mx + gap : mx - gap - bw
                    let box = dir < 0 ? CardRect(minX: tx - pp, minY: ly - bh - pp, maxX: tx + bw + pp, maxY: ly + pp)
                        : CardRect(minX: tx - pp, minY: ly - pp, maxX: tx + bw + pp, maxY: ly + bh + pp)
                    if box.minX < side - pp || box.maxX > W - side + pp || box.minY < frameTop || box.maxY > frameBot { continue }
                    if onRibbon.contains(where: { x, y in x > box.minX - 6 && x < box.maxX + 6 && y > box.minY - 6 && y < box.maxY + 6 }) { continue }
                    best = (tx, ly, dir, box.minY)
                    break search
                }
            }
        }
        if best == nil {
            let ly = my - lead
            let tx = min(max(open > 0 ? mx + gap : mx - gap - bw, side), W - side - bw)
            best = (tx, ly, -1, ly - bh - pp)
        }
        let b = best!
        var y = b.top + pp + lines[0].2
        var baselines: [Double] = []
        for (i, l) in lines.enumerated() {
            if i > 0 { y += l.2 + lg }
            baselines.append(y)
        }
        return TerrainSummitLabel(marker: CardPoint(x: mx, y: my), leaderEnd: CardPoint(x: mx, y: b.ly), x: b.tx, baselines: baselines)
    }
}

/// Scanline fill of one flat triangle into an RGB buffer: pixel centres inside the triangle
/// (top-left style half-open spans, so neighbours share edges without gaps or double hits).
@inline(__always) func terrainFillTriangle(_ p: UnsafeMutablePointer<UInt8>, _ w: Int, _ h: Int,
                                           _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                                           _ cx: Double, _ cy: Double, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
    var x0 = ax, y0 = ay, x1 = bx, y1 = by, x2 = cx, y2 = cy
    if y1 < y0 { swap(&x0, &x1); swap(&y0, &y1) }
    if y2 < y1 { swap(&x1, &x2); swap(&y1, &y2) }
    if y1 < y0 { swap(&x0, &x1); swap(&y0, &y1) }
    guard y2 > y0, y0.isFinite, y2.isFinite else { return }
    let yStart = max(0, Int(min(max((y0 - 0.5).rounded(.up), -1), Double(h))))
    let yEnd = min(h - 1, Int(min(max((y2 - 0.5).rounded(.up), -1), Double(h + 1))) - 1)
    guard yStart <= yEnd else { return }
    let invLong = (x2 - x0) / (y2 - y0)
    let invTop = y1 > y0 ? (x1 - x0) / (y1 - y0) : 0
    let invBot = y2 > y1 ? (x2 - x1) / (y2 - y1) : 0
    let maxX = Double(w)
    for iy in yStart...yEnd {
        let y = Double(iy) + 0.5
        let xl = x0 + (y - y0) * invLong
        let xs = y < y1 ? x0 + (y - y0) * invTop : x1 + (y - y1) * invBot
        let lo = min(xl, xs), hi = max(xl, xs)
        let xa = max(0, Int(min(max((lo - 0.5).rounded(.up), -1), maxX)))
        let xb = min(w - 1, Int(min(max((hi - 0.5).rounded(.up), -1), maxX + 1)) - 1)
        if xa > xb { continue }
        var o = (iy * w + xa) * 3
        for _ in xa...xb { p[o] = r; p[o + 1] = g; p[o + 2] = b; o += 3 }
    }
}
