import CoreLocation
import Foundation

/// As alternativas da tela Como chegar: metrô/trem (Routes TRANSIT), a pé e táxi estimado.
/// Cada uma tem cadeia de fallback sem erro na UI: Routes → MapKit ETA (a pé) → estimativa do solver.
enum TravelOptions {
    static func build(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, departAt: Date, region: Region,
                      routes: any RoutesProviding, apiKey: String? = Secrets.googlePlacesKey, http: HTTP = HTTP()) async -> [TravelOption] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "debugRoutes") == "fake" { return samples(region: region, from: from, to: to) }
        #endif
        let meters = DaySolver.streetKm(from, to) * 1000
        var out: [TravelOption] = []

        // Transporte: só com resposta do Routes (sem MapKit: ele não dá trajeto de metrô com paradas).
        if let apiKey, DevOverrides.liveData,
           let transit = try? await GoogleRoutes.transit(from: from, to: to, departAt: departAt, apiKey: apiKey, http: http) {
            out.append(transit)
        }

        // A pé: Routes WALK, depois MapKit, depois a estimativa (80 m/min).
        var walk: TravelOption?
        if let apiKey, DevOverrides.liveData {
            walk = try? await GoogleRoutes.simple(from: from, to: to, mode: "WALK", apiKey: apiKey, http: http).map {
                var option = $0
                option.mode = .walk
                return option
            }
        }
        if walk == nil, let seconds = try? await routes.eta(from: from, to: to, transit: false) {
            walk = TravelOption(mode: .walk, source: .mapKit, minutes: max(1, Int((seconds / 60).rounded(.up))), meters: Int(meters), departs: nil, arrives: nil)
        }
        out.append(walk ?? TravelOption(mode: .walk, source: .estimate, minutes: Walk.minutes(meters), meters: Int(meters), departs: nil, arrives: nil))

        // Táxi: ETA de carro (Routes DRIVE) e tarifa estimada pela distância. Nunca é tarifa real.
        let km = Double(out.last?.meters ?? Int(meters)) / 1000
        var taxiMinutes = max(3, Int((km / 25 * 60).rounded(.up)))
        var source = TravelOption.Source.estimate
        if let apiKey, DevOverrides.liveData,
           let drive = try? await GoogleRoutes.simple(from: from, to: to, mode: "DRIVE", apiKey: apiKey, http: http) {
            taxiMinutes = drive.minutes
            source = .routes
        }
        let fare = region == .jp ? TaxiEstimate.jpy(km: km) : TaxiEstimate.brl(km: km)
        out.append(TravelOption(mode: .taxi, source: source, minutes: taxiMinutes, meters: Int(km * 1000), departs: nil, arrives: nil,
                                fare: fare, fareCurrency: region.currency))
        return out
    }
}
