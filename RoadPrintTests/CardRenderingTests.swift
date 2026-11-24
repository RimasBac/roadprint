import XCTest
import ImageIO
import UniformTypeIdentifiers
import RoadPrintCore
@testable import RoadPrint

/// The app side of the Print and Terrain cards: text measuring with the bundled fonts, the card
/// content from a share summary, and raw PNG decoding for elevation tiles (ADR 0006).
@MainActor
final class CardRenderingTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    func testCoreTextMeasurerUsesTheBundledFonts() {
        let title = CardTextStyle(CardTokens.Print.Typography.title)
        let box = CoreTextMeasurer.shared.ink("UTAH", style: title)
        XCTAssertGreaterThan(box.width, 100, "Barlow Condensed 96 px: about 150 px wide")
        XCTAssertLessThan(box.top, -50, "cap height above the baseline")
        // Tracking widens the run; a "1" starts further right in its advance than a "6".
        var tracked = title
        tracked.tracking += 10
        XCTAssertGreaterThan(CoreTextMeasurer.shared.ink("UTAH", style: tracked).width, box.width + 25)
        let number = CardTextStyle(CardTokens.Print.Typography.number)
        XCTAssertGreaterThan(CoreTextMeasurer.shared.ink("1", style: number).x, CoreTextMeasurer.shared.ink("6", style: number).x)
        XCTAssertEqual(CoreTextMeasurer.postScriptName(family: "Barlow Condensed", weight: 700), "BarlowCondensed-Bold")
        XCTAssertEqual(CoreTextMeasurer.postScriptName(family: "Inter", weight: 600), "Inter-SemiBold")
    }

    func testPrintTitleUsesRegionsOrTheTwoAreas() {
        let utah = PlaceRef(code: "US-UT", name: "Utah"), california = PlaceRef(code: "US-CA", name: "California")
        let usa = PlaceRef(code: "US", name: "United States of America")
        XCTAssertTrue(PrintCardContent.title(places: TripPlaces(countries: [usa], regions: [utah, california]),
                                             startLabel: "A area", endLabel: "B area") == ("Utah", "California"))
        XCTAssertTrue(PrintCardContent.title(places: TripPlaces(countries: [usa], regions: [utah]),
                                             startLabel: "Salt Lake City area", endLabel: "Provo area") == ("Salt Lake City area", "Provo area"))
        XCTAssertEqual(PrintCardContent.date(ShareDay(year: 2026, month: 11, day: 4), locale: en), "Wednesday, November 4")
    }

    func testPrintStatsShowCareerOrTheHighestPoint() throws {
        let summary = try XCTUnwrap(CardDebugView.fixtureSummary)
        let career = PrintCardContent.input(summary: summary, unit: .miles, startLabel: nil, endLabel: nil,
                                            careerMeters: 1_000 * DistanceUnit.metersPerMile, locale: en)
        XCTAssertEqual(career.stats.map(\.label), ["Moving time", "states", "Career miles"])
        XCTAssertEqual(career.stats.last?.value, "1,000")
        let highest = PrintCardContent.input(summary: summary, unit: .miles, startLabel: nil, endLabel: nil, careerMeters: nil, locale: en)
        XCTAssertEqual(highest.stats.last?.label, "Highest point")
        XCTAssertEqual(highest.distanceUnit, "MILES")
        XCTAssertFalse(highest.hideRoute)
        XCTAssertNotNil(highest.signAspect, "I-80 has a sign")
    }

    func testTerrariumPNGBytesReachTheCoreUnchanged() throws {
        // A 2 × 1 RGB PNG with two exact Terrarium heights: 0 m (128, 0, 0) and 2,206.5 m (136, 158, 128).
        let pixels: [UInt8] = [128, 0, 0, 136, 158, 128]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 6,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let tile = try XCTUnwrap(TerrainPNG.tile(data as Data))
        XCTAssertEqual(tile.bytesPerPixel, 3)
        XCTAssertEqual(tile.pixels, pixels)
    }

    func testBundledLandCoverLoads() throws {
        let land = try XCTUnwrap(TerrainPNG.landCover())
        XCTAssertEqual(land.width, 5400)
        XCTAssertEqual(land.height, 2700)
        XCTAssertEqual(land.rgb.count, 5400 * 2700 * 3)
    }

    func testTerrainRibbonRunsSplitAtHiddenPartsAndGaps() {
        func p(_ x: Double, hidden: Bool = false, gap: Bool = false) -> TerrainRibbonPoint {
            TerrainRibbonPoint(position: CardPoint(x: x, y: 0), gap: gap, hidden: hidden, elevation: gap ? nil : 100)
        }
        let runs = TerrainCardArt.runs([p(0), p(1), p(2, hidden: true), p(3, hidden: true), p(4), p(5, gap: true), p(6), p(7)])
        XCTAssertEqual(runs.visible.map { $0.map(\.x) }, [[0, 1, 2], [3, 4], [6, 7]])
        XCTAssertEqual(runs.hidden.map { $0.map(\.x) }, [[1, 2, 3, 4]])
        XCTAssertEqual(runs.gaps.map { $0.map(\.x) }, [[4, 6]])
    }
}
