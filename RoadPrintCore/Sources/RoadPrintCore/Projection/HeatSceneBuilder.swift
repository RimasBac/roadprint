import Foundation

public extension MapSceneBuilder {
    /// Lays a heat map out for a view of `size`: the base map (outlines and labels) fitted to
    /// everything that was driven, and every heat line in view points.
    ///
    /// The base map is laid out from a thinned copy of the lines, so placing labels and finding
    /// the crossed places stays fast however many trips went into the heat map.
    static func buildHeat(_ heat: HeatMap, places: PlaceIndex, size: (w: Double, h: Double),
                          insets: ViewportInsets = defaultInsets) throws -> HeatScene {
        guard let first = heat.lines.first?.points.first else { throw MapSceneError.emptyInput }
        let tolerance = max(heat.cellMeters * 3, 250)
        var segments: [RouteSegment] = []
        var south = first, north = first, west = first, east = first
        for line in heat.lines {
            for point in line.points {
                if point.latitude < south.latitude { south = point }
                if point.latitude > north.latitude { north = point }
                if point.longitude < west.longitude { west = point }
                if point.longitude > east.longitude { east = point }
            }
            // Short stubs don't matter for labels; leaving them out keeps the layout fast.
            if line.points.count >= 4 {
                segments.append(RouteSegment(points: DouglasPeucker.simplify(line.points, tolerance: tolerance)))
            }
        }
        // The outermost points always take part, so the map is fitted to everything.
        for corner in [south, north, west, east] { segments.append(RouteSegment(points: [corner, corner])) }

        var input = MapSceneInput(segments: segments)
        input.connectsSegments = false
        let (scene, project) = try layout(input: input, places: places, size: size, insets: insets, labels: .map)
        let lines = heat.lines.compactMap { line -> HeatScene.Line? in
            let points = SceneGeometry.simplify(line.points.compactMap(project))
            return points.count > 1 ? HeatScene.Line(points: points, count: line.count, heat: line.heat) : nil
        }
        return HeatScene(map: scene, lines: lines, maxCount: heat.maxCount)
    }
}
