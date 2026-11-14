import SwiftUI
import UIKit
import RoadPrintCore

/// Where the number sits on a sign, worked out from `RoadSignSpec` as Design/road-signs/README.md
/// describes ("Drawing the number"). All lengths are in viewBox units.
struct RoadSignLayout: Equatable {
    let templateName: String
    let template: RoadSignSpec.Template
    let text: String
    /// The number's font size after shrinking to fit the text box.
    let fontSize: CGFloat
    let baseline: CGFloat
    let centerX: CGFloat

    static func == (a: RoadSignLayout, b: RoadSignLayout) -> Bool {
        a.templateName == b.templateName && a.text == b.text && a.fontSize == b.fontSize
            && a.baseline == b.baseline && a.centerX == b.centerX
    }

    /// The sign for `road`, drawn `height` points tall. Nil only if the generic sign is missing.
    @MainActor
    static func make(network: RoadNetwork, ref: String, height: CGFloat) -> RoadSignLayout? {
        let name = templateName(network: network, ref: ref, height: height)
        if let fitted = fit(name, ref: ref) { return fitted }
        // Too long even at the smallest size: the generic plate, at its smallest if need be.
        return fit("generic", ref: ref, force: true)
    }

    /// Step 1 of the README: the template for this network, ref and size.
    static func templateName(network: RoadNetwork, ref: String, height: CGFloat) -> String {
        guard let spec = RoadSignSpec.networks[network] else { return "generic" }
        let text = ref.uppercased()
        guard matches(text, spec.accept) else { return "generic" }
        let rule = spec.variants.first { matches(text, $0.match) }?.rule ?? spec.rule
        let wide = rule.wide != nil && rule.wideAbove.map { text.count > $0 } == true
        let small = rule.smallBelow.map { height < CGFloat($0) } == true
        switch (wide, small) {
        case (true, true): return rule.wideSmall ?? rule.wide ?? rule.template
        case (true, false): return rule.wide ?? rule.template
        case (false, true): return rule.small ?? rule.template
        case (false, false): return rule.template
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Steps 2 to 4: the size and place of the number.
    @MainActor
    private static func fit(_ name: String, ref: String, force: Bool = false) -> RoadSignLayout? {
        guard let template = RoadSignSpec.templates[name] else { return nil }
        let text = template.uppercase ? ref.uppercased() : ref
        let width = textWidth(text, size: template.fontSize)
            + template.tracking * CGFloat(max(text.count - 1, 0))
        var scale = width > template.textBox.width ? template.textBox.width / width : 1
        if scale < template.minScale {
            guard force else { return nil }
            scale = template.minScale
        }
        let box = template.textBox
        let baseline = scale >= 1 ? template.baseline
            : box.minY + (box.height + RoadSignSpec.capHeight * template.fontSize * scale) / 2
        return RoadSignLayout(templateName: name, template: template, text: text,
                              fontSize: template.fontSize * scale, baseline: baseline, centerX: box.midX)
    }

    @MainActor
    private static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        guard let font = UIFont(name: RPFont.number, size: size) else { return 0 }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// A road sign with its number: the US Interstate shield for I-80, the green E-road plate for
/// E85 (Design/road-signs). It keeps its real colours in both themes.
struct RoadSign: View {
    let road: MainRoad
    /// Shown height in points.
    let height: CGFloat
    /// The height the sign really ends up at on a screen or in an exported picture, for picking
    /// the plain small templates under 40 pt. A share card is laid out small and exported at 3×.
    var detailHeight: CGFloat?

    var body: some View {
        if let layout = RoadSignLayout.make(network: road.network, ref: road.ref, height: detailHeight ?? height) {
            let scale = height / RoadSignSpec.viewBoxHeight
            ZStack(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
                Image(layout.template.asset)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.template.width * scale, height: height)
                    .alignmentGuide(.firstTextBaseline) { _ in layout.baseline * scale }
                    .alignmentGuide(HorizontalAlignment.center) { _ in layout.centerX * scale }
                Text(verbatim: layout.text)
                    .font(.custom(RPFont.number, fixedSize: layout.fontSize * scale))
                    .tracking(layout.template.tracking * scale)
                    .foregroundStyle(layout.template.textColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: layout.template.width * scale, height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: ShareCardText.roadName(road)))
            .accessibilityIdentifier("roadSign")
        }
    }

    /// Width for `height`, so a row can make room before drawing.
    @MainActor
    static func width(_ road: MainRoad, height: CGFloat, detailHeight: CGFloat? = nil) -> CGFloat {
        guard let layout = RoadSignLayout.make(network: road.network, ref: road.ref, height: detailHeight ?? height) else { return 0 }
        return layout.template.width * height / RoadSignSpec.viewBoxHeight
    }
}

#if DEBUG
/// DEBUG-only: every template with its sample refs at 32, 48 and 96 pt on the app's dark ground and
/// on Road Atlas paper, to check the signs against Design/road-signs/contact-sheet.png.
/// Launch with `-RPSignGallery YES`.
struct RoadSignGalleryView: View {
    private static let samples: [MainRoad] = [
        MainRoad(network: .usInterstate, ref: "80"), MainRoad(network: .usInterstate, ref: "405"),
        MainRoad(network: .usHighway, ref: "50"), MainRoad(network: .usHighway, ref: "101"),
        MainRoad(network: .canadaHighway, ref: "1"), MainRoad(network: .canadaHighway, ref: "401"),
        MainRoad(network: .eRoad, ref: "E85"), MainRoad(network: .eRoad, ref: "E105"),
        MainRoad(network: .ukMotorway, ref: "M25"), MainRoad(network: .ukMotorway, ref: "A1(M)"),
        MainRoad(network: .ukARoad, ref: "A303"), MainRoad(network: .australia, ref: "M31"),
        MainRoad(network: .australia, ref: "95"), MainRoad(network: .generic, ref: "N7"),
        MainRoad(network: .generic, ref: "A380"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.l) {
                ForEach([CGFloat(32), 48], id: \.self) { height in
                    row(height: height, ground: Color.RP.Night.background)
                    row(height: height, ground: Color.RP.Day.background)
                }
                HStack(spacing: RPSpace.m) {
                    ForEach(Array(Self.samples.prefix(3).enumerated()), id: \.offset) { item in
                        RoadSign(road: item.element, height: 96)
                    }
                }
                .padding(RPSpace.m)
            }
            .padding(.vertical, RPSpace.l)
        }
        .background(Color.RP.Night.background.ignoresSafeArea())
        .accessibilityIdentifier("roadSignGallery")
    }

    private func row(height: CGFloat, ground: Color) -> some View {
        // Wraps by hand: a few signs per line.
        let perLine = height < 40 ? 6 : 4
        let lines = stride(from: 0, to: Self.samples.count, by: perLine).map {
            Array(Self.samples[$0..<min($0 + perLine, Self.samples.count)])
        }
        return VStack(alignment: .leading, spacing: RPSpace.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { line in
                HStack(spacing: RPSpace.s) {
                    ForEach(Array(line.element.enumerated()), id: \.offset) { item in
                        RoadSign(road: item.element, height: height)
                    }
                }
            }
        }
        .padding(RPSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ground)
    }
}
#endif
