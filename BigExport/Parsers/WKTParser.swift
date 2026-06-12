import Foundation

// WKT: one POINT per line, optionally with a leading name column.
//   POINT (4.8896 52.3740)
//   "Café de Klos",POINT(4.8896 52.3740)
// WKT order is lon lat (x y).
enum WKTParser {
    static func parse(_ data: Data) throws -> [Place] {
        guard let text = String(data: data, encoding: .utf8) else { throw ParseError.invalidFormat }
        var places: [Place] = []
        var index = 0
        for line in text.components(separatedBy: .newlines) {
            guard let r = line.range(of: #"POINT\s*\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)"#,
                                     options: [.regularExpression, .caseInsensitive]) else { continue }
            let inner = String(line[r]).drop(while: { $0 != "(" }).dropFirst().dropLast()
            let parts = inner.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let lon = Double(parts[0]), let lat = Double(parts[1]),
                  (-90...90).contains(lat), (-180...180).contains(lon) else { continue }
            index += 1
            // anything before POINT (minus quotes/delimiters) is the name
            let prefix = String(line[line.startIndex..<r.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t,;\""))
            places.append(Place(
                name: prefix.isEmpty ? "Place \(index)" : prefix,
                latitude: lat, longitude: lon, address: "", countryCode: "US"
            ))
        }
        guard !places.isEmpty else { throw ParseError.noPlacesFound }
        return places
    }
}
