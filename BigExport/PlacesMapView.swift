import SwiftUI
import MapKit

struct PlacesMapView: NSViewRepresentable {
    let places: [Place]

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.showsCompass = true
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        let annotations = places.filter { !$0.needsGeocoding }.prefix(2000).map { place -> MKPointAnnotation in
            let a = MKPointAnnotation()
            a.title = place.name
            a.coordinate = place.coordinate
            return a
        }
        map.addAnnotations(annotations)
        if let first = annotations.first {
            let coords = annotations.map(\.coordinate)
            let lats = coords.map(\.latitude)
            let lons = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                                longitude: (minLon + maxLon) / 2)
            let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.3 + 0.1,
                                        longitudeDelta: (maxLon - minLon) * 1.3 + 0.1)
            map.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
            _ = first
        }
    }
}
