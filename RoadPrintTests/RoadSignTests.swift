import XCTest
import UIKit
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class RoadSignTests: XCTestCase {
    /// Step 1 of Design/road-signs/README.md, with its own examples.
    func testTemplateFollowsTheReadme() {
        XCTAssertEqual(RoadSignLayout.templateName(network: .usInterstate, ref: "80", height: 48), "usInterstate")
        XCTAssertEqual(RoadSignLayout.templateName(network: .usInterstate, ref: "80", height: 32), "usInterstate-small")
        XCTAssertEqual(RoadSignLayout.templateName(network: .usInterstate, ref: "405", height: 48), "usInterstate-wide")
        XCTAssertEqual(RoadSignLayout.templateName(network: .usInterstate, ref: "405", height: 32), "usInterstate-wide-small")
        XCTAssertEqual(RoadSignLayout.templateName(network: .usHighway, ref: "101", height: 32), "usHighway-wide")
        XCTAssertEqual(RoadSignLayout.templateName(network: .australia, ref: "95", height: 32), "australia-shield-small")
        XCTAssertEqual(RoadSignLayout.templateName(network: .australia, ref: "95", height: 48), "australia-shield")
        XCTAssertEqual(RoadSignLayout.templateName(network: .australia, ref: "A1", height: 32), "australia")
        XCTAssertEqual(RoadSignLayout.templateName(network: .eRoad, ref: "E85", height: 32), "eRoad")
        XCTAssertEqual(RoadSignLayout.templateName(network: .ukMotorway, ref: "A1(M)", height: 48), "ukMotorway")
        // A ref the network doesn't accept gets the plain plate.
        XCTAssertEqual(RoadSignLayout.templateName(network: .eRoad, ref: "85", height: 48), "generic")
        XCTAssertEqual(RoadSignLayout.templateName(network: .usInterstate, ref: "I80", height: 48), "generic")
    }

    func testNumberFitsItsBox() throws {
        for (network, ref) in [(RoadNetwork.usInterstate, "5"), (.usInterstate, "80"), (.usInterstate, "405"),
                               (.eRoad, "E105"), (.ukMotorway, "A1(M)"), (.generic, "A380")] {
            let layout = try XCTUnwrap(RoadSignLayout.make(network: network, ref: ref, height: 48), "\(network) \(ref)")
            XCTAssertLessThanOrEqual(layout.fontSize, layout.template.fontSize, ref)
            XCTAssertGreaterThanOrEqual(layout.fontSize, layout.template.fontSize * layout.template.minScale - 0.001, ref)
            XCTAssertEqual(layout.centerX, layout.template.textBox.midX, ref)
            XCTAssertGreaterThan(layout.baseline, layout.template.textBox.minY, ref)
            XCTAssertLessThanOrEqual(layout.baseline, layout.template.textBox.maxY + 0.001, ref)
        }
        XCTAssertEqual(RoadSignLayout.make(network: .ukARoad, ref: "a303", height: 48)?.text, "A303")
        // Far too long for any plate: still drawn, on the generic one at its smallest.
        let long = try XCTUnwrap(RoadSignLayout.make(network: .generic, ref: "WWWWW", height: 48))
        XCTAssertEqual(long.templateName, "generic")
    }

    /// Every template's SVG made it into the asset catalog as an image.
    func testEveryTemplateHasItsImage() {
        for (name, template) in RoadSignSpec.templates {
            XCTAssertNotNil(UIImage(named: template.asset), name)
        }
        XCTAssertEqual(Set(RoadSignSpec.networks.keys), Set(RoadNetwork.allCases))
    }
}
