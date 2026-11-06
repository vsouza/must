import CoreLocation
import Foundation

/// Do dia do solver (âncoras + Musts) ao `DayPlan` v8: micro-paradas geradas nos buracos, deslocamentos como itens,
/// último trem e título. Puro e determinístico (mesma entrada → mesmo dia); sem SwiftData, rede nem GPS.
/// Micro-paradas só ocupam buracos que já existem: ligar/desligar não mexe em nenhuma outra parada.
enum DayComposer {
    /// Parada do board já com hora (do solver ou do dia aceito).
    struct BoardStop: Sendable, Hashable {
        var place: SolverPlace
        var start: Date
        var end: Date
        var isAnchor: Bool
        /// Motivo do solver ("reserva", "ingresso", "domingo sem carros", "golden", "fila ~20 min").
        var reason: String
        var isException: Bool = false
        var done: Bool = false
    }

    struct Input: Sendable {
        /// Meia-noite do dia, no fuso da região.
        var date: Date
        var region: Region
        var stops: [BoardStop]
        /// Onde dorme (bairro do `TripInfo.home`, senão o centro da cidade): café da manhã e descanso.
        var hotel: CLLocationCoordinate2D
        var pace: Pace = .normal
        var includes: Set<DayInclude> = [.micro, .goldenPhoto]
        /// Andar máximo a pé já com o nível do dia.
        var walkMaxKm: Double = 1.5
        /// Tempos reais (Routes), se já estão no aparelho. `nil` = estimativa.
        var travel: TravelMatrix? = nil
        var lastTrain: DayLastTrain? = nil
        var dayNumber: Int? = nil
        var budget: Double
        var spent: Double = 0
        /// Bairro pedido no Montar (vale como `DayPlan.area`).
        var focusArea: String? = nil
        /// Nome da cidade, se nenhum bairro aparecer ("Belo Horizonte").
        var cityName: String? = nil
        /// Board inteiro: de onde saem os nomes das micro-paradas (café perto do hotel, loja no caminho).
        var catalog: [SolverPlace] = []
    }

    // MARK: Montagem

    static func compose(_ input: Input) -> DayPlan {
        let areas = AreaCatalog.areas(for: input.region)
        let assigner = AreaAssigner(areas: areas)
        let sun = SunService.day(input.date.addingTimeInterval(12 * 3600), input.hotel, timeZone: input.region.timeZone)
        var stops: [DayStop] = []
        var used: Set<String> = []
        for board in input.stops.sorted(by: { ($0.start, $0.place.id) < ($1.start, $1.place.id) }) {
            var stop = boardStop(board, input: input, sun: sun, assigner: assigner)
            if !used.insert(stop.id).inserted { stop.id += "-\(Int(board.start.timeIntervalSince1970 / 60))" }
            used.insert(stop.id)
            stops.append(stop)
        }
        if input.includes.contains(.micro) {
            stops = MicroStops.insert(into: stops, input: input, sun: sun, assigner: assigner)
        }
        let legs = legs(for: stops, region: input.region, walkMaxKm: input.walkMaxKm, travel: input.travel, areas: areas)
        let main = mainAreas(stops, areas: areas)
        let title = main.isEmpty ? (input.cityName ?? input.region.displayName) : main.prefix(2).map(\.name).joined(separator: " + ")
        return DayPlan(date: input.date, title: title, dayNumber: input.dayNumber, area: input.focusArea ?? main.first?.id,
                       stops: stops, legs: legs, lastTrain: input.lastTrain, pace: input.pace, budget: input.budget, spent: input.spent,
                       includes: input.includes)
    }

    /// Tira uma parada (micro-parada que o usuário dispensou) e religa só as pernas vizinhas. Âncora não sai.
    static func removing(_ stopId: String, from plan: DayPlan, region: Region, walkMaxKm: Double = 1.5) -> DayPlan {
        guard let stop = plan.stops.first(where: { $0.id == stopId }), stop.kind != .anchor else { return plan }
        var out = plan
        out.stops.removeAll { $0.id == stopId }
        out.legs = legs(for: out.stops, region: region, walkMaxKm: walkMaxKm, travel: nil, areas: AreaCatalog.areas(for: region))
        // Pernas que não mudaram guardam o que tinham (tempo real do Routes).
        out.legs = out.legs.map { leg in plan.legs.first { $0.from == leg.from && $0.to == leg.to } ?? leg }
        return out
    }

    /// Só o board (micro-paradas fora), com as pernas religadas.
    static func withoutMicros(_ plan: DayPlan, region: Region, walkMaxKm: Double = 1.5) -> DayPlan {
        plan.stops.filter { $0.kind == .micro }.reduce(plan) { removing($1.id, from: $0, region: region, walkMaxKm: walkMaxKm) }
    }

    // MARK: Paradas do board

    static func isGolden(_ board: BoardStop, sun: SunDay) -> Bool {
        guard board.place.role == .photo else { return false }
        return [sun.goldenAM, sun.goldenPM].compactMap { $0 }.contains { window in
            board.start >= window.start.addingTimeInterval(-5 * 60) && board.start < window.end
        }
    }

    static func anchorReason(_ board: BoardStop, sun: SunDay) -> DayAnchorReason? {
        if board.isAnchor {
            if board.reason.hasPrefix("ingresso") { return .ticket }
            if board.reason.hasPrefix("domingo") { return .sunday }
            return .reservation
        }
        return isGolden(board, sun: sun) ? .golden : nil
    }

    private static func boardStop(_ board: BoardStop, input: Input, sun: SunDay, assigner: AreaAssigner) -> DayStop {
        let p = board.place
        let region = input.region
        let anchor = anchorReason(board, sun: sun)
        var parts: [String] = []
        var tag: String?
        switch anchor {
        case .reservation:
            tag = "RES"
            var head = "reserva"
            if let party = p.reservation?.party, party > 1 { head += " · \(party) pessoas" }
            parts.append(head)
            if board.reason.contains("turno") {
                parts.append("turno \(region.timeString(board.start))–\(region.timeString(board.end))")
                parts.append("chegue \(region.timeString(board.start.addingTimeInterval(-30 * 60)))")
            }
        case .ticket:
            tag = "QR"
            parts.append("ingresso · \(durationText(board.end.timeIntervalSince(board.start)))")
        case .sunday:
            tag = "DOM"
            parts.append("Must \(word(p)) · domingo sem carros")
        case .golden:
            tag = "SOL"
            parts.append("Must photo · golden")
        case .train:
            tag = "JR"
        case nil:
            parts.append("Must \(word(p))")
        }
        if let q = p.queueMinutes, q > 0, anchor != .reservation, anchor != .ticket { parts.append("fila ~\(q) min") }
        if p.cost > 0 { parts.append(region.money(p.cost)) }
        if board.isException { parts.append("fora da meta") }
        if board.done { parts.append("feito") }
        let opensAt = p.hours.flatMap { hours in
            hours.openings(on: input.date, timeZone: region.timeZone).last { $0 <= board.start }
        }
        return DayStop(id: "p-\(p.id)", placeId: p.id, kind: anchor == nil ? .must : .anchor, start: board.start, end: board.end,
                       label: anchor == .golden ? "\(p.name) · golden" : p.name, note: parts.joined(separator: " · "), tag: tag,
                       area: assigner.areaId(name: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng),
                       cost: p.cost > 0 ? p.cost : nil, done: board.done, anchor: anchor, queueMinutes: p.queueMinutes,
                       opensAt: opensAt, lat: p.lat, lng: p.lng, isException: board.isException)
    }

    /// "eat", "drink", "art", "photo", "do"… (o "Must ___" da Linha).
    static func word(_ p: SolverPlace) -> String {
        switch p.kind {
        case .art: return "art"
        case .photo: return "photo"
        case .sport: return "sport"
        case .experience: return "do"
        case .place:
            switch p.listColor {
            case .eat: return "eat"
            case .drink, .coffee: return "drink"
            case .see, .temple: return "see"
            case .art: return "art"
            case .listen: return "listen"
            case .night: return "do"
            case .shop: return "shop"
            case .photo: return "photo"
            case .sport: return "sport"
            }
        }
    }

    /// "2 h", "1 h 30", "45 min".
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    // MARK: Deslocamentos

    static func coordinate(_ stop: DayStop) -> CLLocationCoordinate2D? {
        guard let lat = stop.lat, let lng = stop.lng, lat != 0 || lng != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Abaixo disso é "do lado": sem linha de deslocamento.
    static let sameSpotKm = 0.15

    /// Minutos entre dois pontos como o solver estima (0 = do lado).
    static func minutes(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?, walkMaxKm: Double, travel: TravelMatrix?) -> Int {
        guard let a, let b, DaySolver.streetKm(a, b) >= sameSpotKm else { return 0 }
        return DaySolver.leg(a, b, walkMax: walkMaxKm, matrix: travel).minutes
    }

    static func legs(for stops: [DayStop], region: Region, walkMaxKm: Double, travel: TravelMatrix?, areas: [Area]) -> [DayLeg] {
        let byId = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let assigner = AreaAssigner(areas: areas)
        func areaId(_ s: DayStop, _ c: CLLocationCoordinate2D) -> String? {
            s.area ?? assigner.areaId(name: nil, cityId: areas.first?.cityId ?? region.rawValue, lat: c.latitude, lng: c.longitude)
        }
        var out: [DayLeg] = []
        for (a, b) in zip(stops, stops.dropFirst()) {
            guard let ca = coordinate(a), let cb = coordinate(b) else { continue }
            let km = DaySolver.streetKm(ca, cb)
            guard km >= sameSpotKm else { continue }
            let leg = DaySolver.leg(ca, cb, walkMax: walkMaxKm, matrix: travel)
            let live = travel?.leg(ca, cb, km: km, walkMaxKm: walkMaxKm) != nil
            let (mode, detail) = describe(leg, region: region, from: areaId(a, ca).flatMap { byId[$0] }, to: areaId(b, cb).flatMap { byId[$0] })
            out.append(DayLeg(mode: mode, minutes: leg.minutes, from: a.id, to: b.id, detail: detail, departAt: nil, live: live))
        }
        return out
    }

    /// Modo e texto da perna: a pé; linha da tabela de bairros quando os dois lados se ligam; senão o modo da região.
    static func describe(_ leg: Leg, region: Region, from: Area?, to: Area?) -> (DayLegMode, String) {
        let m = leg.minutes
        if leg.mode == .walk { return (.walk, "a pé \(m) min") }
        if let from, let to, from.id != to.id {
            let hop = from.neighbors.first { $0.areaId == to.id } ?? to.neighbors.first { $0.areaId == from.id }
            if let hop, hop.mode != .walk {
                let mode: DayLegMode
                switch (hop.mode, region) {
                case (.bus, _): mode = .bus
                // JR é trem; Tokyo Metro/Toei, metrô (`transit.trainLinePrefix` do país).
                case (_, _) where region.profile.transit?.trainLinePrefix != nil:
                    mode = hop.line?.code.hasPrefix(region.profile.transit?.trainLinePrefix ?? "") == true ? .train : .metro
                default: mode = .metro
                }
                let what = hop.line.map { "\($0.code) \($0.name.replacingOccurrences(of: "JR ", with: ""))" } ?? hop.mode.label
                return (mode, "\(what) · \(from.name) → \(to.name) · \(m) min")
            }
            if leg.km > 25 { return (.train, "trem regional · \(from.name) → \(to.name) · \(m) min") }
        }
        if leg.km > 25 { return (.train, "trem regional · \(m) min") }
        // Sem tabela: o modo e o rótulo do país ("trem ou metrô", "metrô ou bus", "app ou táxi").
        let transit = region.profile.transit
        let mode = transit?.legMode.flatMap(DayLegMode.init(rawValue:)) ?? .taxi
        return (mode, "\(transit?.legLabel ?? "app ou táxi") · \(m) min")
    }

    // MARK: Título

    /// Bairros do dia (só paradas do board), por número de paradas e depois por ordem de aparição.
    static func mainAreas(_ stops: [DayStop], areas: [Area]) -> [Area] {
        var count: [String: Int] = [:]
        var order: [String] = []
        for stop in stops where stop.kind != .micro {
            guard let id = stop.area else { continue }
            if count[id] == nil { order.append(id) }
            count[id, default: 0] += 1
        }
        let ranked = order.enumerated().sorted { (count[$0.element]!, -$0.offset) > (count[$1.element]!, -$1.offset) }.map(\.element)
        return ranked.compactMap { id in areas.first { $0.id == id } }
    }

    // MARK: Último trem

    /// "00:12" no dia (de madrugada = dia seguinte).
    static func clock(_ hhmm: String, on date: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let day = parts[0] < 5 ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// Roma (Bolso IT): metrô até 23:30, sexta e sábado até 01:30.
    static func romeLastMetro(on date: Date, calendar: Calendar) -> DayLastTrain? {
        let weekday = calendar.component(.weekday, from: date) - 1
        let late = weekday == 5 || weekday == 6
        return clock(late ? "01:30" : "23:30", on: date, calendar: calendar).map { DayLastTrain(line: "Metrô A/B", at: $0) }
    }
}
