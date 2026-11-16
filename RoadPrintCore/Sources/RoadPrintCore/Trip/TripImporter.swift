import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Why a file can't be imported. `message` is the plain wording for alert A10.
public enum ImportError: Error, Equatable {
    /// Made by a newer RoadPrint. Carries the version found.
    case newerVersion(Int)
    case notARoadPrintFile
    case corrupt
    /// Nothing in the file to import.
    case empty

    public var message: String {
        switch self {
        case .newerVersion: "This file was made by a newer RoadPrint. Update the app to open it."
        case .notARoadPrintFile: "This isn't a RoadPrint or GPX file."
        case .corrupt: "This file is damaged and can't be read."
        case .empty: "There are no trips in this file."
        }
    }
}

/// Why one trip in the file isn't imported.
public enum ImportSkipReason: String, Sendable, Equatable {
    /// An in-progress trip is never imported.
    case recording
    /// A GPX track with fewer than 2 timestamped points (RoadPrint's own GPX has none: use the `.json`).
    case noTimes
    /// A GPX track shorter than `TripImporter.minimumGPXDistanceMeters`.
    case tooShort
}

public struct ImportSkip: Sendable, Equatable {
    public var name: String
    public var reason: ImportSkipReason
    public init(name: String, reason: ImportSkipReason) {
        self.name = name
        self.reason = reason
    }
}

/// What importing a file would do. The app shows the counts, then writes `toInsert` and `toReplace`.
public struct ImportPlan: Sendable, Equatable {
    /// Trips or tracks in the file, skipped ones included.
    public var found: Int
    /// Already stored, and the stored copy is as new or newer.
    public var alreadyHere: Int
    public var toInsert: [Trip]
    /// Same `id` as a stored trip, but the file's copy is newer.
    public var toReplace: [Trip]
    public var skipped: [ImportSkip]
    /// The profile to adopt: only when the file has one and the local profile is still the default.
    public var profile: UserProfile?
    /// True when the file was GPX: run `TripProcessor` on `toInsert` before saving.
    public var needsProcessing: Bool

    /// The user picked a RoadPrint `.gpx` export: tell them to pick the `.json` instead.
    public var suggestsJSON: Bool { skipped.contains { $0.reason == .noTimes } && toInsert.isEmpty && toReplace.isEmpty }
}

public enum TripImporter {
    /// GPX tracks shorter than this (straight-line sum, metres) are skipped.
    public static let minimumGPXDistanceMeters = 100.0

    public static func plan(
        data: Data, fileName: String, existing: [Trip], localProfile: UserProfile,
        now: Date = Date(), makeID: () -> UUID = { UUID() }
    ) throws -> ImportPlan {
        let head = data.first(where: { ![0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF].contains($0) })
        guard let head else { throw ImportError.empty }
        let plan: ImportPlan
        switch head {
        case UInt8(ascii: "<"): plan = try planGPX(data, fileName: fileName, existing: existing, now: now, makeID: makeID)
        case UInt8(ascii: "{"): plan = try planJSON(data, existing: existing, localProfile: localProfile)
        default: throw ImportError.notARoadPrintFile
        }
        guard plan.found > 0 else { throw ImportError.empty }
        return plan
    }

    // MARK: JSON

    private static func planJSON(_ data: Data, existing: [Trip], localProfile: UserProfile) throws -> ImportPlan {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.corrupt
        }
        var trips: [Trip]
        var profile: UserProfile?
        if object["format"] != nil {
            do {
                let archive = try TripArchive.decode(data)
                trips = archive.trips
                profile = archive.profile
            } catch ArchiveError.newerVersion(let v) { throw ImportError.newerVersion(v)
            } catch ArchiveError.notARoadPrintFile { throw ImportError.notARoadPrintFile
            } catch { throw ImportError.corrupt }
        } else if object["id"] != nil, let version = object["schemaVersion"] as? Int {
            if version > Trip.maxSupportedSchemaVersion { throw ImportError.newerVersion(version) }
            guard let trip = try? ExportJSON.decoder().decode(Trip.self, from: data) else { throw ImportError.corrupt }
            trips = [trip]
        } else {
            throw ImportError.notARoadPrintFile
        }

        // Duplicate ids inside one file: the newest copy wins.
        var byID: [UUID: Trip] = [:]
        var order: [UUID] = []
        for trip in trips {
            if let old = byID[trip.id] {
                if trip.updatedAt > old.updatedAt { byID[trip.id] = trip }
            } else {
                byID[trip.id] = trip
                order.append(trip.id)
            }
        }
        trips = order.compactMap { byID[$0] }

        let local = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var plan = ImportPlan(found: trips.count, alreadyHere: 0, toInsert: [], toReplace: [], skipped: [],
                              profile: nil, needsProcessing: false)
        for trip in trips {
            if trip.status == .recording {
                plan.skipped.append(ImportSkip(name: nameFor(trip), reason: .recording))
            } else if let mine = local[trip.id] {
                // Never replace a trip that is being recorded here.
                if mine.status == .recording || mine.updatedAt >= trip.updatedAt {
                    plan.alreadyHere += 1
                } else {
                    plan.toReplace.append(trip)
                }
            } else {
                plan.toInsert.append(trip)
            }
        }
        if let profile, isDefault(localProfile) { plan.profile = profile }
        return plan
    }

    /// A profile nobody has filled in: no name and no starting distance.
    static func isDefault(_ p: UserProfile) -> Bool {
        p.displayName.trimmingCharacters(in: .whitespaces).isEmpty && p.startingCareerDistanceMeters == 0
    }

    private static func nameFor(_ trip: Trip) -> String {
        (trip.startedAt ?? trip.createdAt).formatted(.iso8601)
    }

    // MARK: GPX

    private static func planGPX(_ data: Data, fileName: String, existing: [Trip], now: Date,
                                makeID: () -> UUID) throws -> ImportPlan {
        let delegate = GPXTracks()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        guard delegate.sawGPX else { throw ImportError.notARoadPrintFile }
        if delegate.sawError || !ok { throw ImportError.corrupt }

        let starts = existing.compactMap(\.startedAt)
        var plan = ImportPlan(found: delegate.tracks.count, alreadyHere: 0, toInsert: [], toReplace: [],
                              skipped: [], profile: nil, needsProcessing: true)
        for (index, track) in delegate.tracks.enumerated() {
            let name = track.name.isEmpty ? "\(fileName) #\(index + 1)" : track.name
            let points = track.points.sorted { $0.timestamp < $1.timestamp }
            guard points.count >= 2 else {
                plan.skipped.append(ImportSkip(name: name, reason: .noTimes))
                continue
            }
            guard pathLength(points) >= minimumGPXDistanceMeters else {
                plan.skipped.append(ImportSkip(name: name, reason: .tooShort))
                continue
            }
            // The same file twice: a stored trip that starts at the same second is this track.
            let start = points[0].timestamp
            if starts.contains(where: { abs($0.timeIntervalSince(start)) < 2 }) {
                plan.alreadyHere += 1
                continue
            }
            plan.toInsert.append(Trip(
                id: makeID(), createdAt: now, updatedAt: now, schemaVersion: Trip.currentSchemaVersion,
                status: .completed, points: points, endedAt: points.last?.timestamp))
        }
        return plan
    }

    private static func pathLength(_ points: [TrackPoint]) -> Double {
        var total = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let dLat = (b.latitude - a.latitude) * .pi / 180
            let dLon = (b.longitude - a.longitude) * .pi / 180
            let h = pow(sin(dLat / 2), 2)
                + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * pow(sin(dLon / 2), 2)
            total += 2 * 6_371_000 * asin(min(1, sqrt(h)))
        }
        return total
    }

    /// Collects every `<trk>` with its timestamped points. Points without `<time>` are dropped.
    private final class GPXTracks: NSObject, XMLParserDelegate {
        struct Track { var name = ""; var points: [TrackPoint] = [] }
        var tracks: [Track] = []
        var sawGPX = false
        var sawError = false

        private var current: Track?
        private var inPoint = false
        private var lat: Double?, lon: Double?, ele: Double?, time: Date?
        private var text = ""
        private var depth: [String] = []
        private let fractional = ISO8601DateFormatter()
        private let plain = ISO8601DateFormatter()

        override init() {
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            plain.formatOptions = [.withInternetDateTime]
            super.init()
        }

        private func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes a: [String: String]) {
            let name = local(elementName)
            text = ""
            if depth.isEmpty { sawGPX = (name == "gpx") ; if !sawGPX { parser.abortParsing() } }
            depth.append(name)
            switch name {
            case "trk": current = Track()
            case "trkpt":
                inPoint = true; ele = nil; time = nil
                lat = a["lat"].flatMap(Double.init); lon = a["lon"].flatMap(Double.init)
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let name = local(elementName)
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { _ = depth.popLast() }
            switch name {
            case "ele" where inPoint: ele = Double(t)
            case "time" where inPoint: time = fractional.date(from: t) ?? plain.date(from: t)
            case "name" where !inPoint && depth.suffix(2).first == "trk": current?.name = t
            case "trkpt":
                inPoint = false
                if let lat, let lon, let time, (-90...90).contains(lat), (-180...180).contains(lon) {
                    current?.points.append(TrackPoint(
                        latitude: lat, longitude: lon, altitude: ele, timestamp: time,
                        horizontalAccuracy: GPXReader.defaultHorizontalAccuracy))
                }
            case "trk":
                if let c = current { tracks.append(c) }
                current = nil
            default: break
            }
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            if sawGPX { sawError = true }
        }
    }
}
