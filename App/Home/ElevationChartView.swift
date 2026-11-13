import SwiftUI
import Charts
import RoadPrintCore

/// The elevation profile of a trip (plan §4.3, mockup 1; ROA-55, first version): an amber line over a
/// soft fill, faint horizontal grid lines only, and a dot at the highest point. All numbers come
/// from the core's `ElevationProfile`; this view only draws them.
struct ElevationChartView: View {
    let profile: ElevationProfile

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale

    /// Finger position along x while scrubbing (chart units); nil when no touch.
    @State private var scrubX: Double?

    /// Plot height: 140 pt, 180 pt from XXL up (ROA-55 spec).
    private var chartHeight: CGFloat { typeSize >= .xxLarge ? 180 : 140 }
    /// A 4 pt dot: symbol area is the diameter squared.
    private static let dotArea: CGFloat = 16
    private static let summitRing: CGFloat = 1.5

    private var allSamples: [ElevationProfile.Sample] { profile.series.flatMap { $0 } }

    /// The sample nearest to the finger.
    private var scrubSample: ElevationProfile.Sample? {
        guard let x = scrubX else { return nil }
        return allSamples.min { abs($0.distance - x) < abs($1.distance - x) }
    }

    private var summitAlignment: Alignment {
        let f = profile.summit.distance / max(profile.totalDistance, 0.001)
        return f > 0.75 ? .trailing : (f < 0.25 ? .leading : .center)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RPSpace.m) {
            RPSectionTitle(title: "Elevation")
            Chart {
                ForEach(Array(profile.series.enumerated()), id: \.offset) { segment in
                    ForEach(Array(segment.element.enumerated()), id: \.offset) { sample in
                        AreaMark(x: .value("Distance", sample.element.distance),
                                 y: .value("Altitude", sample.element.altitude),
                                 series: .value("Segment", segment.offset),
                                 stacking: .unstacked)
                            .foregroundStyle(fill)
                        LineMark(x: .value("Distance", sample.element.distance),
                                 y: .value("Altitude", sample.element.altitude),
                                 series: .value("Segment", segment.offset))
                            .foregroundStyle(Color.RP.route)
                            .lineStyle(StrokeStyle(lineWidth: RPStroke.chartLine, lineCap: .round, lineJoin: .round))
                    }
                }
                if let scrub = scrubSample {
                    RuleMark(x: .value("Distance", scrub.distance))
                        .foregroundStyle(Color.RP.text.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: RPSize.hairline(displayScale: displayScale)))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(callout(distance: scrub.distance, altitude: scrub.altitude))
                                .font(RPType.axis.monospacedDigit())
                                .foregroundStyle(Color.RP.text)
                        }
                    PointMark(x: .value("Distance", scrub.distance), y: .value("Altitude", scrub.altitude))
                        .symbolSize(Self.dotArea)
                        .foregroundStyle(Color.RP.route)
                } else {
                    PointMark(x: .value("Distance", profile.summit.distance),
                              y: .value("Altitude", profile.summit.altitude))
                        .symbol {
                            Circle().fill(Color.RP.route).frame(width: 4, height: 4)
                                .overlay(Circle().stroke(Color.RP.card, lineWidth: Self.summitRing).frame(width: 4 + Self.summitRing * 2, height: 4 + Self.summitRing * 2))
                        }
                        .annotation(position: .top, alignment: summitAlignment, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(summitText)
                                .font(RPType.axis)
                                .foregroundStyle(Color.RP.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                }
            }
            .chartXSelection(value: $scrubX)
            .animation(RPMotion.fast, value: scrubX == nil)
            .sensoryFeedback(.selection, trigger: scrubSample?.distance)
            .chartXScale(domain: 0...max(profile.totalDistance, 0.001))
            .chartYScale(domain: profile.yMin...max(profile.yMax, profile.yMin + 1))
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: profile.xTicks.map(\.value)) { value in
                    // The end ticks sit on the plot's edges: anchor them inwards so they aren't dropped.
                    AxisValueLabel(anchor: value.index == profile.xTicks.count - 1 ? .topTrailing
                                   : (value.index == 0 ? .topLeading : .top)) {
                        if value.index < profile.xTicks.count {
                            tickLabel(profile.xTicks[value.index], showUnit: value.index == profile.xTicks.count - 1)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yTickValues) { value in
                    AxisGridLine().foregroundStyle(Color.RP.border)
                    AxisValueLabel {
                        if let tick = profile.yTicks.first(where: { $0.value == value.as(Double.self) }) {
                            tickLabel(tick, showUnit: tick == profile.yTicks.last)
                        }
                    }
                }
            }
            .frame(height: chartHeight)
            .accessibilityIdentifier("elevationChart")
        }
        .padding(RPSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpCard()
    }

    /// At accessibility sizes only the lowest and highest y labels, so they never overlap.
    private var yTickValues: [Double] {
        let all = profile.yTicks.map(\.value)
        return typeSize.isAccessibilitySize ? [all.first, all.last].compactMap { $0 } : all
    }

    private func number(_ v: Double) -> String {
        v.formatted(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(.current))
    }

    private var distanceSymbol: String { profile.distanceUnit == .mile ? UnitLength.miles.symbol : UnitLength.kilometers.symbol }
    private var altitudeSymbol: String { profile.altitudeUnit == .foot ? UnitLength.feet.symbol : UnitLength.meters.symbol }

    private func callout(distance: Double, altitude: Double) -> String {
        "\(number(distance)) \(distanceSymbol) · \(number(altitude)) \(altitudeSymbol)"
    }

    private var summitText: String {
        String(localized: "Highest point · \(number(profile.summit.altitude)) \(altitudeSymbol) · \(profile.distanceUnit == .mile ? "mile" : "km") \(number(profile.summit.distance))")
    }

    private var fill: LinearGradient {
        let top = RPTheme.draw(for: colorScheme).elevationFillOpacity
        return LinearGradient(colors: [Color.RP.route.opacity(top), Color.RP.route.opacity(0)],
                              startPoint: .top, endPoint: .bottom)
    }

    private func tickLabel(_ tick: ProfileTick, showUnit: Bool) -> some View {
        Text(Self.tickText(tick, showUnit: showUnit))
            .font(RPType.axis)
            .foregroundStyle(Color.RP.textSecondary)
    }

    /// "8k", "200", and on the last tick of an axis "8k ft" or "200 mi".
    static func tickText(_ tick: ProfileTick, showUnit: Bool, locale: Locale = .current) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(locale)
        let number = tick.isThousands ? (tick.value / 1000).formatted(style) + "k" : tick.value.formatted(style)
        guard showUnit else { return number }
        let symbol: String = switch tick.unit {
        case .mile: UnitLength.miles.symbol
        case .kilometer: UnitLength.kilometers.symbol
        case .foot: UnitLength.feet.symbol
        case .meter: UnitLength.meters.symbol
        }
        return "\(number) \(symbol)"
    }
}
