import Foundation

// Terrain share card style 5 (Design/cards/terrain/README.md, docs/adr/0006): the relief renderer.
// A Foundation-only port of Tools/design/terrain_relief.py plus the overlay geometry of
// Tools/design/terrain-previews.mjs (ribbon segments, ends, summit label placement, place pins).
//
// CONTRACT (owned by the app integration): the public types and signatures in this file are what
// App/Share uses. Implement the bodies; add internal helpers freely (other files are fine). Change a
// public signature only if it is wrong, and say why in your report.

/// A Terrarium elevation tile (AWS Terrain Tiles, Web Mercator, 256 × 256 px).
public struct TerrainTileID: Sendable, Hashable, Codable {
    public var z: Int
    public var x: Int
    public var y: Int
    public init(z: Int, x: Int, y: Int) { self.z = z; self.x = x; self.y = y }
    /// `{base}/{z}/{x}/{y}.png`, e.g. base "https://s3.amazonaws.com/elevation-tiles-prod/terrarium".
    public func path() -> String { "\(z)/\(x)/\(y).png" }
}

/// A decoded tile: 256 × 256 pixels of 8-bit RGB(A), row 0 at the north edge. The app decodes the PNG.
/// Height in metres = R × 256 + G + B ÷ 256 − 32768.
public struct TerrainTile: Sendable {
    public var width: Int
    public var height: Int
    /// 3 (RGB) or 4 (RGBA).
    public var bytesPerPixel: Int
    public var pixels: [UInt8]
    public init(width: Int, height: Int, bytesPerPixel: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.bytesPerPixel = bytesPerPixel; self.pixels = pixels
    }
}

/// The bundled land-cover colour: Natural Earth I (`NE1_LR_LC`) resampled to a global equirectangular
/// grid (row 0 = 90° N, column 0 = 180° W), 8-bit RGB. The app decodes the bundled PNG.
public struct TerrainLandCover: Sendable {
    public var width: Int
    public var height: Int
    public var rgb: [UInt8]
    public init(width: Int, height: Int, rgb: [UInt8]) { self.width = width; self.height = height; self.rgb = rgb }
}

public enum TerrainMode: String, Sendable, Codable {
    /// The route at its recorded altitude.
    case route
    /// Hide route: framed on the two named places' city centres; pins, no route, no route light.
    case places
    /// No usable absolute altitude: the land with no height (k = 0), the route at plane height.
    case flat
}

/// What the card is about. Built by the app from a `TripShareSummary`.
public struct TerrainRequest: Sendable {
    public var mode: TerrainMode
    /// The privacy-filtered route; each segment break is a recording gap. Points without altitude
    /// are gaps too (ADR 0001). Ignored in `.places` mode.
    public var route: [RouteSegment]
    /// `.places`: the two named places' centres (never trip points).
    public var places: [GeoPoint]
    public init(mode: TerrainMode, route: [RouteSegment], places: [GeoPoint]) {
        self.mode = mode; self.route = route; self.places = places
    }
}

/// The framing and the tiles it needs. Cheap: no elevation involved. Codable so the app can cache it.
public struct TerrainPlan: Sendable, Codable, Hashable {
    /// Zoom 6–11, chosen so a tile pixel matches the mesh spacing, within `maxTiles`.
    public var zoom: Int
    public var tiles: [TerrainTileID]
    // Implementation fields (camera, footprint, projection origin…) are up to the renderer; keep
    // them Codable and Hashable.
    public var camera: TerrainCamera
    public init(zoom: Int, tiles: [TerrainTileID], camera: TerrainCamera) {
        self.zoom = zoom; self.tiles = tiles; self.camera = camera
    }
}

/// The framing state the renderer needs (terrain_relief.py `render()` up to the mosaic). Ground
/// coordinates are local metres (x east, y north) from (`lon0`, `lat0`), equirectangular with
/// x = (lon − lon0)·cos(lat0)·M, y = (lat − lat0)·M, M = metres per degree. The camera tokens
/// (perspective, elevation, horizonY, nearY) are read from `CardTokens.Terrain` at render time.
public struct TerrainCamera: Sendable, Codable, Hashable {
    /// Projection origin, degrees: the centre of the framed points' bounding box.
    public var lon0: Double
    public var lat0: Double
    /// Centre of the framed points, local metres (the screen's centre line is x = cx).
    public var cx: Double
    public var cy: Double
    /// Ground y (north, metres) of the near edge, depth 0.
    public var y0: Double
    /// Ground depth from the near edge to the horizon, metres.
    public var groundDepth: Double
    /// Scale at the near edge, export px per ground metre.
    public var scale: Double
    /// Ground width of the near edge, metres (export width ÷ scale).
    public var groundWidth: Double
    /// Ground metres per elevation-tile pixel at `lat0` for the plan's zoom.
    public var metresPerPixel: Double
    /// The mosaic: tile columns `tileX0...tileX1` (not wrapped at the antimeridian) and rows
    /// `tileY0...tileY1` at the plan's zoom; the mesh's bounding box plus 0.05°.
    public var tileX0: Int
    public var tileX1: Int
    public var tileY0: Int
    public var tileY1: Int
    public init(lon0: Double, lat0: Double, cx: Double, cy: Double, y0: Double, groundDepth: Double, scale: Double,
                groundWidth: Double, metresPerPixel: Double, tileX0: Int, tileX1: Int, tileY0: Int, tileY1: Int) {
        self.lon0 = lon0; self.lat0 = lat0; self.cx = cx; self.cy = cy; self.y0 = y0; self.groundDepth = groundDepth
        self.scale = scale; self.groundWidth = groundWidth; self.metresPerPixel = metresPerPixel
        self.tileX0 = tileX0; self.tileX1 = tileX1; self.tileY0 = tileY0; self.tileY1 = tileY1
    }
}

public struct TerrainRibbonPoint: Sendable, Hashable, Codable {
    /// Screen position of the point at its recorded altitude (not lifted), export px. Points without
    /// a recorded altitude sit on the ground at the base height.
    public var position: CardPoint
    /// No line from the previous point to this one: the first point after a recording gap (a segment
    /// break) or a point without a usable altitude.
    ///
    /// Drawing rule: the points on the ribbon are those with an `elevation` (in `.flat`: every point).
    /// Between two consecutive points on the ribbon `a` and `b`, draw the solid (or x-ray, if `b` is
    /// `hidden`) line when `b` directly follows `a` and `b.gap` is false; otherwise the straight dotted
    /// gap link from `a` to `b`.
    public var gap: Bool
    /// Hidden behind relief (ADR 0001 visibility): drawn as the x-ray dash on the ground.
    public var hidden: Bool
    /// Recorded altitude, metres; nil when the point has no usable altitude.
    public var elevation: Double?
    public init(position: CardPoint, gap: Bool, hidden: Bool, elevation: Double?) {
        self.position = position; self.gap = gap; self.hidden = hidden; self.elevation = elevation
    }
}

/// A rendered relief and the geometry the overlays need.
public struct TerrainRender: Sendable {
    public var width: Int
    public var height: Int
    /// Opaque sRGB, 4 bytes per pixel (R, G, B, 255), row 0 at the top.
    public var rgba: [UInt8]
    /// The route as projected points, in route order (empty in `.places` mode).
    public var ribbon: [TerrainRibbonPoint]
    /// `.places`: the pins' screen positions, in request order.
    public var places: [CardPoint]
    /// Index into `ribbon` of the highest valid recorded point, if any (first of equals; nil in `.flat`
    /// and `.places`).
    public var summitIndex: Int?
    public var zoom: Int
    /// Vertical exaggeration used (0 in `.flat`), for the preview stamp and tests.
    public var exaggeration: Double
    public init(width: Int, height: Int, rgba: [UInt8], ribbon: [TerrainRibbonPoint], places: [CardPoint],
                summitIndex: Int?, zoom: Int, exaggeration: Double) {
        self.width = width; self.height = height; self.rgba = rgba; self.ribbon = ribbon; self.places = places
        self.summitIndex = summitIndex; self.zoom = zoom; self.exaggeration = exaggeration
    }
}

/// Where the summit label goes (terrain-previews.mjs `summitSvg`): the marker on the lifted ribbon, a
/// vertical leader, and the text block's top-left corner. Lines: kicker, value, optional name.
public struct TerrainSummitLabel: Sendable, Hashable {
    public var marker: CardPoint
    public var leaderEnd: CardPoint
    /// Baselines of the lines in order, and the shared left x.
    public var x: Double
    public var baselines: [Double]
    public init(marker: CardPoint, leaderEnd: CardPoint, x: Double, baselines: [Double]) {
        self.marker = marker; self.leaderEnd = leaderEnd; self.x = x; self.baselines = baselines
    }
}

public enum TerrainCard {
    /// Tile budget (ADR 0006 point 2). Engineering configuration, not a token.
    public static let maxTiles = 160

    /// Frames the card and lists the tiles to fetch (`render()` in terrain_relief.py up to the mosaic).
    /// Nil when there is nothing to frame (no valid route points, or fewer than 1 place).
    public static func plan(_ request: TerrainRequest) -> TerrainPlan? {
        TerrainRenderer.plan(request)
    }

    /// Renders the relief from the fetched tiles (missing tiles: treat their heights as 0 and keep going;
    /// the app only calls this with every tile present). Deterministic for the same input.
    /// Port of terrain_relief.py `render()`: mesh, light, occlusion, snow, water, route light, haze,
    /// sky, painter's order far to near, 2× supersampling, then the ribbon projection and visibility.
    public static func render(_ request: TerrainRequest, plan: TerrainPlan, tiles: [TerrainTileID: TerrainTile],
                              landCover: TerrainLandCover) -> TerrainRender {
        TerrainRenderer.render(request, plan: plan, tiles: tiles, landCover: landCover)
    }

    /// Places the summit label (kicker, value, optional name) like `summitSvg` in terrain-previews.mjs:
    /// above/below × open side/other side, then leaders ×1.5 and ×2; inside the side safe area, within
    /// the route band (from 150 px above `routeBandTop` to 40 px below `routeBandBottom`), off the ribbon.
    /// Lines are measured as drawn: upper-cased (`CardText.uppercased`) where the type token says so.
    /// Nil when the render has no summit.
    public static func summitLabel(render: TerrainRender, kicker: String, value: String, name: String?,
                                   measurer: some CardTextMeasuring) -> TerrainSummitLabel? {
        TerrainRenderer.summitLabel(render: render, kicker: kicker, value: value, name: name, measurer: measurer)
    }
}
