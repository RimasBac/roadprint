import Foundation
import ImageIO
import CoreGraphics
import RoadPrintCore

/// Elevation tiles for the Terrain card (ADR 0006): public AWS Terrain Tiles (Terrarium PNG) for the
/// card's area only. Requests carry tile coordinates and nothing else: no cookies, no identifiers, never
/// the route. Tiles are cached in Caches (200 MB, oldest first out) and erased by Delete all data.
actor TerrainTileStore {
    static let shared = TerrainTileStore()

    /// One base URL (ADR 0006 point 1), so a RoadPrint proxy needs no other change.
    /// DEBUG builds can override it with `-RPTerrainTilesURL`.
    static var baseURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "RPTerrainTilesURL"), let url = URL(string: override) { return url }
        #endif
        return URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium")
            ?? URL(fileURLWithPath: "/")
    }
    static let cacheLimitBytes = 200 * 1024 * 1024
    static let concurrentRequests = 6

    enum Failure: Error {
        /// No connection, a timeout or a server error: the share sheet offers to try again.
        case offline
        case badTile(TerrainTileID)
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("TerrainTiles", isDirectory: true)
    }

    private func file(_ id: TerrainTileID) -> URL {
        Self.directory.appendingPathComponent("\(id.z)-\(id.x)-\(id.y).png")
    }

    /// Every tile in `ids`, decoded, fetching the ones not cached. `progress` runs 0 → 1.
    func tiles(_ ids: [TerrainTileID], progress: @Sendable @escaping (Double) -> Void = { _ in }) async throws -> [TerrainTileID: TerrainTile] {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        var out: [TerrainTileID: TerrainTile] = [:]
        var missing: [TerrainTileID] = []
        for id in ids {
            if let data = try? Data(contentsOf: file(id)), let tile = TerrainPNG.tile(data) {
                out[id] = tile
                // Touch it, so pruning keeps recently used tiles.
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file(id).path)
            } else {
                missing.append(id)
            }
        }
        let total = Double(max(ids.count, 1))
        var done = Double(out.count)
        progress(done / total)
        let base = Self.baseURL, session = self.session
        try await withThrowingTaskGroup(of: (TerrainTileID, Data).self) { group in
            var queue = missing[...]
            func next() {
                guard let id = queue.popFirst() else { return }
                group.addTask {
                    let url = base.appendingPathComponent("\(id.z)/\(id.x)/\(id.y).png")
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.offline }
                        return (id, data)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw Failure.offline
                    }
                }
            }
            for _ in 0..<Self.concurrentRequests { next() }
            while let result = try await group.next() {
                let (id, data) = result
                guard let tile = TerrainPNG.tile(data) else { throw Failure.badTile(id) }
                out[id] = tile
                try? data.write(to: file(id), options: .atomic)
                done += 1
                progress(done / total)
                next()
            }
        }
        prune()
        return out
    }

    /// Deletes every cached tile (Delete all data).
    func purge() {
        try? FileManager.default.removeItem(at: Self.directory)
    }

    /// Keeps the cache under `cacheLimitBytes`, removing the least recently used tiles first.
    private func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var size = entries.reduce(0) { $0 + $1.1 }
        guard size > Self.cacheLimitBytes else { return }
        entries.sort { $0.2 < $1.2 }
        for (url, bytes, _) in entries where size > Self.cacheLimitBytes {
            try? FileManager.default.removeItem(at: url)
            size -= bytes
        }
    }
}

/// PNG decoding for the terrain data, without colour management: a Terrarium pixel is a number, not
/// a colour, so its bytes must reach the core unchanged.
enum TerrainPNG {
    static func tile(_ data: Data) -> TerrainTile? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rgb = rawRGB(image) else { return nil }
        return TerrainTile(width: image.width, height: image.height, bytesPerPixel: 3, pixels: rgb)
    }

    /// The decoded samples as RGB, straight from the image's data provider (8-bit RGB or RGBA/ARGB).
    static func rawRGB(_ image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 8, let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data), image.colorSpace?.model == .rgb else { return nil }
        let bpp = image.bitsPerPixel / 8, row = image.bytesPerRow, w = image.width, h = image.height
        guard bpp == 3 || bpp == 4 else { return nil }
        let alphaFirst: Bool
        switch image.alphaInfo {
        case .first, .premultipliedFirst, .noneSkipFirst: alphaFirst = true
        default: alphaFirst = false
        }
        let offset = bpp == 4 && alphaFirst ? 1 : 0
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let s = y * row + x * bpp + offset, d = (y * w + x) * 3
                out[d] = bytes[s]; out[d + 1] = bytes[s + 1]; out[d + 2] = bytes[s + 2]
            }
        }
        return out
    }

    /// The bundled land-cover raster (App/Resources/Terrain/landcover-4min.png, 5400 × 2700, a palette
    /// PNG) as RGB. About 44 MB in memory: load it for a render and let it go after.
    static func landCover() -> TerrainLandCover? {
        guard let url = Bundle.main.url(forResource: "landcover-4min", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = rgba[i * 4]; rgb[i * 3 + 1] = rgba[i * 4 + 1]; rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return TerrainLandCover(width: w, height: h, rgb: rgb)
    }

    /// The core's RGBA relief as an image.
    static func image(_ render: TerrainRender) -> CGImage? {
        let data = Data(render.rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: render.width, height: render.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: render.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
