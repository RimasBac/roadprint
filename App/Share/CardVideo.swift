import AVFoundation
import CoreVideo
import SwiftUI

/// A share card as a short video for Stories and TikTok (9:16, 1080 × 1920): the map waits a
/// moment, the route draws itself while the distance counts up, then the finished card holds.
/// Everything is drawn on the phone; nothing is uploaded.
enum CardVideo {
    struct Timing: Equatable, Sendable {
        var fps = 30
        /// The empty map before the route starts: short, so the first second already moves.
        var hold = 0.2
        var draw = 2.8
        /// The finished card at the end, long enough to read the number.
        var end = 2.0

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

        /// When the route's tip reaches `progress` (the inverse of the ease-out).
        func time(atProgress progress: Double) -> Double {
            if progress <= 0 { return hold }
            if progress >= 1 { return hold + draw }
            return hold + draw * (1 - cbrt(1 - progress))
        }

        /// The same number for every frame that looks the same: the empty map at the start, and the
        /// finished card once the last fade is over. Nil while something moves.
        func stillKey(at seconds: Double) -> Double? {
            if seconds <= hold { return -1 }
            if seconds >= hold + draw + CardVideo.fadeSeconds { return -2 }
            return nil
        }
    }

    /// The highest point and the end fade in over this long once the route reaches them.
    static let fadeSeconds = 0.25

    enum Failure: Error {
        case cannotWrite
        case cannotDraw
    }

    /// Ease-out: the route sets off at once and settles into the end (Designer, ROA-60).
    static func eased(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// Writes `card(seconds)` for every frame of `timing` to an H.264 MP4 at `url`.
    /// Frames that look the same (the holds) are drawn once.
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

        var drawn: (key: Double, buffer: CVPixelBuffer)?
        let frames = timing.frameCount
        for frame in 0..<frames {
            try Task.checkCancellation()
            let seconds = Double(frame) / Double(timing.fps)
            let key = timing.stillKey(at: seconds) ?? seconds
            if drawn?.key != key {
                let renderer = ImageRenderer(content: card(seconds))
                renderer.scale = scale
                guard let image = renderer.cgImage else { throw Failure.cannotDraw }
                drawn = (key, try pixelBuffer(image, pool: adaptor.pixelBufferPool, width: width, height: height))
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
