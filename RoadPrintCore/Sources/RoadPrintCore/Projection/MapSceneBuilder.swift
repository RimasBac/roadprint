import Foundation

public enum MapSceneError: Error, Equatable {
    case invalidViewport
    case invalidCoordinate
    case emptyInput
    case unprojectableInput
}

public enum MapSceneBuilder {
    public static var defaultInsets: ViewportInsets {
        ViewportInsets(top: 36, left: 28, bottom: 36, right: 28)
    }

    /// A trip with a route is zoomed to that route, so a short trip still spans the
    /// view (board, 2026-11-12). The floor only keeps a degenerate route (one point,
    /// a tight loop) from being magnified to street level.
    public static let routeMinimumSpanMeters = 2_000.0
    /// A trip with nothing to draw but its privacy circle keeps regional context.
    public static let areaOnlySpanMeters = 50_000.0

    /// Fits the route symmetrically about its bounding-box centre. Reserving the
    /// maximum circle radius keeps every privacy circle within the requested
    /// insets, without shifting the route to accommodate labels.
    public static func build(input: MapSceneInput, places: PlaceIndex,
                             size: (w: Double, h: Double),
                             insets: ViewportInsets = defaultInsets) throws -> MapScene {
        let dimensions = [size.w, size.h, insets.top, insets.left, insets.bottom, insets.right]
        guard dimensions.allSatisfy(\.isFinite), size.w <= 100_000, size.h <= 100_000,
              insets.top >= 0, insets.left >= 0, insets.bottom >= 0, insets.right >= 0,
              size.w - insets.left - insets.right > 44,
              size.h - insets.top - insets.bottom > 44 else { throw MapSceneError.invalidViewport }
        let routePoints = input.segments.flatMap(\.points)
        let areas = [input.start, input.end].compactMap { $0 }
        let coordinates = routePoints.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            + areas.map { GeoCoordinate(latitude: $0.centerLatitude, longitude: $0.centerLongitude) }
        guard !coordinates.isEmpty else { throw MapSceneError.emptyInput }
        guard coordinates.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }),
              areas.allSatisfy({ $0.radiusMeters.isFinite && $0.radiusMeters >= 0 }),
              let bounds = GeoBounds(points: coordinates) else { throw MapSceneError.invalidCoordinate }
        let kind = ProjectionChooser.choose(for: bounds), projection = MapProjection(kind: kind)
        let rawRoute = routePoints.compactMap { projection.project(lat: $0.latitude, lon: $0.longitude) }
        let rawAreas = areas.compactMap { projection.project(lat: $0.centerLatitude, lon: $0.centerLongitude) }
        guard rawAreas.count == areas.count, rawRoute.count == routePoints.count else {
            throw MapSceneError.unprojectableInput
        }
        let raw = rawRoute.isEmpty ? rawAreas : rawRoute
        let cx = (raw.map(\.x).min()! + raw.map(\.x).max()!) / 2
        let cy = (raw.map(\.y).min()! + raw.map(\.y).max()!) / 2
        let all = rawRoute + rawAreas
        let rx = all.map { abs($0.x - cx) }.max()!, ry = all.map { abs($0.y - cy) }.max()!
        let reserved = ViewportInsets(top: insets.top + 22, left: insets.left + 22,
                                      bottom: insets.bottom + 22, right: insets.right + 22)
        guard let fit = ViewportFit(min: PlanePoint(x: cx - rx, y: cy - ry),
                                    max: PlanePoint(x: cx + rx, y: cy + ry),
                                    width: size.w, height: size.h, insets: reserved,
                                    minimumSpanMeters: rawRoute.isEmpty ? areaOnlySpanMeters
                                        : routeMinimumSpanMeters) else {
            throw MapSceneError.invalidViewport
        }
        func project(_ p: RoutePoint) -> PlanePoint? {
            projection.project(lat: p.latitude, lon: p.longitude).map(fit.apply)
        }
        var routes: [MapScene.Route] = [], previousEnd: PlanePoint?
        for segment in input.segments where !segment.points.isEmpty {
            let points = segment.points.compactMap(project)
            if let previousEnd, let first = points.first, previousEnd != first {
                routes.append(.init(kind: .gap, points: [previousEnd, first]))
            }
            routes.append(.init(kind: .recorded, points: SceneGeometry.simplify(points)))
            previousEnd = points.last
        }
        let view = MapRect(x: 0, y: 0, width: size.w, height: size.h)
        let labelView = MapRect(x: 8, y: 8, width: size.w - 16, height: size.h - 16)
        let outlines = makeOutlines(places: places, projection: projection, fit: fit, view: view)
        var occupied: [MapRect] = []
        func available(_ box: MapRect, routeMargin: Double, labelMargin: Double = 8) -> Bool {
            labelView.contains(box) && SceneGeometry.clear(box, of: routes, by: routeMargin)
                && occupied.allSatisfy { !box.expanded(labelMargin).intersects($0) }
        }
        var summit: MapScene.Summit?
        if let point = input.summit, let altitude = point.altitude, altitude.isFinite,
           let position = project(point), view.contains(position) {
            // Space for a localized two-line altitude label. The app scales its
            // formatted text to this box; it must not move the anchor.
            var label: MapRect?
            for side in [1.0, -1.0] {
                for offset in [0.0, 24.0, -24.0] {
                    let box = MapRect(x: side > 0 ? position.x + 10 : position.x - 110,
                                      y: position.y - 14 + offset, width: 100, height: 28)
                    if available(box, routeMargin: 6) { label = box; break }
                }
                if label != nil { break }
            }
            summit = .init(position: position, altitudeMeters: altitude, labelBounds: label)
            if let label { occupied.append(label) }
            occupied.append(MapRect(x: position.x - 4, y: position.y - 4, width: 8, height: 8))
        }
        func area(_ area: ApproximateArea?, text: String?) -> MapScene.Area? {
            guard let area, let raw = projection.project(lat: area.centerLatitude, lon: area.centerLongitude) else { return nil }
            let center = fit.apply(raw), radius = min(22, max(8, area.radiusMeters * fit.scale))
            var label: MapLabel?
            if let text, !text.isEmpty {
                let measured = MapLabelMetrics.measure(text, style: .map)
                let w = measured.width, h = measured.height, gap = radius + 6
                // Right, left, below, above. On a horizontal side, slide above
                // then below its tangent when the route blocks the centre.
                var candidates: [MapRect] = []
                for side in [1.0, -1.0] {
                    let slide = gap + h / 2
                    let offsets = [0.0] + stride(from: slide, through: max(40, slide), by: 4).map { -$0 }
                        + stride(from: slide, through: max(40, slide), by: 4).map { $0 }
                    for offset in offsets {
                        candidates.append(MapRect(x: side > 0 ? center.x + gap : center.x - gap - w,
                                                  y: center.y - h / 2 + offset, width: w, height: h))
                    }
                }
                candidates.append(MapRect(x: center.x - w / 2, y: center.y + gap, width: w, height: h))
                candidates.append(MapRect(x: center.x - w / 2, y: center.y - gap - h, width: w, height: h))
                if let box = candidates.first(where: { available($0, routeMargin: 6) }) {
                    label = MapLabel(text: text, placeCode: nil, bounds: box); occupied.append(box)
                }
            }
            return .init(center: center, radius: radius, label: label)
        }
        let start = area(input.start, text: input.startLabel), end = area(input.end, text: input.endLabel)
        let crossed = crossedPlaces(input.segments, index: places)
        let regionMode = crossed.countries.count == 1 && !crossed.regions.isEmpty
        let visible = outlines.filter { regionMode ? $0.kind == .region : $0.kind == .country }
        let labelsByDistance = visible.sorted {
            let a = crossed.distance[$0.place.code, default: 0], b = crossed.distance[$1.place.code, default: 0]
            return a == b ? $0.place.code < $1.place.code : a > b
        }
        var regionLabels: [MapLabel] = []
        for outline in labelsByDistance {
            let rings = outline.rings.map { SceneGeometry.clipRing($0, to: labelView) }.filter { !$0.isEmpty }
            guard let pole = PolygonLabelAnchor.find(rings: rings) else { continue }
            let code = outline.kind == .region ? String(outline.place.code.split(separator: "-").last!) : outline.place.code
            let measured = MapLabelMetrics.measure(code, style: .region)
            var candidates = [pole]
            let diagonal = 1 / sqrt(2.0)
            let directions: [(Double, Double)] = [(0,-1),(diagonal,-diagonal),(1,0),(diagonal,diagonal),
                                                  (0,1),(-diagonal,diagonal),(-1,0),(-diagonal,-diagonal)]
            for step in stride(from: 4.0, through: 40.0, by: 4.0) {
                candidates += directions.map { PlanePoint(x: pole.x + $0.0 * step, y: pole.y + $0.1 * step) }
            }
            for point in candidates {
                let box = MapRect(x: point.x - measured.width / 2, y: point.y - measured.height / 2,
                                  width: measured.width, height: measured.height)
                guard available(box, routeMargin: 12),
                      (box.corners + [point]).allSatisfy({ SceneGeometry.contains($0, rings: rings) }) else { continue }
                regionLabels.append(MapLabel(text: code, placeCode: outline.place.code, bounds: box))
                occupied.append(box); break
            }
        }
        return MapScene(width: size.w, height: size.h, projection: kind, pointsPerMeter: fit.scale,
                        routes: routes, outlines: outlines, regionLabels: regionLabels,
                        startArea: start, endArea: end, summit: summit, drawOrder: MapScene.Layer.allCases,
                        accessibilitySummary: .init(orderedRegionNames: crossed.regions.map(\.name),
                            countryCount: crossed.countries.count, startName: input.startLabel,
                            endName: input.endLabel, hasRecordingGap: routes.contains { $0.kind == .gap }))
    }

    private static func makeOutlines(places: PlaceIndex, projection: MapProjection,
                                     fit: ViewportFit, view: MapRect) -> [MapScene.Outline] {
        let clip = view.expanded(16)
        var samples: [GeoCoordinate] = []
        for step in 0...16 {
            let t = Double(step) / 16
            for point in [PlanePoint(x: clip.x + clip.width * t, y: clip.y),
                          PlanePoint(x: clip.x + clip.width * t, y: clip.y + clip.height),
                          PlanePoint(x: clip.x, y: clip.y + clip.height * t),
                          PlanePoint(x: clip.x + clip.width, y: clip.y + clip.height * t)] {
                let raw = PlanePoint(x: (point.x - fit.translation.x) / fit.scale,
                                     y: (fit.translation.y - point.y) / fit.scale)
                if let coordinate = projection.inverse(raw) { samples.append(coordinate) }
            }
        }
        let query: [PlaceOutline]
        if samples.count == 68, let bounds = GeoBounds(points: samples) {
            query = places.outlines(south: bounds.minLatitude, west: GeoBounds.normalize(bounds.minLongitude),
                                    north: bounds.maxLatitude, east: GeoBounds.normalize(bounds.maxLongitude))
        } else { query = places.outlines(south: -90, west: -180, north: 90, east: 180) }
        var owner: [Int] = [], projected: [[PlanePoint]] = []
        for (index, feature) in query.enumerated() {
            for ring in feature.rings {
                let points = ring.compactMap { projection.project(lat: $0.latitude, lon: $0.longitude).map(fit.apply) }
                // A ring cut by the projection horizon cannot be closed across
                // the missing hemisphere. Avoid drawing an invented border.
                guard points.count == ring.count else { continue }
                projected.append(points); owner.append(index)
            }
        }
        let simplified = SharedOutlineSimplifier.simplify(projected)
        var grouped = [[[PlanePoint]]](repeating: [], count: query.count)
        for (i, ring) in simplified.enumerated() {
            let clipped = SceneGeometry.clipRing(ring, to: clip)
            if !clipped.isEmpty { grouped[owner[i]].append(clipped) }
        }
        return query.indices.compactMap { i in
            guard !grouped[i].isEmpty else { return nil }
            return .init(kind: query[i].kind == .country ? .country : .region,
                         place: query[i].place, rings: grouped[i])
        }
    }

    private static func crossedPlaces(_ segments: [RouteSegment], index: PlaceIndex)
        -> (countries: [PlaceRef], regions: [PlaceRef], distance: [String: Double]) {
        var countries: [PlaceRef] = [], regions: [PlaceRef] = [], distance: [String: Double] = [:]
        for segment in segments {
            let crossed = index.places(along: segment.points)
            for place in crossed.countries where !countries.contains(place) { countries.append(place) }
            for place in crossed.regions where !regions.contains(place) { regions.append(place) }
            // Sample long sparse edges at <=5 km. A gap is never sampled or
            // counted as having crossed any place.
            for (a, b) in zip(segment.points, segment.points.dropFirst()) {
                let length = Geo.distance(from: a, to: b)
                let count = max(1, Int(ceil(length / 5_000)))
                let longitudeDelta = GeoBounds.normalize(b.longitude - a.longitude)
                for i in 0..<count {
                    let t = (Double(i) + 0.5) / Double(count)
                    let found = index.place(at: a.latitude + (b.latitude - a.latitude) * t,
                                           lon: a.longitude + longitudeDelta * t)
                    for place in [found.country, found.region].compactMap({ $0 }) {
                        distance[place.code, default: 0] += length / Double(count)
                    }
                }
            }
        }
        // Never let an unqualified border-jitter sample outrank a crossed place.
        let qualified = Set((countries + regions).map(\.code))
        distance = distance.filter { qualified.contains($0.key) }
        return (countries, regions, distance)
    }
}
