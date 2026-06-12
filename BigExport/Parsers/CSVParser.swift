import Foundation

enum CSVParser {
    // Supports: name, lat/latitude, lon/lng/longitude, address, country_code columns (any order)
    static func parse(_ data: Data) throws -> [Place] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.invalidFormat
        }
        // Strip UTF-8 BOM if present
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }
        var lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw ParseError.noPlacesFound }

        let header = parseRow(lines.removeFirst()).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let idx = ColumnIndex(header: header)
        guard idx.name >= 0, idx.lat >= 0, idx.lon >= 0 else {
            throw ParseError.missingColumns("Found: \(header.joined(separator: ", ")). Need columns for name, latitude, longitude.")
        }

        return lines.compactMap { line in
            let cols = parseRow(line)
            guard cols.count > max(idx.name, idx.lat, idx.lon) else { return nil }
            let name = cols[idx.name].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let lat = Double(cols[idx.lat]), let lon = Double(cols[idx.lon]) else { return nil }
            let addr = idx.address >= 0 && idx.address < cols.count ? cols[idx.address] : ""
            let cc   = idx.country >= 0 && idx.country < cols.count ? cols[idx.country] : "US"
            return Place(name: name, latitude: lat, longitude: lon,
                         address: addr, countryCode: cc.isEmpty ? "US" : cc)
        }
    }

    private static func parseRow(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    field.append("\""); i = next
                } else { inQuotes.toggle() }
            } else if c == "," && !inQuotes {
                fields.append(field); field = ""
            } else { field.append(c) }
            i = line.index(after: i)
        }
        fields.append(field)
        return fields
    }

    private struct ColumnIndex {
        let name: Int; let lat: Int; let lon: Int; let address: Int; let country: Int
        init(header: [String]) {
            name    = header.firstIndex(where: { $0.contains("name") || $0.contains("title") || $0 == "poi" }) ?? -1
            lat     = header.firstIndex(where: { $0.contains("lat") }) ?? -1
            lon     = header.firstIndex(where: { $0.contains("lon") || $0.contains("lng") }) ?? -1
            address = header.firstIndex(where: { $0.contains("address") || $0.contains("地址") }) ?? -1
            country = header.firstIndex(where: { $0.contains("country") || $0.contains("crs") }) ?? -1
        }
    }
}
