import Foundation
import Testing
@testable import Must

/// Contrato r32/0 (prompt 32 §3): a ordem do contexto de Hoje. O agente C cobre o GPS em `ContextRuleTests`.
struct ContextContractTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    private func area(_ id: String) -> Area {
        Area(id: id, name: id.capitalized, nameLocal: nil, cityId: "tokyo", centroid: .init(lat: 35.69, lng: 139.70),
             polygon: nil, stationIds: [], aliases: [], neighbors: [], stampText: nil, stampSub: nil, heroPhotoRef: nil)
    }
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func manualVenceTudoNoMesmoDia() {
        let i = ContextInputs(manual: .init(areaId: "nakano", name: "Nakano", chosenAt: now.addingTimeInterval(-3600)),
                              dayStop: area("shinjuku"), lastConfirmed: area("ginza"), baseAreaId: "asakusa", baseName: "Asakusa",
                              now: now, calendar: cal)
        #expect(ContextRule.resolve(i) == TodayContext(areaId: "nakano", name: "Nakano", source: .manual))
    }

    @Test func manualDeOntemNaoValeEParadaDoDiaManda() {
        let i = ContextInputs(manual: .init(areaId: "nakano", name: "Nakano", chosenAt: now.addingTimeInterval(-86_400 * 2)),
                              dayStop: area("shinjuku"), lastConfirmed: area("ginza"), baseAreaId: nil, baseName: "Tóquio",
                              now: now, calendar: cal)
        #expect(ContextRule.resolve(i).source == .dayStop)
        #expect(ContextRule.resolve(i).areaId == "shinjuku")
    }

    @Test func semNadaCaiNaCidade() {
        let i = ContextInputs(manual: nil, dayStop: nil, lastConfirmed: nil, baseAreaId: nil, baseName: "Tóquio", now: now, calendar: cal)
        #expect(ContextRule.resolve(i) == TodayContext(areaId: nil, name: "Tóquio", source: .base))
    }
}
