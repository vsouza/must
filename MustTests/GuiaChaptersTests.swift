import Foundation
import Testing
@testable import Must

/// Capítulos do Guia do bairro (prompt 23 §2 · 06): paradas do dia por período com hora, Musts do bairro pela janela.
struct GuiaChaptersTests {
    let cal: Calendar = Region.jp.calendar

    @Test func stubDayInShinjukuSplitsAfternoonAndNight() {
        let plan = DayEngineStub.qaDay
        let shinjuku = plan.stops.filter { $0.area == "shinjuku" }
        let now = cal.date(bySettingHour: 14, minute: 20, second: 0, of: plan.date)!
        let extras = [GuiaChapters.Extra(placeId: "j99", title: "Omoide Yokocho", meta: "yakitori", windows: [.dinner], done: false)]
        let chapters = GuiaChapters.build(stops: shinjuku, nowStopId: "s4", extras: extras, calendar: cal, now: now)
        #expect(chapters.map(\.period) == [.tarde, .noite])
        #expect(chapters[0].items.first?.title == "Fuunji · tsukemen")
        #expect(chapters[0].items.first?.isNow == true)
        #expect(chapters[1].items.contains { $0.placeId == "j99" && $0.at == nil })
        #expect(GuiaChapters.rangeText(chapters[0], time: Region.jp.timeString) == "14:35 → 17:30")
    }

    @Test func periodsFromWindows() {
        #expect(GuiaChapters.Period.of(windows: [.lunch]) == .tarde)
        #expect(GuiaChapters.Period.of(windows: [.night]) == .noite)
        #expect(GuiaChapters.Period.of(windows: [.morning]) == .manha)
        #expect(GuiaChapters.Period.of(windows: []) == .tarde)
    }

    @Test func blurbFallsBackToNumbers() {
        #expect(GuiaBlurbs.blurb(areaId: "shinjuku", name: "Shinjuku", musts: 3, open: 1).hasPrefix("Estação mais movimentada"))
        #expect(GuiaBlurbs.blurb(areaId: "xyz", name: "Xyz", musts: 2, open: 1) == "2 Musts seus em Xyz, 1 aberto agora. Comece pelo mais perto.")
    }
}
