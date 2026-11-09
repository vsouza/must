import Foundation
import Testing
@testable import Must

/// Relatório v9 (item 4): "saia às 14:16" continuava às 14:20. Passada a hora, Hoje e a faixa dizem "saia agora".
struct SaiaAgoraTests {
    private let t = Date(timeIntervalSince1970: 1_794_550_000)

    @Test func antesDaHoraDizAHora() {
        let text = DayClock.actionText(verb: "saia", at: t, now: t.addingTimeInterval(-300), region: .jp)
        #expect(text == "saia às \(Region.jp.timeString(t))")
    }

    @Test func passouDaHoraDizAgora() {
        #expect(DayClock.actionText(verb: "saia", at: t, now: t.addingTimeInterval(240), region: .jp) == "saia agora")
        #expect(DayClock.actionText(verb: "chegue", at: t, now: t, region: .jp) == "chegue agora")
    }
}

/// "Não cabe hoje" sempre com motivo (relatório v9 item 2).
struct NaoCabeMotivoTests {
    private func at(_ h: Int, _ m: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 13; c.hour = h; c.minute = m
        return Region.jp.calendar.date(from: c)!
    }

    @Test func tardeDemais() {
        #expect(DayFit.noFitReason(plan: nil, now: at(22, 20), region: .jp) == "já é tarde pra hoje")
    }

    @Test func fechaAntes() {
        #expect(DayFit.noFitReason(plan: nil, now: at(15, 0), region: .jp, closesAt: at(15, 10)) == "fecha antes de dar tempo")
    }

    @Test func semDiaNaoDaTempo() {
        #expect(DayFit.noFitReason(plan: nil, now: at(15, 0), region: .jp) == "não dá tempo hoje")
    }
}
