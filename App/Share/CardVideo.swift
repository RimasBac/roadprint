import AVFoundation
import CoreVideo
import SwiftUI

/// A share card as a short video for Stories and TikTok (9:16, 1080 × 1920): the map waits a
/// moment, the route draws itself while the distance counts up, then the finished card holds.
/// Everything is drawn on the phone; nothing is uploaded.
enum CardVideo {
    struct Timing: Equatable, Sendable {
        var fps = 30
        /// The empty map before the route starts.
        var hold = 0.5
        var draw = 3.0
        /// The finished card at the end.
        var end = 1.5

        static let standard = Timing()

        var duration: Double { hold + draw + end }
        var frameCount: Int { Int((duration * Double(fps)).rounded()) }

        /// How much of the route frame `frame` shows: 0 while holding, eased while drawing, then 1.
        func progress(atFrame frame: Int) -> Double {
            progress(at: Double(frame) / Double(fps))
        }

        func progress(at seconds: Double) -> Double {
            if seconds <= hold { return 0 }
            if seconds >= hold + draw { return 1 }
            return CardVideo.eased((seconds - hold) / draw)
        }
    }

    enum Failure: Error {
        case cannotWrite
        case cannotDraw
    }

    /// Slow out of the start, slow into the end: the route accelerates away and settles.
    static func eased(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Writes `card(progress)` for every frame of `timing` to an H.264 MP4 at `url`.
    /// Frames that show the same progress (the holds) are drawn once.
    @MainActor
    static func write<Card: View>(to url: URL, size: CGSize, scale: CGFloat, timing: Timing = .standard,
                                  onProgress: (Double) -> Void = { _ in },
                                  card: (Double) -> Card) async throws {
        try? FileManager.default.removeItem(at: url)
        // H.264 wants even sizes.
        let width = Int((size.width * scale).rounded()) / 2 * 2
        let height = Int((size.height * scale).rounded()) / 2 * 2
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw Failure.cannotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        var drawn: (progress: Double, buffer: CVPixelBuffer)?
        let frames = timing.frameCount
        for frame in 0..<frames {
            try Task.checkCancellation()
            let progress = timing.progress(atFrame: frame)
            if drawn?.progress != progress {
                let renderer = ImageRenderer(content: card(progress))
                renderer.scale = scale
                guard let image = renderer.cgImage else { throw Failure.cannotDraw }
                drawn = (progress, try pixelBuffer(image, pool: adaptor.pixelBufferPool, width: width, height: height))
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            guard let buffer = drawn?.buffer,
                  adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(timing.fps)))
            else { throw writer.error ?? Failure.cannotWrite }
            onProgress(Double(frame + 1) / Double(frames))
            // Let the sheet redraw its progress bar between frames.
            await Task.yield()
        }
        input.markAsFinished()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? Failure.cannotWrite }
    }

    private static func pixelBuffer(_ image: CGImage, pool: CVPixelBufferPool?, width: Int, height: Int) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made)
        }
        guard let buffer = made else { throw Failure.cannotDraw }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw Failure.cannotDraw }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
