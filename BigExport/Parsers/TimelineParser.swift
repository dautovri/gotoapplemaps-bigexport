import Foundation

// Google Timeline (Location History) exports — three known shapes:
//   1. Classic Takeout: {"timelineObjects":[{"placeVisit":{"location":{
//        "latitudeE7":…, "longitudeE7":…, "name":…, "address":…}}}]}
//   2. 2024+ Android:   {"semanticSegments":[{"visit":{"topCandidate":{
//        "placeLocation":{"latLng":"52.52°, 13.40°"}}}}]}
//   3. iOS on-device:   [{"visit":{"topCandidate":{"placeLocation":"geo:52.52,13.40"}}}]
// Visits repeat; results are deduped by coordinate.
enum TimelineParser {
    static func parse(_ data: Data) throws -> [Place] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ParseError.invalidFormat
        }
        var places: [Place] = []
        var seen = Set<String>()

        func add(name: String?, address: String?, lat: Double, lon: Double) {
            guard (-90...90).contains(lat), (-180...180).contains(lon),
                  !(lat == 0 && lon == 0) else { return }
            let key = String(format: "%.5f,%.5f", lat, lon)
            guard seen.insert(key).inserted else { return }
            let label = name?.trimmingCharacters(in: .whitespaces)
            places.append(Place(
                name: (label?.isEmpty == false) ? label! : "Visited place \(places.count + 1)",
                latitude: lat, longitude: lon,
                address: address ?? "", countryCode: "US"
            ))
        }

        func parseLatLngString(_ s: String) -> (Double, Double)? {
            // "52.5200766°, 13.4049540°" or "geo:52.520,13.404"
            let cleaned = s.replacingOccurrences(of: "°", with: "")
                           .replacingOccurrences(of: "geo:", with: "")
            let parts = cleaned.components(separatedBy: ",")
            guard parts.count >= 2,
                  let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (lat, lon)
        }

        func handleVisit(_ visit: [String: Any]) {
            guard let top = visit["topCandidate"] as? [String: Any] else { return }
            if let locDict = top["placeLocation"] as? [String: Any],
               let latLng = locDict["latLng"] as? String,
               let (lat, lon) = parseLatLngString(latLng) {
                add(name: (top["name"] as? String) ?? (top["semanticType"] as? String),
                    address: top["address"] as? String, lat: lat, lon: lon)
            } else if let locString = top["placeLocation"] as? String,
                      let (lat, lon) = parseLatLngString(locString) {
                add(name: top["semanticType"] as? String, address: nil, lat: lat, lon: lon)
            }
        }

        if let dict = root as? [String: Any] {
            // Shape 1
            for obj in dict["timelineObjects"] as? [[String: Any]] ?? [] {
                guard let pv = obj["placeVisit"] as? [String: Any],
                      let loc = pv["location"] as? [String: Any],
                      let latE7 = loc["latitudeE7"] as? Double,
                      let lonE7 = loc["longitudeE7"] as? Double else { continue }
                add(name: loc["name"] as? String, address: loc["address"] as? String,
                    lat: latE7 / 1e7, lon: lonE7 / 1e7)
            }
            // Shape 2
            for seg in dict["semanticSegments"] as? [[String: Any]] ?? [] {
                if let visit = seg["visit"] as? [String: Any] { handleVisit(visit) }
            }
        } else if let array = root as? [[String: Any]] {
            // Shape 3
            for seg in array {
                if let visit = seg["visit"] as? [String: Any] { handleVisit(visit) }
            }
        }

        guard !places.isEmpty else { throw ParseError.noPlacesFound }
        return places
    }

    // Cheap sniff: does this JSON look like a Timeline export (vs GeoJSON)?
    static func looksLikeTimeline(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(2048), encoding: .utf8) else { return false }
        return head.contains("timelineObjects") || head.contains("semanticSegments")
            || head.contains("placeLocation")
    }
}
