import Foundation

/// Names for a trip's highest point when it is the top of a well-known mountain pass on a truck
/// route: "Donner Summit" instead of "Highest point" (Designer, ROA-60). A small hand-made list,
/// until the legendary-road zones of M7 exist.
///
/// A name is given only when the highest point is close to the pass and nearly as high, so a
/// drive through a base tunnel (the Gotthard road tunnel, far below the pass) gets no name.
public enum NamedSummit {
    public struct Pass: Sendable, Equatable {
        public var name: String
        public var latitude: Double
        public var longitude: Double
        public var altitudeMeters: Double
    }

    /// How far from the pass's top the highest point may be.
    public static let radiusMeters = 12_000.0
    /// The highest point must reach this share of the pass's altitude.
    public static let altitudeShare = 0.8

    public static let passes: [Pass] = [
        // USA
        Pass(name: "Donner Summit", latitude: 39.34, longitude: -120.34, altitudeMeters: 2_206),
        Pass(name: "Eisenhower Tunnel", latitude: 39.68, longitude: -105.91, altitudeMeters: 3_401),
        Pass(name: "Vail Pass", latitude: 39.53, longitude: -106.22, altitudeMeters: 3_243),
        Pass(name: "Sherman Summit", latitude: 41.13, longitude: -105.39, altitudeMeters: 2_633),
        Pass(name: "Parleys Summit", latitude: 40.76, longitude: -111.63, altitudeMeters: 2_145),
        Pass(name: "Snoqualmie Pass", latitude: 47.42, longitude: -121.41, altitudeMeters: 921),
        Pass(name: "Lookout Pass", latitude: 47.46, longitude: -115.70, altitudeMeters: 1_440),
        Pass(name: "Homestake Pass", latitude: 45.92, longitude: -112.41, altitudeMeters: 1_946),
        Pass(name: "Tejon Pass", latitude: 34.80, longitude: -118.88, altitudeMeters: 1_268),
        Pass(name: "Cajon Pass", latitude: 34.34, longitude: -117.45, altitudeMeters: 1_277),
        Pass(name: "Siskiyou Summit", latitude: 42.06, longitude: -122.60, altitudeMeters: 1_314),
        Pass(name: "Raton Pass", latitude: 36.99, longitude: -104.48, altitudeMeters: 2_388),
        // Canada
        Pass(name: "Rogers Pass", latitude: 51.30, longitude: -117.52, altitudeMeters: 1_330),
        Pass(name: "Kicking Horse Pass", latitude: 51.45, longitude: -116.29, altitudeMeters: 1_627),
        // Europe
        Pass(name: "Brenner Pass", latitude: 47.00, longitude: 11.51, altitudeMeters: 1_370),
        Pass(name: "Gotthard Pass", latitude: 46.56, longitude: 8.56, altitudeMeters: 2_106),
        Pass(name: "San Bernardino Pass", latitude: 46.50, longitude: 9.17, altitudeMeters: 2_066),
        Pass(name: "Simplon Pass", latitude: 46.25, longitude: 8.03, altitudeMeters: 2_005),
        Pass(name: "Great St Bernard Pass", latitude: 45.87, longitude: 7.17, altitudeMeters: 2_469),
        Pass(name: "Mont Cenis Pass", latitude: 45.26, longitude: 6.90, altitudeMeters: 2_083),
        Pass(name: "Arlberg Pass", latitude: 47.13, longitude: 10.21, altitudeMeters: 1_793),
        Pass(name: "Fern Pass", latitude: 47.36, longitude: 10.84, altitudeMeters: 1_216),
        Pass(name: "Radstädter Tauern Pass", latitude: 47.25, longitude: 13.56, altitudeMeters: 1_739),
        Pass(name: "Katschberg Pass", latitude: 47.06, longitude: 13.62, altitudeMeters: 1_641),
        Pass(name: "Col de Montgenèvre", latitude: 44.93, longitude: 6.72, altitudeMeters: 1_854),
        Pass(name: "Somport Pass", latitude: 42.79, longitude: -0.53, altitudeMeters: 1_632),
        Pass(name: "Col de Puymorens", latitude: 42.55, longitude: 1.82, altitudeMeters: 1_920),
        Pass(name: "Puerto de Pajares", latitude: 43.00, longitude: -5.77, altitudeMeters: 1_378),
        Pass(name: "Drumochter Pass", latitude: 56.86, longitude: -4.24, altitudeMeters: 462),
        Pass(name: "Shap Summit", latitude: 54.47, longitude: -2.69, altitudeMeters: 317),
    ]

    /// The pass at `point`, the trip's highest point, if there is one.
    public static func pass(at point: RoutePoint) -> Pass? {
        passes
            .map { (pass: $0, distance: Geo.distance(lat1: point.latitude, lon1: point.longitude,
                                                     lat2: $0.latitude, lon2: $0.longitude)) }
            .filter { $0.distance <= radiusMeters }
            .filter { item in point.altitude.map { $0 >= item.pass.altitudeMeters * altitudeShare } ?? true }
            .min { $0.distance < $1.distance }?
            .pass
    }

    public static func name(at point: RoutePoint) -> String? { pass(at: point)?.name }
}
