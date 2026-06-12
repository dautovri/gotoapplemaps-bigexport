import Foundation
import MapKit

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let countryCode: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
        case importing(Int, Int)  // saved, total
        case done(Int)            // collections created
        case failed(String)
    }

    var isActive: Bool {
        if case .importing = status { return true }
        return false
    }

    var isDone: Bool {
        if case .done = status { return true }
        return false
    }

    static let maxPerCollection = 5000
}
