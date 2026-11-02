import CoreLocation
import Foundation

/// Um passo de um trajeto: a pé (pontilhado) ou transporte (com a cor oficial da linha).
struct TravelStep: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable { case walk, transit }
    struct Stop: Sendable, Hashable {
        var name: String
        var lat: Double?
        var lng: Double?
        var departs: Date?
        var arrives: Date?
    }

    var id: Int
    var kind: Kind
    var instruction: String?
    var minutes: Int
    var meters: Int
    // Transporte
    var lineName: String?
    var lineShort: String?
    /// "#b5b5ac" (cor oficial da linha, do Google).
    var colorHex: String?
    var textColorHex: String?
    var headsign: String?
    var vehicle: String?
    var agency: String?
    var from: Stop?
    var to: Stop?
    var stopCount: Int?
}

/// Uma das alternativas da tela Como chegar (metrô/trem, a pé, táxi estimado).
struct TravelOption: Sendable, Hashable, Identifiable {
    enum Mode: String, Sendable, Hashable { case transit, walk, taxi }
    enum Source: String, Sendable, Hashable { case routes, mapKit, estimate }

    var mode: Mode
    var source: Source
    var minutes: Int
    var meters: Int
    var departs: Date?
    var arrives: Date?
    var steps: [TravelStep] = []
    /// Tarifa (Routes `travelAdvisory.transitFare`) ou táxi estimado.
    var fare: Double?
    var fareCurrency: String?
    var transfers: Int = 0

    var id: Mode { mode }
}

/// Routes API (New): `computeRoutes` (TRANSIT, WALK, DRIVE) e `computeRouteMatrix` (WALK/TRANSIT, máx. 10×10).
enum GoogleRoutes {
    static let routesURL = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
    static let matrixURL = URL(string: "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix")!

    /// Campos mínimos do trajeto de transporte (passos, linha, paradas, horários, tarifa).
    static let transitMask = [
        "routes.duration", "routes.distanceMeters", "routes.legs.steps.travelMode", "routes.legs.steps.staticDuration",
        "routes.legs.steps.distanceMeters", "routes.legs.steps.navigationInstruction", "routes.legs.steps.transitDetails",
        "routes.legs.steps.localizedValues", "routes.travelAdvisory.transitFare",
    ].joined(separator: ",")
    static let walkMask = "routes.duration,routes.distanceMeters,routes.legs.steps.travelMode,routes.legs.steps.staticDuration,routes.legs.steps.navigationInstruction"
    static let driveMask = "routes.duration,routes.distanceMeters"

    // MARK: computeRoutes

    static func body(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: String, departAt: Date) -> [String: Any] {
        var body: [String: Any] = [
            "origin": ["location": ["latLng": ["latitude": from.latitude, "longitude": from.longitude]]],
            "destination": ["location": ["latLng": ["latitude": to.latitude, "longitude": to.longitude]]],
            "travelMode": mode,
            "languageCode": "pt-BR",
            "units": "METRIC",
        ]
        if mode == "TRANSIT" {
            // A tarifa volta sozinha em `travelAdvisory.transitFare` (não é extraComputation).
            body["departureTime"] = iso.string(from: departAt)
        }
        return body
    }

    /// TRANSIT com tarifa conta como Pro; o resto, Essentials (ver `ApiBudget`).
    static func routeCall(mode: String, fare: Bool) -> (sku: GoogleSKU, mask: String) {
        switch mode {
        case "TRANSIT": (fare ? .routesPro : .routesEssentials, transitMask)
        case "WALK": (.routesEssentials, walkMask)
        default: (.routesEssentials, driveMask)
        }
    }

    /// Uma alternativa de transporte (a primeira rota). Sem rota de transporte, `nil` (a tela mostra a pé e táxi).
    static func transit(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, departAt: Date, apiKey: String,
                        http: HTTP) async throws -> TravelOption? {
        let call = routeCall(mode: "TRANSIT", fare: true)
        let data = try await GoogleAPI.run(call.sku) {
            try await http.post(routesURL, json: body(from: from, to: to, mode: "TRANSIT", departAt: departAt),
                                headers: GoogleAPI.headers(key: apiKey, mask: call.mask), service: "routes.transit")
        }
        return try parseTransit(data)
    }

    /// Caminhada ou carro (ETA) pelo computeRoutes. `mode`: "WALK" ou "DRIVE".
    static func simple(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: String, apiKey: String, http: HTTP) async throws -> TravelOption? {
        let call = routeCall(mode: mode, fare: false)
        let data = try await GoogleAPI.run(call.sku) {
            try await http.post(routesURL, json: body(from: from, to: to, mode: mode, departAt: Date()),
                                headers: GoogleAPI.headers(key: apiKey, mask: call.mask), service: "routes.\(mode.lowercased())")
        }
        return try parseSimple(data, mode: mode == "WALK" ? .walk : .taxi)
    }

    // MARK: Parse (testado)

    /// Primeira rota: passos com linha/cor/paradas/horários e a tarifa (`travelAdvisory.transitFare`).
    static func parseTransit(_ data: Data) throws -> TravelOption? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("routes") }
        guard let route = (json["routes"] as? [[String: Any]])?.first else { return nil }
        var steps: [TravelStep] = []
        for leg in route["legs"] as? [[String: Any]] ?? [] {
            for raw in leg["steps"] as? [[String: Any]] ?? [] {
                if let step = parseStep(raw, id: steps.count) { steps.append(step) }
            }
        }
        let fare = (route["travelAdvisory"] as? [String: Any]).flatMap { $0["transitFare"] as? [String: Any] }
        let units = (fare?["units"] as? String).flatMap(Double.init) ?? (fare?["units"] as? Double) ?? 0
        let nanos = Double(fare?["nanos"] as? Int ?? 0) / 1_000_000_000
        let transitSteps = steps.filter { $0.kind == .transit }
        let start = transitSteps.first?.from?.departs ?? steps.first?.from?.departs
        let end = transitSteps.last?.to?.arrives ?? steps.last?.to?.arrives
        return TravelOption(mode: .transit, source: .routes, minutes: seconds(route["duration"]) / 60,
                            meters: route["distanceMeters"] as? Int ?? 0, departs: start, arrives: end, steps: steps,
                            fare: fare == nil ? nil : units + nanos, fareCurrency: fare?["currencyCode"] as? String,
                            transfers: max(0, transitSteps.count - 1))
    }

    static func parseSimple(_ data: Data, mode: TravelOption.Mode) throws -> TravelOption? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("routes") }
        guard let route = (json["routes"] as? [[String: Any]])?.first else { return nil }
        var steps: [TravelStep] = []
        for leg in route["legs"] as? [[String: Any]] ?? [] {
            for raw in leg["steps"] as? [[String: Any]] ?? [] {
                if let step = parseStep(raw, id: steps.count) { steps.append(step) }
            }
        }
        return TravelOption(mode: mode, source: .routes, minutes: max(1, seconds(route["duration"]) / 60),
                            meters: route["distanceMeters"] as? Int ?? 0, departs: nil, arrives: nil, steps: steps)
    }

    static func parseStep(_ raw: [String: Any], id: Int) -> TravelStep? {
        let instruction = (raw["navigationInstruction"] as? [String: Any])?["instructions"] as? String
        let minutes = max(1, seconds(raw["staticDuration"]) / 60)
        let meters = raw["distanceMeters"] as? Int ?? 0
        if raw["travelMode"] as? String == "TRANSIT", let details = raw["transitDetails"] as? [String: Any] {
            let line = details["transitLine"] as? [String: Any]
            let stops = details["stopDetails"] as? [String: Any]
            let vehicle = ((line?["vehicle"] as? [String: Any])?["name"] as? [String: Any])?["text"] as? String
            let agency = ((line?["agencies"] as? [[String: Any]])?.first)?["name"] as? String
            return TravelStep(id: id, kind: .transit, instruction: instruction, minutes: minutes, meters: meters,
                              lineName: line?["name"] as? String, lineShort: line?["nameShort"] as? String,
                              colorHex: line?["color"] as? String, textColorHex: line?["textColor"] as? String,
                              headsign: details["headsign"] as? String, vehicle: vehicle, agency: agency,
                              from: stop(stops?["departureStop"] as? [String: Any], departs: date(stops?["departureTime"])),
                              to: stop(stops?["arrivalStop"] as? [String: Any], arrives: date(stops?["arrivalTime"])),
                              stopCount: details["stopCount"] as? Int)
        }
        return TravelStep(id: id, kind: .walk, instruction: instruction, minutes: minutes, meters: meters)
    }

    private static func stop(_ raw: [String: Any]?, departs: Date? = nil, arrives: Date? = nil) -> TravelStep.Stop? {
        guard let raw, let name = raw["name"] as? String else { return nil }
        let latLng = ((raw["location"] as? [String: Any])?["latLng"] as? [String: Any])
        return TravelStep.Stop(name: name, lat: latLng?["latitude"] as? Double, lng: latLng?["longitude"] as? Double,
                               departs: departs, arrives: arrives)
    }

    /// "840s" → 840.
    static func seconds(_ any: Any?) -> Int {
        guard let text = any as? String else { return 0 }
        return Int(Double(text.replacingOccurrences(of: "s", with: "")) ?? 0)
    }

    static func date(_ any: Any?) -> Date? {
        guard let text = any as? String else { return nil }
        return iso.date(from: text) ?? isoPlain.date(from: text)
    }

    /// Formatadores novos a cada uso (ISO8601DateFormatter não é Sendable).
    static var iso: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    static var isoPlain: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    // MARK: Route Matrix (solver)

    /// Elementos (origem × destino) da matriz. Máx. 10 × 10 por pedido (ver `TravelMatrixLoader`).
    static func matrixBody(origins: [CLLocationCoordinate2D], destinations: [CLLocationCoordinate2D], mode: String, departAt: Date) -> [String: Any] {
        func waypoint(_ c: CLLocationCoordinate2D) -> [String: Any] {
            ["waypoint": ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]]
        }
        var body: [String: Any] = [
            "origins": origins.map(waypoint), "destinations": destinations.map(waypoint),
            "travelMode": mode, "languageCode": "pt-BR",
        ]
        if mode == "TRANSIT" { body["departureTime"] = iso.string(from: departAt) }
        return body
    }

    /// Uma célula da matriz: minutos e metros entre `origins[originIndex]` e `destinations[destinationIndex]`.
    struct MatrixCell: Sendable, Hashable {
        var originIndex: Int
        var destinationIndex: Int
        var minutes: Int
        var meters: Int
    }

    static func matrix(origins: [CLLocationCoordinate2D], destinations: [CLLocationCoordinate2D], mode: String, departAt: Date,
                       apiKey: String, http: HTTP) async throws -> [MatrixCell] {
        let units = origins.count * destinations.count
        let mask = "originIndex,destinationIndex,duration,distanceMeters,status,condition"
        let data = try await GoogleAPI.run(.routeMatrix, units: units) {
            try await http.post(matrixURL, json: matrixBody(origins: origins, destinations: destinations, mode: mode, departAt: departAt),
                                headers: GoogleAPI.headers(key: apiKey, mask: mask), service: "routes.matrix")
        }
        return try parseMatrix(data)
    }

    /// Array de elementos. Elemento com `status` (erro) fica de fora; o solver cai na estimativa pra ele.
    static func parseMatrix(_ data: Data) throws -> [MatrixCell] {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ServiceError.decoding("route matrix") }
        return items.compactMap { item in
            if let status = item["status"] as? [String: Any], !status.isEmpty { return nil }
            return MatrixCell(originIndex: item["originIndex"] as? Int ?? 0, destinationIndex: item["destinationIndex"] as? Int ?? 0,
                              minutes: max(1, seconds(item["duration"]) / 60), meters: item["distanceMeters"] as? Int ?? 0)
        }
    }
}

/// Táxi estimado (não há tarifa na Routes API). Constantes aproximadas, sempre mostradas como "estimado".
enum TaxiEstimate {
    /// Tóquio: ¥500 pelo 1,052 km e ¥80 a cada 255 m (≈ ¥314/km), sem adicional noturno.
    static func jpy(km: Double) -> Double {
        let extra = max(0, km - 1.052)
        return ((500 + extra * 80 / 0.255) / 10).rounded() * 10
    }

    /// BH: bandeirada e quilômetro rodado aproximados (R$ 6,00 + R$ 2,50/km).
    static func brl(km: Double) -> Double {
        ((6 + max(0, km) * 2.5) * 10).rounded() / 10
    }
}
