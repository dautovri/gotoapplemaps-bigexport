import Foundation
import CoreLocation

enum GeocoderService {
    typealias ProgressHandler = @Sendable (Int, Int) -> Void

    // Resolves all places that have geocodingQuery set.
    // Returns the full array with unresolved entries either resolved or dropped.
    static func resolve(
        _ places: [Place],
        onProgress: @escaping ProgressHandler
    ) async -> [Place] {
        let needsGeo = places.filter { $0.needsGeocoding }
        guard !needsGeo.isEmpty else { return places }

        let total = needsGeo.count
        nonisolated(unsafe) var done = 0

        // Geocode in concurrent batches of 4 (CLGeocoder is one-request-per-instance)
        let batches = needsGeo.chunked(by: 4)
        var resolved: [UUID: Place] = [:]

        for batch in batches {
            let results: [(UUID, Place?)] = await withTaskGroup(of: (UUID, Place?).self) { group in
                for place in batch {
                    group.addTask { (place.id, await geocodeOne(place)) }
                }
                var out: [(UUID, Place?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (uuid, place) in results {
                if let p = place { resolved[uuid] = p }
                done += 1
                let snapshot = done
                await MainActor.run { onProgress(snapshot, total) }
            }
            // Brief pause between batches to be polite to Apple's geocoding service
            try? await Task.sleep(for: .milliseconds(300))
        }

        // Rebuild array: replace geocoded entries, drop failures
        return places.compactMap { place in
            guard place.needsGeocoding else { return place }
            return resolved[place.id]
        }
    }

    private static func geocodeOne(_ place: Place) async -> Place? {
        guard let query = place.geocodingQuery, !query.isEmpty else { return nil }
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.geocodeAddressString(query)
        guard let location = placemarks?.first?.location else { return nil }
        return place.resolved(latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude)
    }
}

