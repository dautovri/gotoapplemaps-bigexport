import Foundation

enum GeoJSONParser {
    static func parse(_ data: Data) throws -> [Place] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            throw ParseError.invalidFormat
        }
        return features.compactMap { feature in
            guard let geometry = feature["geometry"] as? [String: Any],
                  let coords = geometry["coordinates"] as? [Double],
                  coords.count >= 2,
                  let props = feature["properties"] as? [String: Any],
                  let location = props["location"] as? [String: Any],
                  let name = location["name"] as? String, !name.isEmpty
            else { return nil }
            return Place(
                name: name,
                latitude: coords[1],
                longitude: coords[0],
                address: location["address"] as? String ?? "",
                countryCode: location["country_code"] as? String ?? "US"
            )
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
