import Foundation

// All Google Maps URL intelligence in one place. Coordinate sources in
// priority order — exact sources first, the approximate S2 cell decode last:
//   1. !3d<lat>!4d<lng>      exact place coords (full place URLs)
//   2. @lat,lng              camera position (place/coordinate URLs)
//   3. /search/lat,lng       dropped pins
//   4. ?q=lat,lng            Takeout "no location info" saved places
//   5. ?ll= / ?center= / ?destination=lat,lng
//   6. S2 cell ID            !1s0x…:0x… or ftid=0x…:0x… (approximate cell center)
enum GoogleURL {

    static func coords(from url: String) -> (lat: Double, lon: Double)? {
        // 1. !3d!4d — exact place coordinates
        if let r = url.range(of: #"!3d(-?[\d.]+)!4d(-?[\d.]+)"#, options: .regularExpression) {
            let m = String(url[r]).dropFirst(3) // drop "!3d"
            let parts = m.components(separatedBy: "!4d")
            if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
               valid(lat, lon) { return (lat, lon) }
        }
        // 2–3. @lat,lng and /search/lat,lng
        for pattern in [#"@(-?[\d.]+),(-?[\d.]+)"#, #"/search/(-?[\d.]+),(-?[\d.]+)"#] {
            if let pair = pairMatch(url, pattern) { return pair }
        }
        // 4–5. query parameters carrying a bare coordinate pair
        for pattern in [#"[?&]q=(-?[\d.]+),(-?[\d.]+)"#,
                        #"[?&]ll=(-?[\d.]+),(-?[\d.]+)"#,
                        #"[?&]center=(-?[\d.]+),(-?[\d.]+)"#,
                        #"[?&]destination=(-?[\d.]+),(-?[\d.]+)"#] {
            if let pair = pairMatch(url, pattern) { return pair }
        }
        // 6. S2 cell ID embedded in data= or ftid=
        if let s2 = s2Coords(from: url) { return s2 }
        return nil
    }

    // Decoded place name from /place/Name/ or a non-coordinate ?q= value.
    static func placeName(from url: String) -> String? {
        if let r = url.range(of: #"maps/place/([^/?#]+)"#, options: .regularExpression) {
            let segment = String(url[r]).replacingOccurrences(of: "maps/place/", with: "")
            return decode(segment)
        }
        if let r = url.range(of: #"[?&]q=([^&#]+)"#, options: .regularExpression) {
            let raw = String(url[r]).replacingOccurrences(of: #"^[?&]q="#, with: "", options: .regularExpression)
            let text = decode(raw)
            // skip if it's actually a coordinate pair
            let parts = text.components(separatedBy: ",")
            if parts.count == 2, Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
               Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil { return nil }
            return text
        }
        return nil
    }

    static func isShortLink(_ url: String) -> Bool {
        url.contains("maps.app.goo.gl") || url.contains("goo.gl/maps")
    }

    // Expand a shortened link by following redirects; returns the final URL.
    static func expandShortLink(_ url: String) async -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 10
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return resp.url?.absoluteString
    }

    // MARK: - helpers

    private static func s2Coords(from url: String) -> (Double, Double)? {
        for pattern in [#"!1s(0x[0-9a-fA-F]+):0x[0-9a-fA-F]+"#,
                        #"[?&]ftid=(0x[0-9a-fA-F]+):0x[0-9a-fA-F]+"#] {
            guard let r = url.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(url[r])
            guard let hexRange = match.range(of: #"0x[0-9a-fA-F]+"#, options: .regularExpression),
                  let coords = S2CellID.toLatLon(String(match[hexRange])) else { continue }
            return (coords.lat, coords.lon)
        }
        return nil
    }

    private static func pairMatch(_ url: String, _ pattern: String) -> (Double, Double)? {
        guard let r = url.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(url[r])
        let coords = match.drop(while: { !$0.isNumber && $0 != "-" })
        let parts = coords.components(separatedBy: ",")
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              valid(lat, lon) else { return nil }
        return (lat, lon)
    }

    private static func valid(_ lat: Double, _ lon: Double) -> Bool {
        (-90...90).contains(lat) && (-180...180).contains(lon) && !(lat == 0 && lon == 0)
    }

    private static func decode(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
