import Foundation

/// Where points come from. The app provides CoreLocation and replay versions.
public protocol LocationSource: Sendable {
    func points() -> AsyncStream<TrackPoint>
    func stop()
}
