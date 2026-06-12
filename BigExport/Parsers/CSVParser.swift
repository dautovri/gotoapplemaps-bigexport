import Foundation

enum CSVParser {
    static func parse(_ data: Data) throws -> [Place] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.invalidFormat
        }
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }
        let allLines = text.components(separatedBy: "\n")
                           .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
                           .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !allLines.isEmpty else { throw ParseError.noPlacesFound }

        // Auto-detect delimiter from whichever candidate appears most in the first non-empty line
        let delim = detectDelimiter(allLines[0])

        // Smart header scan: skip preamble/metadata rows, find first row that has recognisable columns
        guard let (headerIdx, header) = findHeader(in: allLines, delimiter: delim) else {
            throw ParseError.missingColumns(
                "Could not find a header row. Expected columns: Title+URL, or lat/lon columns."
            )
        }
        let dataLines = Array(allLines.dropFirst(headerIdx + 1))
        guard !dataLines.isEmpty else { throw ParseError.noPlacesFound }

        // Mode 1: coordinate columns (lat/lon explicit)
        let ci = CoordIndex(header: header)
        if ci.lat >= 0 && ci.lon >= 0 {
            return parseCoordRows(dataLines, idx: ci, delimiter: delim)
        }

        // Mode 2: Google Maps Takeout (Title + URL)
        let ti = header.firstIndex(where: { $0.contains("title") || $0.contains("name") || $0 == "tytuł" || $0 == "titre" }) ?? -1
        let ui = header.firstIndex(where: { $0.contains("url") || $0.contains("link") }) ?? -1
        let ni = header.firstIndex(where: { $0.contains("note") || $0.contains("notatka") || $0.contains("comment") || $0.contains("description") }) ?? -1
        if ti >= 0 && ui >= 0 {
            return parseTakeoutRows(dataLines, titleIdx: ti, urlIdx: ui, noteIdx: ni, delimiter: delim)
        }

        throw ParseError.missingColumns(
            "Found: \(header.joined(separator: ", ")).\nNeed lat/lon columns, or Title+URL (Google Maps Takeout)."
        )
    }

    // MARK: - Header detection

    // Returns (lineIndex, lowercased columns) of the first row that looks like a header
    private static func findHeader(in lines: [String], delimiter: Character) -> (Int, [String])? {
        for (i, line) in lines.enumerated() {
            let row = parseRow(line, delimiter: delimiter)
                        .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            let ci = CoordIndex(header: row)
            let hasCoords = ci.lat >= 0 && ci.lon >= 0
            let hasTitle = row.contains(where: { $0.contains("title") || $0.contains("name") || $0 == "tytuł" || $0 == "titre" })
            let hasURL   = row.contains(where: { $0.contains("url") || $0.contains("link") })
            if hasCoords || (hasTitle && hasURL) { return (i, row) }
        }
        return nil
    }

    // MARK: - Coordinate-column rows

    private static func parseCoordRows(_ lines: [String], idx: CoordIndex, delimiter: Character) -> [Place] {
        lines.compactMap { line in
            let cols = parseRow(line, delimiter: delimiter)
            guard cols.count > max(idx.lat, idx.lon) else { return nil }
            guard let lat = Double(cols[idx.lat].trimmingCharacters(in: .whitespaces)),
                  let lon = Double(cols[idx.lon].trimmingCharacters(in: .whitespaces)) else { return nil }
            let name = idx.name >= 0 && idx.name < cols.count
                ? cols[idx.name].trimmingCharacters(in: .whitespaces) : "Place"
            guard !name.isEmpty else { return nil }
            let addr = idx.address >= 0 && idx.address < cols.count ? cols[idx.address] : ""
            let cc   = idx.country >= 0 && idx.country < cols.count ? cols[idx.country] : "US"
            return Place(name: name, latitude: lat, longitude: lon,
                         address: addr, countryCode: cc.isEmpty ? "US" : cc)
        }
    }

    // MARK: - Google Maps Takeout rows

    private static func parseTakeoutRows(
        _ lines: [String], titleIdx: Int, urlIdx: Int, noteIdx: Int, delimiter: Character
    ) -> [Place] {
        lines.compactMap { line in
            let cols = parseRow(line, delimiter: delimiter)
            guard cols.count > max(titleIdx, urlIdx) else { return nil }
            let title = cols[titleIdx].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            let url  = cols[urlIdx].trimmingCharacters(in: .whitespaces)
            let note = noteIdx >= 0 && noteIdx < cols.count ? cols[noteIdx].trimmingCharacters(in: .whitespaces) : ""

            if let (lat, lon) = coordsFromGoogleURL(url) {
                return Place(name: title, latitude: lat, longitude: lon, address: note, countryCode: "US")
            }

            // No coords in URL — extract place name for later geocoding
            let query = placeNameFromGoogleURL(url) ?? title
            return Place(name: title, latitude: 0, longitude: 0,
                         address: note, countryCode: "US", geocodingQuery: query)
        }
    }

    // MARK: - URL helpers

    // Resolves coordinates straight from a Google Maps URL, in priority order:
    //   1. @lat,lon            (place/coordinate URLs)
    //   2. /search/lat,lon     (dropped pins)
    //   3. S2 cell ID in data= (Takeout place URLs — exact, offline, no geocoding)
    static func coordsFromGoogleURL(_ url: String) -> (Double, Double)? {
        let patterns = [
            #"@(-?[\d.]+),(-?[\d.]+)"#,
            #"/search/(-?[\d.]+),(-?[\d.]+)"#,
        ]
        for pattern in patterns {
            guard let range = url.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(url[range])
            let coords = match.drop(while: { !$0.isNumber && $0 != "-" })
            let parts = coords.components(separatedBy: ",")
            guard parts.count >= 2,
                  let lat = Double(parts[0]),
                  let lon = Double(parts[1]) else { continue }
            return (lat, lon)
        }
        // Google Takeout place URLs embed the location as an S2 cell ID in data=
        if let s2 = S2CellID.fromGoogleURL(url) { return (s2.lat, s2.lon) }
        return nil
    }

    // Extract URL-decoded place name from maps/place/Name/data= pattern
    private static func placeNameFromGoogleURL(_ url: String) -> String? {
        guard let range = url.range(of: #"maps/place/([^/?#]+)"#, options: .regularExpression) else { return nil }
        let segment = String(url[range]).replacingOccurrences(of: "maps/place/", with: "")
        let withSpaces = segment.replacingOccurrences(of: "+", with: " ")
        return withSpaces.removingPercentEncoding ?? withSpaces
    }

    // MARK: - Delimiter detection

    private static func detectDelimiter(_ line: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        let counts = candidates.map { d in (d, line.filter { $0 == d }.count) }
        return counts.max(by: { $0.1 < $1.1 })?.0 ?? ","
    }

    // MARK: - RFC 4180 row parser

    static func parseRow(_ line: String, delimiter: Character = ",") -> [String] {
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
            } else if c == delimiter && !inQuotes {
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
