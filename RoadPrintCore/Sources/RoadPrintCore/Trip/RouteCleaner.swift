import Foundation

/// The cleaned trace: segments of raw points split at unfilled gaps.
public struct CleanedRoute: Sendable, Equatable {
    public var segments: [[TrackPoint]]
    /// Gaps joined by a straight line inside one segment (tunnels).
    public var filledGapCount: Int
    /// Gaps that split segments (including sustained relocations).
    public var unfilledGapCount: Int

    public var status: TripStatus { unfilledGapCount > 0 ? .partial : .completed }
    public var points: [TrackPoint] { segments.flatMap { $0 } }
}

/// Pure GPS cleaning. Speed is computed transiently here and never stored.
public struct RouteCleaner: Sendable {
    public var heuristics: ProcessingHeuristics

    public init(heuristics: ProcessingHeuristics = .default) {
        self.heuristics = heuristics
    }

    public func clean(_ raw: [TrackPoint]) -> CleanedRoute {
        let accurate = raw.filter {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= heuristics.maxHorizontalAccuracy
        }
        let (kept, relocations) = dropSpikes(accurate)
        return segment(kept, relocations: relocations)
    }

    private func speed(_ a: TrackPoint, _ b: TrackPoint) -> Double? {
        let dt = b.timestamp.timeIntervalSince(a.timestamp)
        guard dt > 0 else { return nil }
        return Geo.distance(from: a, to: b) / dt
    }

    /// Returns the kept points and the indices (into the kept list) that start
    /// after a sustained relocation.
    private func dropSpikes(_ points: [TrackPoint]) -> ([TrackPoint], Set<Int>) {
        var kept: [TrackPoint] = []
        var relocations = Set<Int>()
        kept.reserveCapacity(points.count)
        for i in points.indices {
            guard let last = kept.last else {
                kept.append(points[i])
                continue
            }
            // Out-of-order or duplicate timestamps can't be placed in time.
            guard let v = speed(last, points[i]) else { continue }
            if v <= heuristics.spikeSpeed {
                kept.append(points[i])
                continue
            }
            let need = heuristics.relocationConfirmCount
            let next = points[(i + 1)...].prefix(need)
            let confirmed = need > 0 && next.count == need
                && next.allSatisfy { (speed(points[i], $0) ?? .infinity) <= heuristics.spikeSpeed }
            if confirmed {
                relocations.insert(kept.count)
                kept.append(points[i])
            }
        }
        return (kept, relocations)
    }

    private func segment(_ points: [TrackPoint], relocations: Set<Int>) -> CleanedRoute {
        var segments: [[TrackPoint]] = []
        var current: [TrackPoint] = []
        var filled = 0
        var unfilled = 0
        for i in points.indices {
            if i > 0 {
                let d = Geo.distance(from: points[i - 1], to: points[i])
                let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
                if relocations.contains(i) {
                    unfilled += 1
                    segments.append(current)
                    current = []
                } else if d >= heuristics.recording.gapMinDisplacement {
                    if dt > 0, dt <= heuristics.filledGapMaxDuration,
                       d <= heuristics.filledGapMaxDisplacement,
                       d / dt <= heuristics.filledGapMaxSpeed {
                        filled += 1
                    } else {
                        unfilled += 1
                        segments.append(current)
                        current = []
                    }
                }
            }
            current.append(points[i])
        }
        if !current.isEmpty { segments.append(current) }
        return CleanedRoute(segments: segments, filledGapCount: filled, unfilledGapCount: unfilled)
    }
}
