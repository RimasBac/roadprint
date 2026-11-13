import MapKit
import RoadPrintCore

/// TEMPORARY, with the test tool (`TestTripView`): asks Apple Maps for the driving route between
/// two places, so a made-up trip follows the real road instead of a straight line.
///
/// This is the only place the app uses the network, and it sends only the two city centres the
/// tester typed, never a location of the phone. Remove it with the test tool.
enum TestDrive {
    /// The road's line in driving order, or nil when there is no route (offline, no road
    /// between the places, or the service refused).
    static func road(from: GeoCoordinate, to: GeoCoordinate) async -> [GeoCoordinate]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        request.transportType = .automobile
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        let polyline = route.polyline
        let count = polyline.pointCount
        guard count > 1 else { return nil }
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
        return coordinates.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
