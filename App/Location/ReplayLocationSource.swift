#if DEBUG
import Foundation
import RoadPrintCore

/// Debug-only: replays a bundled GPX quickly, keeping the original timestamps.
final class ReplayLocationSource: LocationSource, @unchecked Sendable {
    private let route: [TrackPoint]
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init?(routeName: String) {
        guard let url = Bundle.main.url(forResource: routeName, withExtension: "gpx"),
              let data = try? Data(contentsOf: url),
              let points = try? GPXReader.parse(data), !points.isEmpty
        else { return nil }
        route = points
    }

    func points() -> AsyncStream<TrackPoint> {
        let route = route
        let (stream, continuation) = AsyncStream<TrackPoint>.makeStream()
        let task = Task {
            var index = 0
            while index < route.count && !Task.isCancelled {
                for point in route[index..<min(index + 50, route.count)] { continuation.yield(point) }
                index += 50
                try? await Task.sleep(for: .milliseconds(100))
            }
            continuation.finish()
        }
        lock.lock()
        self.task = task
        lock.unlock()
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func stop() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
#endif
