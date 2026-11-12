import SwiftUI
import RoadPrintCore

/// Draws a laid-out `MapScene`. No projection, collision or label placement lives here (AGENTS.md §7.5).
struct MapSceneRenderer {
    let scene: MapScene
    let scheme: ColorScheme
    let displayScale: CGFloat
    let summitName: String
    let summitAltitude: String
    /// 0...1: how much of the route is drawn (route draw animation).
    var routeProgress: Double = 1
    /// 0...1: summit, area and region labels.
    var detailOpacity: Double = 1

    private var theme: RPTheme.Draw { RPTheme.draw(for: scheme) }

    func draw(_ context: inout GraphicsContext) {
        for layer in scene.drawOrder {
            switch layer {
            case .landFill: drawLand(&context)
            case .regionBorders: drawBorders(&context, kind: .region)
            case .countryBorders: drawBorders(&context, kind: .country)
            case .routeGlow: if theme.routeGlow { drawGlow(&context) }
            case .route: drawRoute(&context)
            case .areaCircles: drawAreas(&context)
            case .summit: drawSummit(&context)
            case .labels: drawLabels(&context)
            }
        }
    }

    private func path(_ points: [PlanePoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.x, y: point.y)) }
        return p
    }

    private func ringsPath(_ rings: [[PlanePoint]]) -> Path {
        var p = Path()
        for ring in rings { p.addPath(path(ring)); p.closeSubpath() }
        return p
    }

    private func drawLand(_ c: inout GraphicsContext) {
        for outline in scene.outlines {
            c.fill(ringsPath(outline.rings), with: .color(Color.RP.land), style: FillStyle(eoFill: true))
        }
    }

    private func drawBorders(_ c: inout GraphicsContext, kind: MapScene.Outline.Kind) {
        let width = kind == .region ? RPSize.hairline(displayScale: displayScale) : RPStroke.countryBorder
        for outline in scene.outlines where outline.kind == kind {
            c.stroke(ringsPath(outline.rings), with: .color(Color.RP.border),
                     style: StrokeStyle(lineWidth: width, lineCap: .butt))
        }
    }

    /// Recorded routes trimmed together by cumulative length so the line draws start to end.
    private func recordedPaths() -> [Path] {
        let recorded = scene.routes.filter { $0.kind == .recorded }
        func length(_ r: MapScene.Route) -> Double {
            zip(r.points, r.points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        }
        let total = max(recorded.map(length).reduce(0, +), 0.001)
        var drawn = 0.0
        var result: [Path] = []
        for route in recorded {
            let share = length(route) / total
            let from = drawn, to = drawn + share
            drawn = to
            let local = min(max((routeProgress - from) / max(share, 0.0001), 0), 1)
            if local > 0 { result.append(path(route.points).trimmedPath(from: 0, to: local)) }
        }
        return result
    }

    private func drawGlow(_ c: inout GraphicsContext) {
        let paths = recordedPaths()
        guard !paths.isEmpty else { return }
        c.drawLayer { layer in
            layer.addFilter(.blur(radius: RPStroke.routeGlowBlur))
            layer.opacity = RPOpacity.routeGlow * routeProgress
            for p in paths {
                layer.stroke(p, with: .color(Color.RP.route),
                             style: StrokeStyle(lineWidth: RPStroke.routeGlow, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func drawRoute(_ c: inout GraphicsContext) {
        for route in scene.routes where route.kind == .gap {
            c.stroke(path(route.points), with: .color(Color.RP.textSecondary),
                     style: StrokeStyle(lineWidth: RPStroke.gap, lineCap: .round, lineJoin: .round, dash: [0.01, RPSize.gapDotSpacing]))
        }
        let paths = recordedPaths()
        if !theme.routeGlow {
            for p in paths {
                c.stroke(p, with: .color(Color.RP.routeEdge),
                         style: StrokeStyle(lineWidth: RPStroke.route + theme.routeEdgeExtra, lineCap: .round, lineJoin: .round))
            }
        }
        for p in paths {
            c.stroke(p, with: .color(Color.RP.route),
                     style: StrokeStyle(lineWidth: RPStroke.route, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawAreas(_ c: inout GraphicsContext) {
        guard detailOpacity > 0 else { return }
        c.drawLayer { layer in
            layer.opacity = detailOpacity
            for area in [scene.startArea, scene.endArea].compactMap({ $0 }) {
                let r = area.radius
                let circle = Path(ellipseIn: CGRect(x: area.center.x - r, y: area.center.y - r, width: r * 2, height: r * 2))
                layer.fill(circle, with: .color(Color.RP.route.opacity(theme.areaFillOpacity)))
                layer.stroke(circle, with: .color(theme.routeGlow ? Color.RP.route : Color.RP.routeEdge),
                             style: StrokeStyle(lineWidth: RPStroke.areaCircle, dash: [RPSize.areaDash, RPSize.areaDash]))
                let d = RPSize.mapDotRadius
                let dot = Path(ellipseIn: CGRect(x: area.center.x - d, y: area.center.y - d, width: d * 2, height: d * 2))
                layer.stroke(dot, with: .color(Color.RP.background), lineWidth: RPStroke.mapDotRing)
                layer.fill(dot, with: .color(Color.RP.route))
            }
        }
    }

    private func drawSummit(_ c: inout GraphicsContext) {
        guard detailOpacity > 0, let summit = scene.summit else { return }
        let x = summit.position.x, y = summit.position.y, w = RPSize.summitWidth, h = RPSize.summitHeight
        var tri = Path()
        tri.move(to: CGPoint(x: x, y: y - h / 2))
        tri.addLine(to: CGPoint(x: x + w / 2, y: y + h / 2))
        tri.addLine(to: CGPoint(x: x - w / 2, y: y + h / 2))
        tri.closeSubpath()
        c.drawLayer { layer in
            layer.opacity = detailOpacity
            layer.stroke(tri, with: .color(theme.summitOutlineOnBackground ? Color.RP.background : Color.RP.land),
                         style: StrokeStyle(lineWidth: RPStroke.summitOutline, lineJoin: .round))
            layer.fill(tri, with: .color(Color.RP.text))
        }
    }

    private func drawLabels(_ c: inout GraphicsContext) {
        guard detailOpacity > 0 else { return }
        c.drawLayer { layer in
            layer.opacity = detailOpacity
            for label in scene.regionLabels {
                let text = Text(label.text.uppercased()).font(RPType.regionLabel).tracking(RPType.regionLabelTracking)
                layer.draw(layer.resolve(text.foregroundColor(Color.RP.textSecondary.opacity(RPOpacity.regionLabel))),
                           at: CGPoint(x: label.anchor.x, y: label.anchor.y), anchor: .center)
            }
            for area in [scene.startArea, scene.endArea] {
                guard let label = area?.label else { continue }
                let text = Text(label.text).font(RPType.mapLabel).foregroundColor(Color.RP.textSecondary)
                layer.draw(layer.resolve(text), at: CGPoint(x: label.anchor.x, y: label.anchor.y), anchor: .center)
            }
            if let box = scene.summit?.labelBounds {
                let name = Text(summitName).font(RPType.mapLabel.weight(.semibold)).foregroundColor(Color.RP.text)
                let alt = Text(summitAltitude).font(RPType.mapLabel).foregroundColor(Color.RP.textSecondary)
                let resolvedName = layer.resolve(name)
                let nameHeight = resolvedName.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height
                layer.draw(resolvedName, at: CGPoint(x: box.x, y: box.y), anchor: .topLeading)
                layer.draw(layer.resolve(alt), at: CGPoint(x: box.x, y: box.y + nameHeight + 2), anchor: .topLeading)
            }
        }
    }
}
