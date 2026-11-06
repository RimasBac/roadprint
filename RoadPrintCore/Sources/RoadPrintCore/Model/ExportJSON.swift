import Foundation

/// The JSON coding settings for the export format (docs/data-format.md).
/// Dates are ISO 8601 UTC with millisecond precision on write (sub-millisecond
/// parts are dropped); whole-second dates are also read.
public enum ExportJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(makeFormatter(fractional: true).string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = makeFormatter(fractional: true).date(from: string)
                ?? makeFormatter(fractional: false).date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return decoder
    }

    // Created per call: ISO8601DateFormatter is not Sendable.
    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
