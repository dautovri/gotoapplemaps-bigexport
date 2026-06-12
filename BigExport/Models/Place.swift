import Foundation
import MapKit

struct Place: Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let countryCode: String
    let geocodingQuery: String?  // non-nil → needs geocoding, lat/lon are 0

    init(name: String, latitude: Double, longitude: Double,
         address: String, countryCode: String, geocodingQuery: String? = nil) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.countryCode = countryCode
        self.geocodingQuery = geocodingQuery
    }

    var needsGeocoding: Bool { geocodingQuery != nil }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func resolved(latitude: Double, longitude: Double) -> Place {
        Place(name: name, latitude: latitude, longitude: longitude,
              address: address, countryCode: countryCode, geocodingQuery: nil)
    }
}

struct ImportJob: Identifiable {
    let id = UUID()
    var guideName: String
    var places: [Place]
    var fileExtension: String = "json"
    var status: Status = .ready

    enum Status: Equatable {
        case ready
        case geocoding(Int, Int)  // resolved, total
        case importing(Int, Int)  // saved, total
        case done(Int)            // collections created
        case failed(String)
    }

    var isActive: Bool {
        switch status {
        case .geocoding, .importing: return true
        default: return false
        }
    }

    var isDone: Bool {
        if case .done = status { return true }
        return false
    }

    var resolvedPlaces: [Place] { places.filter { !$0.needsGeocoding } }
    var unresolvedCount: Int { places.filter { $0.needsGeocoding }.count }

    static let maxPerCollection = 5000
}
