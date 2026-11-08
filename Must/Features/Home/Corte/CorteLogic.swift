import CoreLocation
import Foundation

// A capa do corte (prompt 30): a lógica pura (divisão board × fora, linhas, passo a passo, cutucão). Sem SwiftUI, sem rede.

// MARK: - Resultado em duas faixas (§4)

/// Uma linha do resultado, pronta pra tela.
struct CorteRow: Identifiable, Hashable, Sendable {
    enum Action: Hashable, Sendable {
        /// Dá hoje: abre a rota.
        case go
        /// Não dá hoje: "amanhã" (ou o dia em que abre).
        case later(String)
        /// Fora do board: guarda no board.
        case addToBoard
    }

    var row: QueroRow
    var id: String { row.id }
    var isBoard: Bool { row.result.origin == .board }
    var meters: Double
    /// Número grande da distância ("2,1", "850") e a unidade ("km", "m").
    var distance: (value: String, unit: String)
    /// "9 min · trem".
    var travel: String
    var reason: String
    var action: Action

    static func == (a: CorteRow, b: CorteRow) -> Bool { a.id == b.id && a.action == b.action && a.reason == b.reason }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// As duas faixas: laranja = seus Musts da cidade de hoje, **a qualquer distância**; tinta = o que não está no board, perto.
@MainActor
enum CorteSplit {
    /// "Aqui perto": até 2 km do ponto de partida (o mesmo "perto" do Quero…).
    static let nearMeters: Double = 2_000
    static let maxOutside = 6

    struct Result: Sendable {
        var board: [CorteRow]
        var outside: [CorteRow]
    }

    /// `rows` vêm do `QueroModel` (board da cidade de hoje + Google + lojas de marca). O board nunca é cortado por distância;
    /// fora do board só entra o que está perto. Ordem do board: dá hoje › tempo pra chegar.
    static func split(_ rows: [QueroRow], origin: CLLocationCoordinate2D, region: Region, walkMaxKm: Double,
                      near: Double = nearMeters, now: Date = AppClock.now) -> Result {
        let o = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        func meters(_ r: QueroRow) -> Double { CLLocation(latitude: r.result.lat, longitude: r.result.lng).distance(from: o) }

        let board = rows.filter { $0.result.origin == .board }
            .sorted { a, b in
                let fa = a.slot != nil, fb = b.slot != nil
                if fa != fb { return fa }
                return (a.minutes, a.id) < (b.minutes, b.id)
            }
            .map { line($0, meters: meters($0), origin: origin, region: region, walkMaxKm: walkMaxKm, now: now) }
        let outside = rows.filter { $0.result.origin != .board && meters($0) <= near }
            .sorted { (meters($0), $0.id) < (meters($1), $1.id) }
            .prefix(maxOutside)
            .map { line($0, meters: meters($0), origin: origin, region: region, walkMaxKm: walkMaxKm, now: now) }
        return Result(board: board, outside: Array(outside))
    }

    static func line(_ r: QueroRow, meters: Double, origin: CLLocationCoordinate2D, region: Region, walkMaxKm: Double,
                     now: Date = AppClock.now) -> CorteRow {
        let leg = DaySolver.leg(origin, r.result.coordinate, walkMax: walkMaxKm)
        let mode = leg.mode == .walk ? "a pé" : transit(region)
        let isBoard = r.result.origin == .board
        let action: CorteRow.Action = !isBoard ? .addToBoard : (r.slot != nil ? .go : .later(laterLabel(r)))
        return CorteRow(row: r, meters: meters, distance: distanceParts(meters), travel: "\(max(1, r.minutes)) min · \(mode)",
                        reason: reason(r, isBoard: isBoard, now: now, region: region), action: action)
    }

    /// "850" + "m", "2,1" + "km". Número grande em cima, unidade embaixo.
    static func distanceParts(_ meters: Double) -> (value: String, unit: String) {
        let text = Walk.distanceText(meters)
        guard text != "aqui" else { return ("0", "m") }
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : (text, "")
    }

    static func transit(_ region: Region) -> String { region.rawValue == "jp" ? "trem" : "metrô" }

    /// Sempre com motivo, e só afirma "aberto" com horário confirmado (o board só traz `until` quando o Google deu o horário):
    /// "do seu board · aberto até 19h" / "do seu board · horário não confirmado" /
    /// "a 26 min e fecha 17h" / "fecha 15h · não cabe no dia" / "dia cheio · horário não confirmado".
    static func reason(_ r: QueroRow, isBoard: Bool, now: Date? = nil, region: Region? = nil) -> String {
        if isBoard {
            if r.slot != nil {
                return ["do seu board", r.result.until.map { "aberto até \($0)" } ?? PlaceTrust.hoursUnconfirmed].joined(separator: " · ")
            }
            guard let until = r.result.until else { return "dia cheio · \(PlaceTrust.hoursUnconfirmed)" }
            if let now, let region, let close = QueroModel.closing(until, on: now, region: region),
               now.addingTimeInterval(Double(max(1, r.minutes) + DayFit.minutes) * 60) > close {
                return "a \(max(1, r.minutes)) min e fecha \(until)"
            }
            return "fecha \(until) · não cabe no dia"
        }
        let kind = r.result.note ?? QueroModel.typeLabel(r.result)
        return [kind, r.result.until.map { "até \($0)" } ?? "aberto"].compactMap { $0 }.joined(separator: " · ")
    }

    /// O dia em que abre ("sáb") ou "amanhã".
    static func laterLabel(_ r: QueroRow) -> String {
        guard let other = r.otherDay, other.contains(" · ") else { return "amanhã" }
        return other.components(separatedBy: " · ").first ?? "amanhã"
    }
}

// MARK: - Vazio com motivo (prompt 31 · 2)

/// O resultado nunca volta vazio à toa: diz por quê e oferece "ampliar pra 5 km" / "outro bairro".
@MainActor
enum CorteEmpty {
    static let widenedMeters: Double = 5_000

    struct Total: Equatable, Sendable {
        var headline: String
        var reason: String
        var canWiden: Bool
    }

    /// A linha da faixa tinta quando ela não tem nada: o motivo certo (sem internet, sem chave, cota…), ou `nil` se a busca foi
    /// normal e só não achou nada aberto.
    static func outsideLine(offline: Bool, note: String?) -> String? {
        if offline { return "sem internet · só seus Musts" }
        return note.map { "\($0) · só seus Musts" }
    }

    /// As duas faixas vazias: a frase, o porquê e se dá pra ampliar.
    static func total(query: String, areaName: String, offline: Bool, note: String?, radiusMeters: Double?) -> Total {
        let radius = radiusMeters ?? CorteSplit.nearMeters
        let km = radius >= 1_000 ? "\(Int((radius / 1_000).rounded())) km" : "\(Int(radius)) m"
        let headline = "nada de \(query) por aqui"
        if let line = outsideLine(offline: offline, note: note) {
            return Total(headline: headline, reason: "\(line), e nenhum \(query) seu nesta cidade.", canWiden: false)
        }
        return Total(headline: headline, reason: "Nada aberto em até \(km) de \(areaName), e nenhum \(query) seu nesta cidade.",
                     canWiden: radius < widenedMeters)
    }

    /// Os bairros mais perto do ponto de partida, da mesma cidade, sem o atual.
    static func nearbyAreas(_ areas: [Area], from point: CLLocationCoordinate2D, cityGroup: String, excluding name: String, limit: Int = 6) -> [Area] {
        areas.filter { AreaCatalog.cityGroup(forCityId: $0.cityId) == cityGroup && $0.name != name }
            .sorted { DaySolver.streetKm(point, $0.centroid.clCoordinate) < DaySolver.streetKm(point, $1.centroid.clCoordinate) }
            .prefix(limit).map { $0 }
    }
}

// MARK: - Abertos a 10 min (o numeral da capa)

enum CorteCount {
    /// Quantas coisas abertas a 10 min a pé: seus Musts abertos + o que o cache de "por perto" diz que está aberto.
    static func openWithin10(places: [SuggestPlace], indicated: [NearbyPlace], here: CLLocationCoordinate2D) -> Int {
        counts(places: places, indicated: indicated, here: here).open
    }

    /// `open` = aberto com horário confirmado (Google); `unconfirmed` = Musts perto sem horário confirmado: não dá pra
    /// afirmar que estão abertos, então não entram no numeral.
    static func counts(places: [SuggestPlace], indicated: [NearbyPlace], here: CLLocationCoordinate2D) -> (open: Int, unconfirmed: Int) {
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let reach = 10 * Walk.metersPerMinute
        func near(_ lat: Double, _ lng: Double) -> Bool {
            CLLocation(latitude: lat, longitude: lng).distance(from: origin) * SuggestionEngine.streetFactor <= reach
        }
        let board = places.filter { !$0.done && $0.kind != .photo && $0.state.isOpen && near($0.lat, $0.lng) }
        let boardNames = Set(board.map { $0.name.lowercased() })
        let outside = indicated.filter { $0.openNow == true && near($0.lat, $0.lng) && !boardNames.contains($0.name.lowercased()) }
        let unknown = places.filter { !$0.done && $0.kind != .photo && $0.state == .unknown && near($0.lat, $0.lng) }.count
        return (board.count + outside.count, unknown)
    }
}

// MARK: - Em cartaz na capa

/// A linha "Em cartaz" do índice da capa (faixa tinta: é de fora do board). Aparece só com evento hoje; a hora grande é a da
/// próxima sessão (ou "hoje" quando é exposição em temporada). Puro: o `body` só desenha.
struct CorteShowLine: Equatable, Sendable {
    static let rowId = "emcartaz"
    var big: String
    var unit: String
    var title: String
    var reason: String
    /// Acontecendo (ou começando em até 10 min) a até 10 min a pé: entra no numeral da capa.
    var countsNearby: Bool

    /// `coordinates` = onde cada evento acontece (`ShowEvent.lat/lng` ou o lugar do board), por id do evento.
    static func make(events: [ShowEvent], now: Date, region: Region, here: CLLocationCoordinate2D,
                     coordinates: [String: CLLocationCoordinate2D] = [:]) -> CorteShowLine? {
        let cal = region.calendar
        let today = events.filter { EventsMapping.isOn($0, day: now, calendar: cal) || EmCartazModel.happensToday($0, now: now, calendar: cal) }
        guard !today.isEmpty else { return nil }
        // Primeiro o que tem hora (a mais próxima), depois as exposições em temporada.
        let timed = today.compactMap { e in EmCartazModel.nextDate(e, now: now).map { (e, $0) } }.sorted { $0.1 < $1.1 }
        let first = timed.first?.0 ?? today[0]
        let when = timed.first?.1
        let big = when.map { region.timeString($0) } ?? "hoje"
        let n = today.count
        let reason = "em cartaz · \(n) hoje"
        // Conta no numeral: tem hora entre -90 min e +10 min e está a até 10 min a pé.
        var counts = false
        if let when, when <= now.addingTimeInterval(10 * 60), when >= now.addingTimeInterval(-90 * 60) {
            if let c = coordinates[first.id] ?? first.lat.flatMap({ lat in first.lng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }) {
                let d = CLLocation(latitude: c.latitude, longitude: c.longitude)
                    .distance(from: CLLocation(latitude: here.latitude, longitude: here.longitude)) * SuggestionEngine.streetFactor
                counts = d <= 10 * Walk.metersPerMinute
            }
        }
        return CorteShowLine(big: big, unit: when == nil ? "em cartaz" : "hoje", title: first.title, reason: reason, countsNearby: counts)
    }
}

// MARK: - Vontades de agora (chips)

/// Os chips da fenda: o texto que vai pro Quero… e, quando existe, o verbo (`WantVerb`).
struct CorteWish: Identifiable, Hashable, Sendable {
    var label: String
    var text: String
    var verb: WantVerb?
    var id: String { label }

    static let all: [CorteWish] = [
        CorteWish(label: "café", text: "café", verb: nil),
        CorteWish(label: "comer já", text: "comer", verb: .comer),
        CorteWish(label: "beber", text: "beber", verb: .beber),
        CorteWish(label: "sentar 1 h", text: "lugar pra sentar", verb: nil),
        CorteWish(label: "fugir da chuva", text: "fugir da chuva", verb: nil),
        CorteWish(label: "barato", text: "comer barato", verb: nil),
        CorteWish(label: "pra 4", text: "restaurante pra 4", verb: nil),
        CorteWish(label: "ver", text: "ver", verb: .ver),
        CorteWish(label: "comprar", text: "comprar", verb: .comprar),
        CorteWish(label: "ouvir", text: "ouvir", verb: nil),
        CorteWish(label: "noite", text: "noite", verb: nil),
        CorteWish(label: "foto", text: "foto", verb: nil),
        CorteWish(label: "arte", text: "arte", verb: .ver),
        CorteWish(label: "fazer", text: "fazer", verb: .fazer),
    ]
}
