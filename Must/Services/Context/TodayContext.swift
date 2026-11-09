import CoreLocation
import Foundation
import Observation

/// Contexto estável de Hoje (prompt 32 §3, 09/11/2026): o bairro não pula no metrô.
///
/// Ordem: bairro **escolhido à mão** (vale até o fim do dia ou até trocar) › bairro da **parada corrente/próxima**
/// do dia › último bairro **confirmado** › hotel/cidade do dia. O GPS nunca troca o título sozinho: ele só **propõe**
/// ("Você chegou em Nakano · ver perto") com precisão < 100 m, parado (< 1,5 m/s) por ≥ 2 min e bairro diferente do
/// mostrado; ✕ dispensa por 1 h. GPS fora da cidade da viagem nunca vira contexto. No Explorar o contexto é o centro do
/// mapa (não passa por aqui).
enum ContextSource: String, Codable, Sendable {
    case manual, dayStop, confirmed, base
}

struct TodayContext: Equatable, Sendable {
    /// `nil` quando o contexto é a cidade (sem bairro).
    var areaId: String?
    /// O que o cabeçalho mostra: "Shinjuku" ou "Tóquio".
    var name: String
    var source: ContextSource
}

/// Bairro escolhido à mão no cabeçalho de Hoje.
struct ManualContext: Codable, Equatable, Sendable {
    var areaId: String
    var name: String
    var chosenAt: Date
}

struct ContextInputs: Sendable {
    var manual: ManualContext?
    /// Bairro da parada corrente ou da próxima do dia aceito.
    var dayStop: Area?
    /// Último bairro confirmado (tocou na proposta do GPS ou escolheu à mão em outro dia).
    var lastConfirmed: Area?
    /// Hotel do dia (bairro) ou, sem hotel, a cidade do dia.
    var baseAreaId: String?
    var baseName: String
    var now: Date
    var calendar: Calendar
}

enum ContextRule {
    /// Escolhido à mão só vale no mesmo dia (no calendário da região).
    static func manualIsValid(_ manual: ManualContext, now: Date, calendar: Calendar) -> Bool {
        calendar.isDate(manual.chosenAt, inSameDayAs: now)
    }

    static func resolve(_ i: ContextInputs) -> TodayContext {
        if let m = i.manual, manualIsValid(m, now: i.now, calendar: i.calendar) {
            return TodayContext(areaId: m.areaId, name: m.name, source: .manual)
        }
        if let stop = i.dayStop { return TodayContext(areaId: stop.id, name: stop.name, source: .dayStop) }
        if let last = i.lastConfirmed { return TodayContext(areaId: last.id, name: last.name, source: .confirmed) }
        return TodayContext(areaId: i.baseAreaId, name: i.baseName, source: .base)
    }
}

/// Uma leitura do GPS, já reduzida ao que a regra usa (testável sem `CLLocation`).
struct LocationFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Metros; negativo = inválido.
    var horizontalAccuracy: Double
    /// m/s; negativo = desconhecido.
    var speed: Double
    var timestamp: Date

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double, speed: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.timestamp = timestamp
    }

    init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  horizontalAccuracy: location.horizontalAccuracy, speed: location.speed, timestamp: location.timestamp)
    }
}

/// Quando o GPS pode propor "Você chegou em X". **Agente C implementa** (com `ContextRuleTests`); o contrato é:
/// `feed` recebe cada leitura com o bairro dela (já resolvido fora do main) e devolve o id proposto ou `nil`.
struct ArrivalProposer: Sendable {
    static let maxAccuracy: Double = 100
    static let maxSpeed: Double = 1.5
    static let dwell: TimeInterval = 120
    static let dismissFor: TimeInterval = 3600

    /// Bairros dispensados (✕) e até quando.
    var dismissed: [String: Date] = [:]

    init() {}

    /// - Parameters:
    ///   - areaId: bairro da leitura (`nil` = fora de qualquer bairro conhecido).
    ///   - shownAreaId: bairro que Hoje está mostrando.
    ///   - insideTripCity: a leitura está na cidade da viagem de hoje.
    mutating func feed(_ fix: LocationFix, areaId: String?, shownAreaId: String?, insideTripCity: Bool) -> String? {
        nil // stub do contrato r32/0
    }

    mutating func dismiss(_ areaId: String, now: Date) {
        dismissed[areaId] = now.addingTimeInterval(Self.dismissFor)
    }
}

/// Persistência do escolhido à mão e do último confirmado, por viagem (UserDefaults do App Group).
struct ContextMemory {
    var tripId: String
    var defaults: UserDefaults

    init(tripId: String, defaults: UserDefaults = UserDefaults(suiteName: "group.dev.viniso.must") ?? .standard) {
        self.tripId = tripId
        self.defaults = defaults
    }

    private var manualKey: String { "ctx.manual.\(tripId)" }
    private var confirmedKey: String { "ctx.confirmed.\(tripId)" }

    var manual: ManualContext? {
        get { defaults.data(forKey: manualKey).flatMap { try? JSONDecoder().decode(ManualContext.self, from: $0) } }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: manualKey) }
            else { defaults.removeObject(forKey: manualKey) }
        }
    }

    var lastConfirmedAreaId: String? {
        get { defaults.string(forKey: confirmedKey) }
        nonmutating set { defaults.set(newValue, forKey: confirmedKey) }
    }
}

/// O contexto de Hoje vivo (no environment, criado na `RootView`). Hoje chama `update` nos gatilhos (relógio, plano,
/// região) e `feed` a cada leitura nova do GPS; o cabeçalho mostra `context.name` e a faixa `proposal`.
@MainActor @Observable
final class TodayContextModel {
    private(set) var context = TodayContext(areaId: nil, name: "", source: .base)
    /// Bairro proposto pelo GPS ("Você chegou em X · ver perto"); `nil` = nenhuma faixa.
    private(set) var proposal: Area?

    private var memory: ContextMemory?
    private var proposer = ArrivalProposer()
    private var lastInputs: ContextInputs?
    private var areas: [Area] = []

    init() {}

    /// Recalcula com o que o dia diz agora. `areas` = catálogo da região (pra achar o último confirmado).
    func update(tripId: String, areas: [Area], dayStop: Area?, baseAreaId: String?, baseName: String, now: Date, calendar: Calendar) {
        if memory?.tripId != tripId { memory = ContextMemory(tripId: tripId) }
        self.areas = areas
        let confirmed = memory?.lastConfirmedAreaId.flatMap { id in areas.first { $0.id == id } }
        let inputs = ContextInputs(manual: memory?.manual, dayStop: dayStop, lastConfirmed: confirmed,
                                   baseAreaId: baseAreaId, baseName: baseName, now: now, calendar: calendar)
        lastInputs = inputs
        let new = ContextRule.resolve(inputs)
        if new != context { context = new }
        if proposal?.id == context.areaId { proposal = nil }
    }

    /// Escolha à mão (cabeçalho de Hoje ou "ver perto"): vale até o fim do dia e vira o último confirmado.
    func choose(_ area: Area, now: Date) {
        memory?.manual = ManualContext(areaId: area.id, name: area.name, chosenAt: now)
        memory?.lastConfirmedAreaId = area.id
        proposal = nil
        reresolve(now: now)
    }

    /// Volta pro automático (parada do dia › confirmado › hotel/cidade).
    func clearManual(now: Date) {
        memory?.manual = nil
        reresolve(now: now)
    }

    func acceptProposal(now: Date) {
        guard let area = proposal else { return }
        choose(area, now: now)
    }

    func dismissProposal(now: Date) {
        guard let area = proposal else { return }
        proposer.dismiss(area.id, now: now)
        proposal = nil
    }

    /// Leitura nova do GPS com o bairro dela (resolvido fora do main). Só pode criar uma proposta; nunca troca o contexto.
    func feed(_ fix: LocationFix, area: Area?, insideTripCity: Bool) {
        let id = proposer.feed(fix, areaId: area?.id, shownAreaId: context.areaId, insideTripCity: insideTripCity)
        if let id, id != context.areaId { proposal = areas.first { $0.id == id } ?? area } else if id == nil, proposal != nil, area?.id != proposal?.id { proposal = nil }
    }

    private func reresolve(now: Date) {
        guard var inputs = lastInputs else { return }
        inputs.manual = memory?.manual
        inputs.lastConfirmed = memory?.lastConfirmedAreaId.flatMap { id in areas.first { $0.id == id } }
        inputs.now = now
        lastInputs = inputs
        context = ContextRule.resolve(inputs)
    }
}
