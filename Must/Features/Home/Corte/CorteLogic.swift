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
                      near: Double = nearMeters) -> Result {
        let o = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        func meters(_ r: QueroRow) -> Double { CLLocation(latitude: r.result.lat, longitude: r.result.lng).distance(from: o) }

        let board = rows.filter { $0.result.origin == .board }
            .sorted { a, b in
                let fa = a.slot != nil, fb = b.slot != nil
                if fa != fb { return fa }
                return (a.minutes, a.id) < (b.minutes, b.id)
            }
            .map { line($0, meters: meters($0), origin: origin, region: region, walkMaxKm: walkMaxKm) }
        let outside = rows.filter { $0.result.origin != .board && meters($0) <= near }
            .sorted { (meters($0), $0.id) < (meters($1), $1.id) }
            .prefix(maxOutside)
            .map { line($0, meters: meters($0), origin: origin, region: region, walkMaxKm: walkMaxKm) }
        return Result(board: board, outside: Array(outside))
    }

    static func line(_ r: QueroRow, meters: Double, origin: CLLocationCoordinate2D, region: Region, walkMaxKm: Double) -> CorteRow {
        let leg = DaySolver.leg(origin, r.result.coordinate, walkMax: walkMaxKm)
        let mode = leg.mode == .walk ? "a pé" : transit(region)
        let isBoard = r.result.origin == .board
        let action: CorteRow.Action = !isBoard ? .addToBoard : (r.slot != nil ? .go : .later(laterLabel(r)))
        return CorteRow(row: r, meters: meters, distance: distanceParts(meters), travel: "\(max(1, r.minutes)) min · \(mode)",
                        reason: reason(r, isBoard: isBoard), action: action)
    }

    /// "850" + "m", "2,1" + "km". Número grande em cima, unidade embaixo.
    static func distanceParts(_ meters: Double) -> (value: String, unit: String) {
        let text = Walk.distanceText(meters)
        guard text != "aqui" else { return ("0", "m") }
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : (text, "")
    }

    static func transit(_ region: Region) -> String { region.rawValue == "jp" ? "trem" : "metrô" }

    /// "do seu board · aberto até 19h" / "fecha 20h · não dá" / "casa de café · aberto".
    static func reason(_ r: QueroRow, isBoard: Bool) -> String {
        if isBoard {
            if r.slot != nil { return ["do seu board", r.result.until.map { "aberto até \($0)" }].compactMap { $0 }.joined(separator: " · ") }
            return r.result.until.map { "fecha \($0) · não dá" } ?? "não dá hoje"
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

// MARK: - Abertos a 10 min (o numeral da capa)

enum CorteCount {
    /// Quantas coisas abertas a 10 min a pé: seus Musts abertos + o que o cache de "por perto" diz que está aberto.
    static func openWithin10(places: [SuggestPlace], indicated: [NearbyPlace], here: CLLocationCoordinate2D) -> Int {
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let reach = 10 * Walk.metersPerMinute
        func near(_ lat: Double, _ lng: Double) -> Bool {
            CLLocation(latitude: lat, longitude: lng).distance(from: origin) * SuggestionEngine.streetFactor <= reach
        }
        let board = places.filter { !$0.done && $0.kind != .photo && $0.state.isOpen && near($0.lat, $0.lng) }
        let boardNames = Set(board.map { $0.name.lowercased() })
        let outside = indicated.filter { $0.openNow == true && near($0.lat, $0.lng) && !boardNames.contains($0.name.lowercased()) }
        return board.count + outside.count
    }
}

// MARK: - Passo a passo (§5)

/// O passo a passo da capa: na primeira vez e na primeira entrada em cada viagem. Só avança com o gesto de verdade.
enum CorteWalk {
    enum Step: Int, Sendable { case pull = 1, write = 2, done = 3 }
    enum Event: Sendable { case pulledOpen, gotResult, skip }

    /// Primeira vez (nenhuma viagem apresentada) ou viagem ainda não apresentada.
    static func shouldPresent(tripId: String, seen: Set<String>) -> Bool { !seen.contains(tripId) }

    static func next(_ step: Step, _ event: Event) -> Step? {
        switch (step, event) {
        case (_, .skip): nil
        case (.pull, .pulledOpen): .write
        case (.write, .gotResult): .done
        default: step
        }
    }
}

// MARK: - Cutucão e contador de puxadas

/// Quantas puxadas com resultado (o texto encurta e o cutucão para depois de 3).
struct CutCoach: Equatable, Sendable {
    var uses: Int

    /// Parado ~5 s na capa, a régua desce ~22 pt e volta.
    static let idleSeconds: Double = 5
    static let nudgeDistance: CGFloat = 22

    var isShort: Bool { uses >= CutPull.usesBeforeShort }
    var nudges: Bool { !isShort }

    mutating func recordResult() { uses += 1 }
}

/// O que o corte lembra entre aberturas: viagens já apresentadas e quantas puxadas deram resultado.
struct CortePrefs {
    private let defaults: UserDefaults
    static let seenKey = "corte.walkSeenTrips"
    static let usesKey = "corte.pullUses"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var seenTrips: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.seenKey) }
    }

    func markPresented(_ tripId: String) { seenTrips.insert(tripId) }

    var coach: CutCoach {
        get { CutCoach(uses: defaults.integer(forKey: Self.usesKey)) }
        nonmutating set { defaults.set(newValue.uses, forKey: Self.usesKey) }
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
    ]
}
