import Foundation

enum CSVParser {
    static func parse(_ data: Data) throws -> [Place] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.invalidFormat
        }
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }
        var lines = text.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw ParseError.noPlacesFound }

        let header = parseRow(lines.removeFirst())
                        .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Mode 1: coordinate CSV — has explicit lat/lon columns
        let idx = CoordIndex(header: header)
        if idx.lat >= 0 && idx.lon >= 0 {
            return parseCoordRows(lines, idx: idx)
        }

        // Mode 2: Google Maps Takeout — Title + URL columns, coords from URL
        let ti = header.firstIndex(where: { $0.contains("title") || $0.contains("name") }) ?? -1
        let ui = header.firstIndex(where: { $0.contains("url") || $0.contains("link") }) ?? -1
        let ni = header.firstIndex(where: { $0.contains("note") || $0.contains("comment") || $0.contains("description") }) ?? -1
        if ti >= 0 && ui >= 0 {
            return parseTakeoutRows(lines, titleIdx: ti, urlIdx: ui, noteIdx: ni)
        }

        throw ParseError.missingColumns(
            "Found: \(header.joined(separator: ", ")).\nNeed lat/lon columns, or Title+URL (Google Maps Takeout)."
        )
    }

    // MARK: - Coordinate-column rows

    private static func parseCoordRows(_ lines: [String], idx: CoordIndex) -> [Place] {
        lines.compactMap { line in
            let cols = parseRow(line)
            guard cols.count > max(idx.name >= 0 ? idx.name : 0, idx.lat, idx.lon) else { return nil }
            let lat = Double(cols[idx.lat].trimmingCharacters(in: .whitespaces))
            let lon = Double(cols[idx.lon].trimmingCharacters(in: .whitespaces))
            guard let lat, let lon else { return nil }
            let name = idx.name >= 0 && idx.name < cols.count
                ? cols[idx.name].trimmingCharacters(in: .whitespaces)
                : "Place"
            guard !name.isEmpty else { return nil }
            let addr = idx.address >= 0 && idx.address < cols.count ? cols[idx.address] : ""
            let cc   = idx.country >= 0 && idx.country < cols.count ? cols[idx.country] : "US"
            return Place(name: name, latitude: lat, longitude: lon,
                         address: addr, countryCode: cc.isEmpty ? "US" : cc)
        }
    }

    // MARK: - Google Maps Takeout rows (Title, Note, URL, Comment)

    private static func parseTakeoutRows(_ lines: [String], titleIdx: Int, urlIdx: Int, noteIdx: Int) -> [Place] {
        lines.compactMap { line in
            let cols = parseRow(line)
            guard cols.count > max(titleIdx, urlIdx) else { return nil }
            let title = cols[titleIdx].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            let url   = cols[urlIdx].trimmingCharacters(in: .whitespaces)
            let note  = noteIdx >= 0 && noteIdx < cols.count ? cols[noteIdx].trimmingCharacters(in: .whitespaces) : ""

            guard let (lat, lon) = coordsFromGoogleURL(url) else { return nil }
            return Place(name: title, latitude: lat, longitude: lon, address: note, countryCode: "US")
        }
    }

    // Extract @lat,lon from a Google Maps URL
    private static func coordsFromGoogleURL(_ url: String) -> (Double, Double)? {
        guard let range = url.range(of: #"@(-?[\d.]+),(-?[\d.]+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(url[range])
        let parts = match.dropFirst().components(separatedBy: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }

    // MARK: - RFC 4180 row parser

    static func parseRow(_ line: String) -> [String] {
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

    // MARK: - Column index (coordinate mode)

    private struct CoordIndex {
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
