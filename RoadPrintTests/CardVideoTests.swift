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
        XCTAssertEqual(timing.progress(atFrame: 5), 0, "a short empty map first")
        XCTAssertGreaterThan(timing.progress(atFrame: 9), 0.05, "moving within the first third of a second")
        XCTAssertEqual(timing.progress(atFrame: 149), 1, "the finished card last")
        XCTAssertEqual(timing.progress(at: 3.0), 1, "two seconds of the finished card")
        let drawing = (0..<timing.frameCount).map(timing.progress(atFrame:))
        XCTAssertEqual(drawing, drawing.sorted(), "never goes back")
        XCTAssertEqual(CardVideo.eased(0.5), 0.875, accuracy: 1e-9)
        XCTAssertGreaterThan(CardVideo.eased(0.1), 0.25, "sets off at once")
        for p in [0.1, 0.5, 0.9] {
            XCTAssertEqual(timing.progress(at: timing.time(atProgress: p)), p, accuracy: 1e-9)
        }
        XCTAssertEqual(timing.stillKey(at: 0.1), -1)
        XCTAssertNil(timing.stillKey(at: 1.5))
        XCTAssertEqual(timing.stillKey(at: 4.0), -2)
        // Things fade in over a quarter of a second after the tip reaches them.
        XCTAssertEqual(CardMotion.still.appear(at: 0.5), 1)
        XCTAssertEqual(CardMotion(time: 0).appear(at: 0.5), 0)
        XCTAssertEqual(CardMotion(time: timing.time(atProgress: 0.5) + 0.125).appear(at: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(CardMotion(time: 5).appear(at: 1), 1)
    }

    func testRouteCutsAtTheProgress() throws {
        // MapScene.Route has no public initializer; it is Codable.
        let route = try JSONDecoder().decode(MapScene.Route.self, from: Data(
            #"{"kind":"recorded","points":[{"x":0,"y":0},{"x":100,"y":0},{"x":100,"y":100}]}"#.utf8))
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
        try await CardVideo.write(to: url, size: ShareCardMetrics.size, scale: ShareCardMetrics.exportScale) { seconds in
            ShareCard(style: .nightHighway, content: CardDebugView.fixtureContent, scene: scene,
                      elevation: CardDebugView.fixtureElevation, motion: CardMotion(time: seconds))
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
