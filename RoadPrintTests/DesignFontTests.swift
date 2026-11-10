import XCTest
import SwiftUI
import UIKit
import CoreText
@testable import RoadPrint

final class DesignFontTests: XCTestCase {
    @MainActor
    func testEveryTypeStyleLoadsItsBundledPostScriptFont() throws {
        let expected = ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
                        "BarlowCondensed-SemiBold", "BarlowCondensed-Bold"]
        for name in expected {
            let font = try XCTUnwrap(UIFont(name: name, size: 34), "Unregistered bundled font: \(name)")
            XCTAssertEqual(font.fontName, name, "System fallback for \(name)")
        }
        for sample in RPType.samples {
            let font = try XCTUnwrap(UIFont(name: sample.postScriptName, size: sample.size), sample.name)
            XCTAssertEqual(font.fontName, sample.postScriptName, sample.name)
            // Exercise the actual generated SwiftUI Font, including its Dynamic Type path.
            let renderer = ImageRenderer(content: Text("RoadPrint 0123456789").font(sample.font))
            XCTAssertNotNil(renderer.uiImage, sample.name)
        }
    }

    @MainActor
    func testNumberFontWithTabularFeatureHasEqualDigitAdvances() throws {
        let base = try XCTUnwrap(UIFont(name: RPFont.number, size: 34))
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        let font = UIFont(descriptor: descriptor, size: 34)
        XCTAssertEqual(font.fontName, RPFont.number)
        let widths = (0...9).map { digit in
            (String(digit) as NSString).size(withAttributes: [.font: font]).width
        }
        for width in widths { XCTAssertEqual(width, widths[0], accuracy: 0.01) }
    }

    @MainActor
    func testDynamicPaletteResolvesBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let dynamic = UIColor(Color.RP.background).resolvedColor(with: traits)
            let fixed = UIColor(style == .dark ? Color.RP.Night.background : Color.RP.Day.background)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
            XCTAssertTrue(dynamic.getRed(&r, green: &g, blue: &b, alpha: &a))
            XCTAssertTrue(fixed.getRed(&fr, green: &fg, blue: &fb, alpha: &fa))
            XCTAssertEqual(r, fr, accuracy: 0.001)
            XCTAssertEqual(g, fg, accuracy: 0.001)
            XCTAssertEqual(b, fb, accuracy: 0.001)
        }
        XCTAssertTrue(RPTheme.draw(for: .dark).routeGlow)
        XCTAssertFalse(RPTheme.draw(for: .light).routeGlow)
        XCTAssertTrue(RPTheme.draw(for: .light).cardBorder)
        XCTAssertEqual(RPSize.hairline(displayScale: 3), 1 / 3, accuracy: 0.0001)
    }
}
