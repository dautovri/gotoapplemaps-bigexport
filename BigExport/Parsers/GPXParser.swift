import Foundation

// GPX waypoints: <wpt lat="…" lon="…"><name>…</name><desc>…</desc></wpt>
final class GPXParser: NSObject, XMLParserDelegate {
    private var places: [Place] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentName = ""
    private var currentDesc = ""
    private var currentElement = ""
    private var inWaypoint = false
    private var waypointIndex = 0

    static func parse(_ data: Data) throws -> [Place] {
        let parser = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { throw ParseError.invalidFormat }
        guard !parser.places.isEmpty else { throw ParseError.noPlacesFound }
        return parser.places
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = name
        if name == "wpt" {
            inWaypoint = true
            currentLat = attributes["lat"].flatMap(Double.init)
            currentLon = attributes["lon"].flatMap(Double.init)
            currentName = ""; currentDesc = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inWaypoint else { return }
        switch currentElement {
        case "name": currentName += string
        case "desc", "cmt": currentDesc += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if name == "wpt" {
            inWaypoint = false
            waypointIndex += 1
            if let lat = currentLat, let lon = currentLon {
                let trimmed = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
                places.append(Place(
                    name: trimmed.isEmpty ? "Waypoint \(waypointIndex)" : trimmed,
                    latitude: lat, longitude: lon,
                    address: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                    countryCode: "US"
                ))
            }
        }
        currentElement = ""
    }
}
