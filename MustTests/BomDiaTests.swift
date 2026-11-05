import Foundation
import Testing
@testable import Must

/// Bom dia (prompt 23 §2 · 02): checklist "Antes de sair" e a frase do tempo.
struct BomDiaTests {
    private let plan = DayEngineStub.qaDay

    private func weather(code: Int = 0, rain: Int = 0) -> DayWeather {
        DayWeather(tempMin: 12, tempMax: 18, code: code, precipProb: rain, sunrise: nil, sunset: nil)
    }

    @Test func diaDeQATemPassaporteECash() {
        let items = MorningChecklist.items(plan: plan, transitCard: nil, weather: weather(), region: .jp)
        #expect(items.map(\.kind) == [.passport, .cash])
        #expect(items[0].text == "Passaporte (ingresso + tax-free)")
        #expect(items[1].text == "Dinheiro: Golden Gai é só cash")
    }

    @Test func suicaAbaixoDoPisoPedeRecarga() {
        let low = MorningChecklist.items(plan: plan, transitCard: .init(name: "Suica", balance: 1_240), weather: nil, region: .jp)
        #expect(low.contains { $0.kind == .transitCard && $0.text == "Suica ¥ 1.240 · recarregar" })
        let ok = MorningChecklist.items(plan: plan, transitCard: .init(name: "Suica", balance: 3_000), weather: nil, region: .jp)
        #expect(!ok.contains { $0.kind == .transitCard })
    }

    @Test func chuvaPedeGuardaChuva() {
        let items = MorningChecklist.items(plan: nil, transitCard: nil, weather: weather(code: 61, rain: 80), region: .jp)
        #expect(items.map(\.kind) == [.umbrella])
        #expect(items[0].text == "Guarda-chuva · 80% de chuva")
    }

    @Test func emBHNaoPedePassaporteNemSuica() {
        let items = MorningChecklist.items(plan: plan, transitCard: .init(name: "BHBus", balance: 2), weather: weather(), region: .bh)
        #expect(!items.contains { $0.kind == .passport || $0.kind == .transitCard })
    }

    @Test func soCashPelasNotasDoLugar() {
        var day = plan
        day.stops = [DayStop(id: "x", placeId: "p1", kind: .must, start: .now, end: .now, label: "Bar do Zé", note: "Must drink")]
        let items = MorningChecklist.items(plan: day, placeNotes: ["p1": "Só dinheiro, sem cartão"], transitCard: nil,
                                           weather: nil, region: .bh)
        #expect(items.map(\.kind) == [.cash])
    }

    @Test func fraseDoTempo() {
        let golden = Region.jp.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 16, minute: 0))!
        #expect(MorningText.sentence(today: weather(), golden: golden, nextRain: "terça, indo pra Kyoto", region: .jp)
                == "Sol o dia todo, golden às 16:00. Chuva só terça, indo pra Kyoto.")
        #expect(MorningText.sentence(today: weather(code: 63, rain: 90), golden: nil, nextRain: "terça", region: .jp)
                == "Chuva hoje, 90% de chance.")
        #expect(MorningText.sentence(today: nil, golden: nil, nextRain: nil, region: .jp) == "Sem previsão no aparelho.")
    }

    @Test func primeiroTremUtil() {
        let at = plan.stops[0].start
        #expect(MorningText.firstTrain(plan, after: at)?.from == "s1")
        let later = plan.stops[3].start
        #expect(MorningText.firstTrain(plan, after: later)?.to == "s8")
    }
}
