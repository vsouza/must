import Foundation
import SwiftUI
import SwiftData

// Tipos do dia v8 (prompt 23 §3). Contrato da fase 0 da rodada 22: o agente B é dono desta pasta e implementa o
// `DayEngine` real sobre o solver atual; as telas (C, D) leem só `DayPlan`/`DayStop`/`DayLeg` e o `\.dayEngine`.

/// Papel da parada na Linha do dia.
enum StopKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// Âncora: ingresso, reserva, golden, trem. Card tinta. Horário fixo.
    case anchor
    /// Must livre do board. Card branco.
    case must
    /// Micro-parada gerada (café, konbini, descanso, compra rápida, vista). Tracejada, 10–40 min, nunca vira âncora.
    case micro
}

/// Uma parada do dia.
struct DayStop: Identifiable, Hashable, Sendable, Codable {
    var id: String
    /// Lugar do board (`Place.id`); `nil` em micro-parada genérica ("Descanso no hotel").
    var placeId: String?
    var kind: StopKind
    var start: Date
    var end: Date
    /// Título na Linha ("Fuunji · tsukemen").
    var label: String
    /// Linha de meta ("Must eat · fila ~20 min · ¥ 1.250").
    var note: String
    /// Selo curto no quadradinho da esquerda ("QR", "RES", "SOL", "café", "zz", "¥"); `nil` = índice da parada.
    var tag: String? = nil
    /// Bairro (`Area.id`), pro selo e pro Guia.
    var area: String? = nil
    /// Custo previsto na moeda da região.
    var cost: Double? = nil
    var done: Bool = false
    // Acrescentados pelo motor real (agente B); todos com valor padrão, o contrato continua valendo.
    /// Por que é âncora (selo e regra do "saia às"). `nil` em Must livre e micro-parada.
    var anchor: DayAnchorReason? = nil
    /// Que micro-parada é (ícone, liga/desliga). `nil` fora das micro-paradas.
    var micro: DayMicroKind? = nil
    /// Fila prevista em minutos (board/Places). Com fila e sem reserva, o "saia às" vira "chegue às".
    var queueMinutes: Int? = nil
    /// Abertura do lugar nesse dia (o "chegue às" de quem tem fila). `nil` = sem horário.
    var opensAt: Date? = nil
    /// Onde fica (micro-parada: no hotel ou perto da parada vizinha). `nil` = sem coordenada.
    var lat: Double? = nil
    var lng: Double? = nil
    /// Fora da meta do dia ("vale a exceção").
    var isException: Bool = false

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    /// Hora marcada de verdade (reserva, ingresso): não tem "chegue às" nem margem de fila.
    var isBooked: Bool { anchor == .reservation || anchor == .ticket }
}

/// Por que uma parada é âncora.
enum DayAnchorReason: String, Codable, Hashable, Sendable, CaseIterable {
    /// Reserva (RES). Em Roma, com turno: fim fixo.
    case reservation
    /// Ingresso ou sessão comprada (QR).
    case ticket
    /// Foto no golden (SOL): a luz manda no horário.
    case golden
    /// Domingo sem carros na Via Appia (Roma).
    case sunday
    /// Trem com hora (Shinkansen, voo): reservado pra quando o board tiver.
    case train
}

/// Tipos de micro-parada gerada (prompt 23 §3). Duração fixa de 10 a 40 min, nunca âncora.
enum DayMicroKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// Café da manhã perto do hotel (Roma: cornetto no balcão).
    case breakfast
    /// Konbini/água antes de fila longa (Roma: nasone).
    case water
    /// 40 min no hotel quando a noite tem âncora depois das 19h.
    case rest
    /// Compra rápida a caminho (depachika, tax-free, alimentari).
    case shop
    /// Vista/foto no caminho ou no golden.
    case view
    /// Doce no caminho à tarde (Roma: gelato).
    case treat
    /// Exposição em cartaz aberta e em temporada, que cabe num buraco do dia (RODADA-23 · A). TODO(r23:A): arquivo é do motor, só o case.
    case show

    /// Minutos fixos.
    var minutes: Int {
        switch self {
        case .breakfast: 30
        case .water: 10
        case .rest: 40
        case .shop: 15
        case .view: 15
        case .treat: 15
        case .show: 30
        }
    }
}

/// Modo de um deslocamento.
enum DayLegMode: String, Codable, Hashable, Sendable, CaseIterable {
    case walk, train, metro, bus, taxi
}

/// Deslocamento entre duas paradas: é um item da Linha, não um detalhe do lugar.
struct DayLeg: Hashable, Sendable, Codable {
    var mode: DayLegMode
    var minutes: Int
    /// `DayStop.id` de origem e destino.
    var from: String
    var to: String
    /// "JY Yamanote 09:12 · plat. 14" / "a pé 14 min · ou Marunouchi 1 parada".
    var detail: String
    /// Partida (trem) quando conhecida.
    var departAt: Date? = nil
    /// `true` quando veio do Routes (rede); `false` = estimativa offline.
    var live: Bool = false
}

/// Último trem útil do dia: vira a última linha da Linha e um aviso.
struct DayLastTrain: Hashable, Sendable, Codable {
    var line: String
    var at: Date
}

/// Ritmo do dia: quantas paradas (âncoras + Musts + micro).
enum Pace: Int, Codable, Hashable, Sendable, CaseIterable {
    case calm = 6
    case normal = 9
    case intense = 12

    var label: String {
        switch self {
        case .calm: "calmo"
        case .normal: "normal"
        case .intense: "intenso"
        }
    }
}

/// O que o Montar pede pra incluir.
enum DayInclude: String, Codable, Hashable, Sendable, CaseIterable {
    case micro, goldenPhoto, shopping
}

/// O dia montado.
struct DayPlan: Hashable, Sendable, Codable {
    /// Meia-noite do dia, no fuso da região.
    var date: Date
    /// "Shinjuku + Tsukiji".
    var title: String
    /// Número do dia na viagem (numeral da capa); `nil` fora da viagem.
    var dayNumber: Int?
    /// Bairro principal (`Area.id`).
    var area: String?
    var stops: [DayStop]
    /// `legs[i]` liga `stops[i]` a `stops[i+1]` quando há deslocamento (pode haver menos legs que paradas − 1).
    var legs: [DayLeg]
    var lastTrain: DayLastTrain?
    var pace: Pace
    var budget: Double
    var spent: Double = 0
    /// O que o Montar pediu (micro-paradas, foto no golden, compras): volta igual quando o dia aceito é relido.
    var includes: Set<DayInclude> = [.micro, .goldenPhoto]

    var anchors: [DayStop] { stops.filter { $0.kind == .anchor } }
    var plannedCost: Double { stops.compactMap(\.cost).reduce(0, +) }

    func leg(after stop: DayStop) -> DayLeg? { legs.first { $0.from == stop.id } }
    func leg(before stop: DayStop) -> DayLeg? { legs.first { $0.to == stop.id } }
}

/// "Agora": a parada atual, a hora de sair e a próxima.
struct DayNow: Hashable, Sendable {
    var current: DayStop
    /// "saia às" = início da próxima − deslocamento − margem.
    var leaveAt: Date
    var next: DayStop?
    /// Lugar sem reserva com fila: "chegue às" (abertura + 0) em vez de "saia às".
    var arriveBy: Date? = nil
}

/// Motor do dia. O real (agente B) roda o solver atual e gera micro-paradas e deslocamentos.
protocol DayEngine: Sendable {
    /// Monta o dia de hoje com o ritmo pedido.
    func build(area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>) async -> DayPlan
    /// Monta o dia de uma data (amanhã, no Montar da Boa noite). Padrão: o de hoje.
    func build(on date: Date, area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>) async -> DayPlan
    /// "Outra" (Montar › proposta): o mesmo pedido com outra semente de desempate. Padrão: ignora a semente.
    func build(on date: Date, area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>, seed: Int) async -> DayPlan
    /// "Agora" num instante do dia; `nil` antes da primeira parada ou depois da última.
    func now(in plan: DayPlan, at date: Date) -> DayNow?
    /// O dia aceito numa data (do SwiftData), já no formato v8. `nil` = nada montado.
    @MainActor func plan(for date: Date, region: Region, context: ModelContext) -> DayPlan?
}

extension DayEngine {
    func build(on date: Date, area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>) async -> DayPlan {
        await build(area: area, pace: pace, budget: budget, until: until, includes: includes)
    }

    func build(on date: Date, area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>, seed: Int) async -> DayPlan {
        await build(on: date, area: area, pace: pace, budget: budget, until: until, includes: includes)
    }

    /// "Agora" (prompt 23 §3): a parada cujo horário de saída é o próximo. `DayNowRules` tem as contas.
    func now(in plan: DayPlan, at date: Date) -> DayNow? {
        DayNowRules.now(in: plan, at: date)
    }
}

/// Stub do contrato: devolve o dia de QA do `Dia.png` (sáb 15/11/2026, Shinjuku + Tsukiji, 9 paradas) em qualquer pedido.
struct DayEngineStub: DayEngine {
    init() {}

    func build(area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>) async -> DayPlan {
        Self.qaDay
    }

    @MainActor func plan(for date: Date, region: Region, context: ModelContext) -> DayPlan? {
        region == .jp ? Self.qaDay : nil
    }

    /// Dia 3 · sáb 15 nov · Shinjuku + Tsukiji · 9 paradas, 3 âncoras · ¥ 4.250 de 12.000.
    static let qaDay: DayPlan = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        func t(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        let stops: [DayStop] = [
            DayStop(id: "s1", placeId: nil, kind: .micro, start: t(8, 30), end: t(9, 0), label: "Fuglen Tokyo",
                    note: "micro · café filtrado · a pé do hotel", tag: "café", area: "shibuya", cost: 600, done: true, micro: .breakfast),
            DayStop(id: "s2", placeId: nil, kind: .anchor, start: t(10, 0), end: t(12, 0), label: "Aula de sushi · Tsukiji",
                    note: "ingresso · 2 h · feito", tag: "QR", area: "tsukiji", done: true, anchor: .ticket),
            DayStop(id: "s3", placeId: nil, kind: .micro, start: t(12, 30), end: t(12, 45), label: "Konbini · água e onigiri",
                    note: "7-Eleven na saída · caixa 7 Bank aqui", tag: "7", area: "tsukiji", cost: 400, micro: .water),
            DayStop(id: "s4", placeId: "j05", kind: .must, start: t(14, 35), end: t(15, 20), label: "Fuunji · tsukemen",
                    note: "Must eat · fila ~20 min · ¥ 1.250", area: "shinjuku", cost: 1_250, queueMinutes: 20),
            DayStop(id: "s5", placeId: "j104", kind: .anchor, start: t(15, 48), end: t(16, 40), label: "Shinjuku Gyoen · golden",
                    note: "Must photo · entrada até 16:00 · ¥ 500", tag: "SOL", area: "shinjuku", cost: 500, anchor: .golden),
            DayStop(id: "s6", placeId: nil, kind: .micro, start: t(16, 50), end: t(17, 30), label: "Descanso no hotel",
                    note: "40 min · carregar o celular · trocar de roupa", tag: "zz", area: "shinjuku", micro: .rest),
            DayStop(id: "s7", placeId: nil, kind: .micro, start: t(18, 10), end: t(18, 25), label: "Isetan · depachika",
                    note: "doces pra levar · tax-free acima de ¥ 5.000", tag: "¥", area: "shinjuku", cost: 1_500, micro: .shop),
            DayStop(id: "s8", placeId: "j01", kind: .anchor, start: t(19, 0), end: t(21, 0), label: "Udatsu Sushi",
                    note: "reserva · omakase · 2 pessoas · ¥ 22.000", tag: "RES", area: "nakameguro", anchor: .reservation),
            DayStop(id: "s9", placeId: "j105", kind: .must, start: t(21, 30), end: t(23, 30), label: "Golden Gai · bar Albatross",
                    note: "Must drink · cover ¥ 800 · só cash", area: "shinjuku", cost: 800),
        ]
        let legs: [DayLeg] = [
            DayLeg(mode: .train, minutes: 34, from: "s1", to: "s2", detail: "JY Yamanote 09:12 · 34 min · plat. 14", departAt: t(9, 12)),
            DayLeg(mode: .metro, minutes: 24, from: "s3", to: "s4", detail: "Hibiya → Shinjuku 13:05 · 24 min", departAt: t(13, 5)),
            DayLeg(mode: .walk, minutes: 14, from: "s4", to: "s5", detail: "a pé 14 min · ou Marunouchi 1 parada"),
            DayLeg(mode: .train, minutes: 22, from: "s7", to: "s8", detail: "Yamanote → Naka-Meguro 18:30 · 22 min", departAt: t(18, 30)),
        ]
        let lastTrain = DayLastTrain(line: "Yamanote", at: cal.date(byAdding: .minute, value: 40, to: cal.date(byAdding: .day, value: 1, to: day)!)!)
        return DayPlan(date: day, title: "Shinjuku + Tsukiji", dayNumber: 3, area: "shinjuku", stops: stops, legs: legs,
                       lastTrain: lastTrain, pace: .normal, budget: 12_000, spent: 4_250)
    }()
}

// MARK: - Ambiente

private struct DayEngineKey: EnvironmentKey {
    static var defaultValue: any DayEngine { DayEngineStub() }
}

extension EnvironmentValues {
    /// Motor do dia. O agente B injeta o real em `MustApp`; sem injeção, o stub (dia de QA).
    var dayEngine: any DayEngine {
        get { self[DayEngineKey.self] }
        set { self[DayEngineKey.self] = newValue }
    }
}
