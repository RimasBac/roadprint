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
}

/// The framing state the renderer needs; fields are the implementer's choice.
public struct TerrainCamera: Sendable, Codable, Hashable {
    // TODO(ROA-125): lon0, lat0, cx, cy, y0, gd, gw, s, el, p, horizonY, nearY, …
}

public struct TerrainRibbonPoint: Sendable, Hashable, Codable {
    /// Screen position of the point at its recorded altitude (not lifted), export px.
    public var position: CardPoint
    /// Start of a recording gap or invalid altitude: no line from the previous point; the app draws a
    /// straight dotted link from the last valid point to the next valid one.
    public var gap: Bool
    /// Hidden behind relief (ADR 0001 visibility): drawn as the x-ray dash on the ground.
    public var hidden: Bool
    /// Recorded altitude, metres; nil for gap points.
    public var elevation: Double?
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
    /// Index into `ribbon` of the highest valid recorded point, if any.
    public var summitIndex: Int?
    public var zoom: Int
    /// Vertical exaggeration used (0 in `.flat`), for the preview stamp and tests.
    public var exaggeration: Double
}

/// Where the summit label goes (terrain-previews.mjs `summitSvg`): the marker on the lifted ribbon, a
/// vertical leader, and the text block's top-left corner. Lines: kicker, value, optional name.
public struct TerrainSummitLabel: Sendable, Hashable {
    public var marker: CardPoint
    public var leaderEnd: CardPoint
    /// Baselines of the lines in order, and the shared left x.
    public var x: Double
    public var baselines: [Double]
}

public enum TerrainCard {
    /// Tile budget (ADR 0006 point 2). Engineering configuration, not a token.
    public static let maxTiles = 160

    /// Frames the card and lists the tiles to fetch (`render()` in terrain_relief.py up to the mosaic).
    /// Nil when there is nothing to frame (no valid route points, or fewer than 1 place).
    public static func plan(_ request: TerrainRequest) -> TerrainPlan? {
        fatalError("TODO(ROA-125): TerrainCard.plan")
    }

    /// Renders the relief from the fetched tiles (missing tiles: treat their heights as 0 and keep going;
    /// the app only calls this with every tile present). Deterministic for the same input.
    /// Port of terrain_relief.py `render()`: mesh, light, occlusion, snow, water, route light, haze,
    /// sky, painter's order far to near, 2× supersampling, then the ribbon projection and visibility.
    public static func render(_ request: TerrainRequest, plan: TerrainPlan, tiles: [TerrainTileID: TerrainTile],
                              landCover: TerrainLandCover) -> TerrainRender {
        fatalError("TODO(ROA-125): TerrainCard.render")
    }

    /// Places the summit label (kicker, value, optional name) like `summitSvg` in terrain-previews.mjs:
    /// above/below × open side/other side, then leaders ×1.5 and ×2; inside the side safe area, within
    /// the route band (from 150 px above `routeBandTop` to 40 px below `routeBandBottom`), off the ribbon.
    public static func summitLabel(render: TerrainRender, kicker: String, value: String, name: String?,
                                   measurer: some CardTextMeasuring) -> TerrainSummitLabel? {
        fatalError("TODO(ROA-125): TerrainCard.summitLabel")
    }
}
