import CoreLocation
import Foundation
import SwiftData

/// Um relógio de verdade (relatório do viajante, problema 1): a **única** fonte do "agora no plano" (parada atual, próxima,
/// saia às, quantas faltam, se o dia foi ajustado). Capa, Linha do dia, Agora, Guia, Bom dia e Boa noite leem daqui, então
/// às 14:20 todas dizem a mesma coisa. Puro: recebe o plano aceito, os "feito" e a hora.
struct DayClock: Sendable {
    enum Phase: Equatable, Sendable {
        /// Sem dia montado.
        case noPlan
        /// Antes da primeira parada que falta.
        case before
        /// Tem parada de agora.
        case running
        /// Nada mais falta (tudo feito, ficou pra depois ou já passou).
        case finished
    }

    /// Quando foi lido.
    var at: Date
    var phase: Phase
    /// O dia inteiro, com os "feito" aplicados e o resto reposicionado se atrasou. `nil` sem dia.
    var plan: DayPlan?
    /// Só o que ainda vale (sem feito, sem os que ficaram pra depois): é o plano do relógio.
    var active: DayPlan?
    /// Ficaram pra depois (passaram da hora sem "feito" ou não cabem mais).
    var skipped: [DayStop]
    /// Mudaram de hora no ajuste.
    var shifted: [String]
    /// A parada de agora e a hora de sair dela.
    var now: DayNow?
    /// Antes da primeira parada: ela e a hora de sair pra ela.
    var upcoming: Upcoming?

    struct Upcoming: Equatable, Sendable {
        var stop: DayStop
        var leaveAt: Date
    }

    var skippedIds: Set<String> { Set(skipped.map(\.id)) }
    /// O dia foi refeito agora ("Atrasou? Ajustei").
    var adjusted: Bool { !skipped.isEmpty }
    /// Quantas paradas ainda faltam (a de agora conta).
    var remaining: Int { active?.stops.count ?? 0 }

    /// Hora de sair da parada de agora, ou a de "chegue às" da seguinte (o que o Agora mostra em grande).
    var actionTime: Date? { now.map { $0.arriveBy ?? $0.leaveAt } ?? upcoming?.leaveAt }
    /// "saia" / "chegue".
    var actionVerb: String { now?.arriveBy != nil ? "chegue" : "saia" }

    /// Posição (de 1) da parada de agora no dia inteiro.
    var position: Int? { now.flatMap { n in plan?.position(of: n.current) } }

    // MARK: Leitura

    static func make(plan raw: DayPlan?, doneIds: Set<String>, at date: Date, region: Region,
                     position: CLLocationCoordinate2D? = nil) -> DayClock {
        guard var plan = raw, !plan.stops.isEmpty else {
            return DayClock(at: date, phase: .noPlan, plan: raw, active: nil, skipped: [], shifted: [], now: nil, upcoming: nil)
        }
        plan.stops = plan.stops.map { var s = $0; if doneIds.contains(s.id) { s.done = true }; return s }
        var skipped: [DayStop] = []
        var shifted: [String] = []
        if let replan = DayReplanner.replan(plan, at: date, region: region, position: position) {
            plan = replan.plan
            skipped = replan.skipped
            shifted = replan.shifted
        }
        let hidden = Set(skipped.map(\.id))
        var active = plan
        active.stops = plan.stops.filter { !$0.done && !hidden.contains($0.id) }
        let started = (plan.stops.map(\.start).min() ?? .distantFuture) <= date
        let now = DayNowRules.now(in: active, at: date, dayStarted: started)
        var upcoming: Upcoming?
        if now == nil, !started, let first = active.stops.first, date < first.start {
            upcoming = Upcoming(stop: first, leaveAt: DayNowRules.leaveTime(to: first, in: active))
        }
        let phase: Phase = now != nil ? .running : (upcoming != nil ? .before : .finished)
        return DayClock(at: date, phase: phase, plan: plan, active: active, skipped: skipped, shifted: shifted, now: now, upcoming: upcoming)
    }

    /// Lê o dia aceito de hoje no motor e o "feito" do dia. É o que toda tela chama.
    @MainActor
    static func read(engine: any DayEngine, region: Region, context: ModelContext, at date: Date,
                     position: CLLocationCoordinate2D? = nil) -> DayClock {
        let day = region.calendar.startOfDay(for: date)
        let raw = engine.plan(for: day, region: region, context: context)
        return make(plan: raw, doneIds: DayDoneStore().ids(day: BoardDates(timeZone: region.timeZone).dayString(date)), at: date,
                    region: region, position: position)
    }
}
