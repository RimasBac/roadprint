import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads `trkpt` elements (lat/lon attributes, `ele`, `time`) from GPX 1.0/1.1.
public enum GPXReader {
    public enum ParseError: Error, Equatable {
        case malformedXML(String)
        case invalidCoordinate
        case missingOrInvalidTime
    }

    /// GPX carries no accuracy, so imported points get this value (metres).
    public static let defaultHorizontalAccuracy = 5.0

    public static func parse(_ data: Data) throws -> [TrackPoint] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        if let failure = delegate.failure { throw failure }
        guard ok else {
            throw ParseError.malformedXML(parser.parserError?.localizedDescription ?? "unknown")
        }
        return delegate.points
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var points: [TrackPoint] = []
        var failure: ParseError?

        private var lat: Double?
        private var lon: Double?
        private var ele: Double?
        private var time: Date?
        private var inPoint = false
        private var text = ""
        private let fractional: ISO8601DateFormatter
        private let plain: ISO8601DateFormatter

        override init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            super.init()
        }

        private func local(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            text = ""
            if local(elementName) == "trkpt" {
                inPoint = true
                ele = nil
                time = nil
                lat = attributeDict["lat"].flatMap { Double($0) }
                lon = attributeDict["lon"].flatMap { Double($0) }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            guard inPoint else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local(elementName) {
            case "ele":
                ele = Double(trimmed)
            case "time":
                time = fractional.date(from: trimmed) ?? plain.date(from: trimmed)
            case "trkpt":
                inPoint = false
                guard let lat, let lon, (-90...90).contains(lat), (-180...180).contains(lon) else {
                    fail(.invalidCoordinate, parser)
                    return
                }
                guard let time else {
                    fail(.missingOrInvalidTime, parser)
                    return
                }
                points.append(TrackPoint(
                    latitude: lat, longitude: lon, altitude: ele, timestamp: time,
                    horizontalAccuracy: GPXReader.defaultHorizontalAccuracy
                ))
            default:
                break
            }
        }

        private func fail(_ error: ParseError, _ parser: XMLParser) {
            failure = error
            parser.abortParsing()
        }
    }
}
