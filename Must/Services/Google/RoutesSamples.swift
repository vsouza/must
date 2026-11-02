import CoreLocation
import Foundation

#if DEBUG
/// Respostas de exemplo do Routes API v2 (formato da documentação) pra `-debugRoutes fake` e os testes.
/// Naka-Meguro → Udatsu (JST, 18:42): a pé até a estação, Hibiya (H) até Ebisu, a pé até o lugar.
enum RoutesSamples {
    static let transitJSON = """
    {
      "routes": [{
        "duration": "840s",
        "distanceMeters": 2350,
        "travelAdvisory": {"transitFare": {"currencyCode": "JPY", "units": "180"}},
        "legs": [{
          "steps": [
            {
              "travelMode": "WALK",
              "staticDuration": "240s",
              "distanceMeters": 320,
              "navigationInstruction": {"maneuver": "DEPART", "instructions": "Caminhe até a estação Hibiya, entrada oeste"}
            },
            {
              "travelMode": "TRANSIT",
              "staticDuration": "480s",
              "distanceMeters": 4200,
              "navigationInstruction": {"maneuver": "DEPART", "instructions": "Pegue a linha Hibiya"},
              "transitDetails": {
                "stopDetails": {
                  "arrivalStop": {"name": "Ebisu", "location": {"latLng": {"latitude": 35.6467, "longitude": 139.7100}}},
                  "departureStop": {"name": "Hibiya", "location": {"latLng": {"latitude": 35.6736, "longitude": 139.7597}}},
                  "arrivalTime": "2026-11-15T09:55:00Z",
                  "departureTime": "2026-11-15T09:47:00Z"
                },
                "localizedValues": {
                  "arrivalTime": {"time": {"text": "18:55"}},
                  "departureTime": {"time": {"text": "18:47"}}
                },
                "headsign": "Kita-Senju",
                "headway": "300s",
                "transitLine": {
                  "name": "Hibiya Line",
                  "nameShort": "H",
                  "color": "#b5b5ac",
                  "textColor": "#ffffff",
                  "agencies": [{"name": "Tokyo Metro"}],
                  "vehicle": {"name": {"text": "Subway"}, "type": "SUBWAY"}
                },
                "stopCount": 2
              }
            },
            {
              "travelMode": "WALK",
              "staticDuration": "300s",
              "distanceMeters": 350,
              "navigationInstruction": {"maneuver": "DEPART", "instructions": "Saia pela saída 1 e siga 350 m pela rua com ladeira"}
            }
          ]
        }]
      }]
    }
    """

    static let walkJSON = """
    {"routes": [{"duration": "1320s", "distanceMeters": 1640, "legs": [{"steps": [
      {"travelMode": "WALK", "staticDuration": "1320s", "distanceMeters": 1640,
       "navigationInstruction": {"maneuver": "DEPART", "instructions": "Siga a pé pela Meguro-dori"}}
    ]}]}]}
    """

    static let driveJSON = """
    {"routes": [{"duration": "540s", "distanceMeters": 3100}]}
    """

    /// Matriz (array de elementos, formato do computeRouteMatrix): 2 origens × 2 destinos.
    static let matrixJSON = """
    [
      {"originIndex": 0, "destinationIndex": 0, "duration": "0s", "distanceMeters": 0, "status": {}, "condition": "ROUTE_EXISTS"},
      {"originIndex": 0, "destinationIndex": 1, "duration": "660s", "distanceMeters": 900, "condition": "ROUTE_EXISTS"},
      {"originIndex": 1, "destinationIndex": 0, "duration": "600s", "distanceMeters": 820, "condition": "ROUTE_EXISTS"},
      {"originIndex": 1, "destinationIndex": 1, "duration": "0s", "distanceMeters": 0, "condition": "ROUTE_EXISTS"}
    ]
    """
}

extension TravelOptions {
    /// `-debugRoutes fake`: alternativas de mentira (prints, sem cota). Mesmo formato de resposta, sem rede.
    static func samples(region: Region, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [TravelOption] {
        var out: [TravelOption] = []
        if let transit = try? GoogleRoutes.parseTransit(Data(RoutesSamples.transitJSON.utf8)) { out.append(transit) }
        if var walk = try? GoogleRoutes.parseSimple(Data(RoutesSamples.walkJSON.utf8), mode: .walk) {
            walk.source = .routes
            out.append(walk)
        }
        let km = DaySolver.streetKm(from, to)
        out.append(TravelOption(mode: .taxi, source: .routes, minutes: 9, meters: Int(km * 1000), departs: nil, arrives: nil,
                                fare: region == .jp ? TaxiEstimate.jpy(km: km) : TaxiEstimate.brl(km: km), fareCurrency: region.currency))
        return out
    }
}
#endif
