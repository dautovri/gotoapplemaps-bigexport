import Foundation

final class KMLParser: NSObject, XMLParserDelegate {
    private var places: [Place] = []
    private var currentName = ""
    private var currentDesc = ""
    private var currentCoords = ""
    private var inPlacemark = false
    private var currentElement = ""

    static func parse(_ data: Data) throws -> [Place] {
        let parser = KMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { throw ParseError.invalidFormat }
        guard !parser.places.isEmpty else { throw ParseError.noPlacesFound }
        return parser.places
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = name
        if name == "Placemark" { inPlacemark = true; currentName = ""; currentDesc = ""; currentCoords = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inPlacemark else { return }
        switch currentElement {
        case "name":        currentName    += string
        case "description": currentDesc    += string
        case "coordinates": currentCoords  += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if name == "Placemark" {
            inPlacemark = false
            let trimmed = currentCoords.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: ",")
            if parts.count >= 2,
               let lon = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let lat = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               !currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                places.append(Place(
                    name: currentName.trimmingCharacters(in: .whitespacesAndNewlines),
                    latitude: lat, longitude: lon,
                    address: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                    countryCode: "US"
                ))
            }
        }
        currentElement = ""
    }
}
