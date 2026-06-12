import SwiftUI
import MapKit

struct PlacesMapView: NSViewRepresentable {
    let places: [Place]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.showsCompass = true
        map.delegate = context.coordinator
        // Register reusable views so overlapping pins collapse into a numbered
        // cluster badge (Apple Maps behavior) that splits apart as you zoom.
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: Coordinator.pinID)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
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
        if !annotations.isEmpty {
            let coords = annotations.map(\.coordinate)
            let lats = coords.map(\.latitude)
            let lons = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                                longitude: (minLon + maxLon) / 2)
            let span = MKCoordinateSpan(
                latitudeDelta: min((maxLat - minLat) * 1.3 + 0.1, 140),
                longitudeDelta: min((maxLon - minLon) * 1.3 + 0.1, 340))
            map.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pinID = "bigexport.pin"

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = .systemRed
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.titleVisibility = .hidden
                return view
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Coordinator.pinID, for: annotation) as! MKMarkerAnnotationView
            view.markerTintColor = .systemRed
            view.clusteringIdentifier = "place"   // overlapping pins group together
            view.displayPriority = .defaultLow     // let the map collapse dense clusters
            return view
        }
    }
}
