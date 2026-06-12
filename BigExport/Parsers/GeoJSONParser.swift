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

            // Name: location.name → non-coordinate ?q= text → address.
            // Coordinate-only saved pins (?q=lat,lng) have no name anywhere —
            // fall back to a generated label rather than dropping the place.
            let urlName = GoogleURL.placeName(from: googleURL)
            let name = (location["name"] as? String)
                ?? urlName.map { $0.components(separatedBy: ",")[0] }
                ?? (location["address"] as? String)
                ?? (GoogleURL.coords(from: googleURL) != nil ? "Saved pin" : nil)
            guard let name, !name.isEmpty else { return nil }

            let address = location["address"] as? String ?? urlName ?? ""
            let country = location["country_code"] as? String ?? "US"

            // Coordinates: geometry first; Takeout writes [0,0] when the export
            // has "no location information" — recover from google_maps_url
            // (?q=lat,lng or ftid S2 cell), else queue for geocoding.
            let geometry = feature["geometry"] as? [String: Any]
            if let coords = geometry?["coordinates"] as? [Double], coords.count >= 2,
               !(coords[0] == 0 && coords[1] == 0) {
                return Place(name: name, latitude: coords[1], longitude: coords[0],
                             address: address, countryCode: country)
            }
            if let (lat, lon) = GoogleURL.coords(from: googleURL) {
                return Place(name: name, latitude: lat, longitude: lon,
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
