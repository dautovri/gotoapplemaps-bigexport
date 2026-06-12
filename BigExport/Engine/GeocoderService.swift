import Foundation
import CoreLocation
import MapKit

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
        guard var query = place.geocodingQuery, !query.isEmpty else { return nil }

        // Shortened Google link — expand the redirect, then read coordinates
        // straight from the full URL (exact, no search needed).
        if GoogleURL.isShortLink(query) {
            guard let expanded = await GoogleURL.expandShortLink(query) else { return nil }
            if let (lat, lon) = GoogleURL.coords(from: expanded) {
                return place.resolved(latitude: lat, longitude: lon)
            }
            // expanded URL had no coords — fall through to searching by name
            query = GoogleURL.placeName(from: expanded) ?? place.name
        }

        // POI search first. Google Maps lists store bare business names ("Kimchi
        // Princess") with no address; MKLocalSearch is built for that and finds
        // the actual place. CLGeocoder.geocodeAddressString treats the name as an
        // address and mislocates it worldwide (e.g. Berlin restaurant → India).
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let resp = try? await MKLocalSearch(request: req).start(),
           let item = resp.mapItems.first {
            let c = item.placemark.coordinate
            return place.resolved(latitude: c.latitude, longitude: c.longitude)
        }

        // Fallback: address geocoder, for entries that are real addresses.
        if let placemarks = try? await CLGeocoder().geocodeAddressString(query),
           let location = placemarks.first?.location {
            return place.resolved(latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude)
        }
        return nil
    }
}

