import CoreLocation
import Foundation

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
