import Foundation

enum GeoJSONParser {
    static func parse(_ data: Data) throws -> [Place] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            throw ParseError.invalidFormat
        }
        return features.compactMap { feature in
            let props = feature["properties"] as? [String: Any] ?? [:]
            let location = props["location"] as? [String: Any] ?? [:]
            let googleURL = props["google_maps_url"] as? String ?? ""

            // Resolve coordinates first: geometry, then the URL. Takeout writes
            // [0,0] when the export has "no location information" — recover from
            // google_maps_url (?q=lat,lng or ftid S2 cell).
            let geometry = feature["geometry"] as? [String: Any]
            var coordinate: (lat: Double, lon: Double)?
            if let c = geometry?["coordinates"] as? [Double], c.count >= 2, !(c[0] == 0 && c[1] == 0) {
                coordinate = (c[1], c[0])
            } else if let c = GoogleURL.coords(from: googleURL) {
                coordinate = c
            }

            // Name: location.name → ?q= place text → address → a generated label
            // when we still have a valid coordinate (a pin with no name is a
            // real saved place; don't drop it).
            let urlName = GoogleURL.placeName(from: googleURL)
            let name = (location["name"] as? String)
                ?? urlName.map { $0.components(separatedBy: ",")[0] }
                ?? (location["address"] as? String)
                ?? (coordinate != nil ? "Saved pin" : nil)
            guard let name, !name.isEmpty else { return nil }

            let address = location["address"] as? String ?? urlName ?? ""
            let country = location["country_code"] as? String ?? "US"

            if let coordinate {
                return Place(name: name, latitude: coordinate.lat, longitude: coordinate.lon,
                             address: address, countryCode: country)
            }
            if GoogleURL.isShortLink(googleURL) {
                return Place(name: name, latitude: 0, longitude: 0,
                             address: address, countryCode: country, geocodingQuery: googleURL)
            }
            let query = [name, address].filter { !$0.isEmpty }.joined(separator: ", ")
            guard !query.isEmpty else { return nil }
            return Place(name: name, latitude: 0, longitude: 0,
                         address: address, countryCode: country, geocodingQuery: query)
        }
    }
}

enum ParseError: LocalizedError {
    case invalidFormat
    case noPlacesFound
    case missingColumns(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:          return "Unrecognized file format."
        case .noPlacesFound:          return "No valid places found in this file."
        case .missingColumns(let msg): return "Missing required columns. \(msg)"
        }
    }
}
