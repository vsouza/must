import Foundation
import Testing
@testable import Must

/// Hoje V9 (prompt 32 §2): o cartão da próxima parada, a faixa "agora", a Linha e o Agora leem o mesmo `DayClock`
/// (relatório do viajante, problema 1); cartão Bom dia / Boa noite por horário e dispensa; bairro da parada pro contexto.
@MainActor
struct HojeTests {
    private let plan = DayEngineStub.qaDay
    private var region: Region { .jp }

    private func at(_ h: Int, _ m: Int, day: Int = 15) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    private func clock(_ date: Date) -> DayClock {
        DayClock.make(plan: plan, doneIds: [], at: date, region: region)
    }

    // MARK: Um relógio só

    @Test func cartaoFaixaLinhaEAgoraMostramOMesmoSaiaAs() {
        for (h, m) in [(7, 30), (10, 5), (14, 20), (17, 45)] {
            let c = clock(at(h, m))
            guard let card = HojeLogic.next(clock: c), let action = c.actionTime else { continue }
            let hhmm = region.timeString(action)
            // Cartão de Hoje
            #expect(card.actionAt == action)
            #expect(HojeLogic.line(card, region: region).contains("\(card.verb) às \(hhmm)"))
            // Faixa "agora"
            #expect(NowAccessoryLine.make(clock: c, region: region).contains("\(c.actionVerb) às \(hhmm)"))
            // Linha do dia e Agora usam a mesma regra pura (`DayNowRules`) sobre o mesmo plano
            if let heading = DayNowRules.heading(in: c.active ?? plan, at: c.at), c.phase == .before {
                #expect(heading.leaveAt == action)
            }
            if let now = c.now { #expect((now.arriveBy ?? now.leaveAt) == action) }
        }
    }

    @Test func semDiaNaoHaCartao() {
        let c = DayClock.make(plan: nil, doneIds: [], at: at(14, 0), region: region)
        #expect(HojeLogic.next(clock: c) == nil)
        #expect(NowAccessoryLine.make(clock: c, region: region) == "Montar o dia de hoje")
    }

    @Test func diaConcluidoNaoTemCartao() {
        let c = clock(at(23, 50))
        #expect(HojeLogic.next(clock: c) == nil)
    }

    @Test func proximasParadasNaoRepetemACartaoENaoTemMicro() {
        let c = clock(at(7, 30))
        guard let card = HojeLogic.next(clock: c) else { Issue.record("sem cartão"); return }
        let rest = HojeLogic.following(clock: c, after: card.stopId)
        #expect(rest.count <= 3)
        #expect(!rest.contains { $0.id == card.stopId })
        #expect(rest.allSatisfy { $0.kind != .micro })
    }

    // MARK: Contexto

    @Test func bairroDaParadaVemDoRelogio() {
        let c = clock(at(14, 20))
        let id = HojeLogic.dayStopAreaId(clock: c)
        #expect(id == c.now?.current.area)
        let none = DayClock.make(plan: nil, doneIds: [], at: at(14, 0), region: region)
        #expect(HojeLogic.dayStopAreaId(clock: none) == nil)
    }

    // MARK: Bom dia / Boa noite

    @Test func cartaoPorHorarioEDispensa() {
        let cal = region.calendar
        #expect(HojeLogic.greetingCard(now: at(8, 0), calendar: cal, dismissedKey: nil) == .bomDia)
        #expect(HojeLogic.greetingCard(now: at(12, 0), calendar: cal, dismissedKey: nil) == nil)
        #expect(HojeLogic.greetingCard(now: at(21, 30), calendar: cal, dismissedKey: nil) == .boaNoite)
        let key = HojeLogic.dismissKey(.bomDia, now: at(8, 0), calendar: cal)
        #expect(HojeLogic.greetingCard(now: at(9, 0), calendar: cal, dismissedKey: key) == nil)
        // dia seguinte: volta
        #expect(HojeLogic.greetingCard(now: at(8, 0, day: 16), calendar: cal, dismissedKey: key) == .bomDia)
    }

    @Test func madrugadaAindaEANoiteDoDiaAnterior() {
        let cal = region.calendar
        let night = HojeLogic.dismissKey(.boaNoite, now: at(22, 0, day: 15), calendar: cal)
        #expect(HojeLogic.greetingCard(now: at(0, 40, day: 16), calendar: cal, dismissedKey: night) == nil)
        #expect(HojeLogic.greetingCard(now: at(22, 0, day: 16), calendar: cal, dismissedKey: night) == .boaNoite)
    }

    @Test func fusoDaRegiaoDecideAHora() {
        // 08:00 em Tóquio = 20:00 do dia anterior em BH: o cartão segue o calendário da região.
        let instant = at(8, 0)
        #expect(HojeLogic.greeting(now: instant, calendar: Region.jp.calendar) == .bomDia)
        #expect(HojeLogic.greeting(now: instant, calendar: Region.bh.calendar) == nil)
    }
}
