import CoreLocation
import UIKit

/// Rotas por deep link (Apple Maps / Google Maps), com fallback web.
@MainActor
enum MapsLinks {
    enum Mode { case walking, transit }

    static func appleMaps(to c: CLLocationCoordinate2D, name: String? = nil, mode: Mode = .walking) -> URL? {
        var comps = URLComponents(string: "maps://")
        comps?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(c.latitude),\(c.longitude)"),
            URLQueryItem(name: "dirflg", value: mode == .walking ? "w" : "r"),
        ] + (name.map { [URLQueryItem(name: "q", value: $0)] } ?? [])
        return comps?.url
    }

    static func googleMaps(to c: CLLocationCoordinate2D, mode: Mode = .walking) -> URL? {
        var comps = URLComponents(string: "comgooglemaps://")
        comps?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(c.latitude),\(c.longitude)"),
            URLQueryItem(name: "directionsmode", value: mode == .walking ? "walking" : "transit"),
        ]
        return comps?.url
    }

    static func googleMapsWeb(to c: CLLocationCoordinate2D, mode: Mode = .walking) -> URL? {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(c.latitude),\(c.longitude)&travelmode=\(mode == .walking ? "walking" : "transit")")
    }

    static func openApple(to c: CLLocationCoordinate2D, name: String? = nil, mode: Mode = .walking) {
        guard let url = appleMaps(to: c, name: name, mode: mode) else { return }
        UIApplication.shared.open(url)
    }

    static func openGoogle(to c: CLLocationCoordinate2D, mode: Mode = .walking) {
        if let url = googleMaps(to: c, mode: mode), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = googleMapsWeb(to: c, mode: mode) {
            UIApplication.shared.open(web)
        }
    }
}
