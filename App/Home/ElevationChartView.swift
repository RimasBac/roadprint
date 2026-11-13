import SwiftUI
import Charts
import RoadPrintCore

/// The elevation profile of a trip (plan §4.3, mockup 1; ROA-55, first version): an amber line over a
/// soft fill, faint horizontal grid lines only, and a dot at the highest point. All numbers come
/// from the core's `ElevationProfile`; this view only draws them.
struct ElevationChartView: View {
    let profile: ElevationProfile

    @Environment(\.colorScheme) private var colorScheme

    /// Mockup 1 draws the chart about 120 pt tall.
    private static let chartHeight: CGFloat = 120
    private static let summitDotArea: CGFloat = 36

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
                PointMark(x: .value("Distance", profile.summit.distance),
                          y: .value("Altitude", profile.summit.altitude))
                    .symbolSize(Self.summitDotArea)
                    .foregroundStyle(Color.RP.text)
            }
            .chartXScale(domain: 0...max(profile.totalDistance, 0.001))
            .chartYScale(domain: profile.yMin...max(profile.yMax, profile.yMin + 1))
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: profile.xTicks.map(\.value)) { value in
                    AxisValueLabel {
                        if value.index < profile.xTicks.count {
                            tickLabel(profile.xTicks[value.index], showUnit: value.index == profile.xTicks.count - 1)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: profile.yTicks.map(\.value)) { value in
                    AxisGridLine().foregroundStyle(Color.RP.border)
                    AxisValueLabel {
                        if value.index < profile.yTicks.count {
                            tickLabel(profile.yTicks[value.index], showUnit: value.index == profile.yTicks.count - 1)
                        }
                    }
                }
            }
            .frame(height: Self.chartHeight)
            .accessibilityIdentifier("elevationChart")
        }
        .padding(RPSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpCard()
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
