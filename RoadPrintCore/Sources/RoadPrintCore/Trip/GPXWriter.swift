import Foundation

/// Writes trips as one GPX 1.1 document: one `<trk>` per trip. Never speed or course.
/// Processed trips (schema 2) have no times, so their points carry none; raw trips keep `<time>`.
/// A trip with nothing to draw (short trip, no points) writes no `<trk>`.
public enum GPXWriter {
    public static func document(trips: [Trip]) -> Data {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="RoadPrint" xmlns="http://www.topografix.com/GPX/1/1">

        """
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nameFormatter = ISO8601DateFormatter()
        nameFormatter.formatOptions = [.withInternetDateTime]

        for trip in trips {
            var segments: [String] = []
            if let route = trip.route {
                for segment in route.segments where !segment.points.isEmpty {
                    var seg = "    <trkseg>\n"
                    for p in segment.points {
                        seg += point(p.latitude, p.longitude, p.altitude, time: nil)
                    }
                    segments.append(seg + "    </trkseg>\n")
                }
            } else if !trip.points.isEmpty {
                var seg = "    <trkseg>\n"
                for p in trip.points {
                    seg += point(p.latitude, p.longitude, p.altitude, time: formatter.string(from: p.timestamp))
                }
                segments.append(seg + "    </trkseg>\n")
            }
            guard !segments.isEmpty else { continue }
            let name = nameFormatter.string(from: trip.startedAt ?? trip.createdAt)
            out += "  <trk>\n    <name>\(escape(name))</name>\n" + segments.joined() + "  </trk>\n"
        }
        out += "</gpx>\n"
        return Data(out.utf8)
    }

    private static func point(_ lat: Double, _ lon: Double, _ ele: Double?, time: String?) -> String {
        var s = String(format: "      <trkpt lat=\"%.7f\" lon=\"%.7f\">", lat, lon)
        if let ele { s += String(format: "<ele>%.1f</ele>", ele) }
        if let time { s += "<time>\(time)</time>" }
        return s + "</trkpt>\n"
    }

    static func escape(_ text: String) -> String {
        var r = ""
        for ch in text {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "'": r += "&apos;"
            default: r.append(ch)
            }
        }
        return r
    }
}
