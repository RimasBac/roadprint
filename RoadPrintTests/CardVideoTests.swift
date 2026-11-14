import XCTest
import AVFoundation
import SwiftUI
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class CardVideoTests: XCTestCase {
    func testTimingHoldsDrawsAndHolds() {
        let timing = CardVideo.Timing.standard
        XCTAssertEqual(timing.frameCount, 150)
        XCTAssertEqual(timing.progress(atFrame: 0), 0)
        XCTAssertEqual(timing.progress(atFrame: 15), 0, "the empty map first")
        XCTAssertEqual(timing.progress(atFrame: 149), 1, "the finished card last")
        let drawing = (0..<timing.frameCount).map(timing.progress(atFrame:))
        XCTAssertEqual(drawing, drawing.sorted(), "never goes back")
        XCTAssertEqual(CardVideo.eased(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(CardVideo.eased(0.1), 0.1, "slow away from the start")
    }

    func testRouteCutsAtTheProgress() {
        let route = MapScene.Route(kind: .recorded, points: [PlanePoint(x: 0, y: 0), PlanePoint(x: 100, y: 0),
                                                             PlanePoint(x: 100, y: 100)])
        let half = ShareCardArt.trimmed([route], progress: 0.5)
        XCTAssertEqual(half.tip?.x ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(half.tip?.y ?? 1, 0, accuracy: 1e-9)
        XCTAssertNil(ShareCardArt.trimmed([route], progress: 1).tip)
        XCTAssertEqual(ShareCardArt.fraction(of: PlanePoint(x: 99, y: 98), along: [route]), 1, accuracy: 1e-9)
        XCTAssertEqual(ShareCardArt.fraction(of: PlanePoint(x: 1, y: 1), along: [route]), 0, accuracy: 1e-9)
        let content = CardDebugView.fixtureContent
        XCTAssertEqual(content.distanceText(progress: 1), content.distanceValue)
        XCTAssertEqual(content.distanceText(progress: 0), "0")
        XCTAssertEqual(content.distanceText(progress: 0.5), (content.distanceAmount / 2).formatted(.number.precision(.fractionLength(0))))
    }

    /// The real Night Highway card on the I-80 fixture, as the video a driver shares. Kept as an
    /// attachment so the board can watch it, and timed: this is how long the driver waits.
    func testNightHighwayVideoIsWritten() async throws {
        let input = try XCTUnwrap(MapDebugView.input(fixture: "i80"))
        let places = try PlaceIndex.bundled()
        let spec = ShareCardMetrics.map(.nightHighway, hasElevation: true)
        // The Night Highway card places its own small capitals, not the builder's labels.
        var cardInput = input
        cardInput.startLabel = nil
        cardInput.endLabel = nil
        let scene = try MapSceneBuilder.build(input: cardInput, places: places,
                                              size: (Double(ShareCardMetrics.size.width), Double(spec.height)),
                                              insets: spec.insets, labels: spec.labels)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("card-night-highway-i80.mp4")
        let started = Date()
        try await CardVideo.write(to: url, size: ShareCardMetrics.size, scale: ShareCardMetrics.exportScale) { progress in
            ShareCard(style: .nightHighway, content: CardDebugView.fixtureContent, scene: scene,
                      elevation: CardDebugView.fixtureElevation, progress: progress)
        }
        let seconds = Date().timeIntervalSince(started)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, CardVideo.Timing.standard.duration, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)

        let video = XCTAttachment(contentsOfFile: url)
        video.name = "video-night-highway-i80"
        video.lifetime = .keepAlways
        add(video)
        let note = XCTAttachment(string: "Rendered \(CardVideo.Timing.standard.frameCount) frames in \(String(format: "%.1f", seconds)) s on the CI simulator.")
        note.name = "video-night-highway-i80-timing"
        note.lifetime = .keepAlways
        add(note)
    }
}
