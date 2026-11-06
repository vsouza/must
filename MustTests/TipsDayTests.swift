import Foundation
import Testing
@testable import Must

/// Dicas pra hoje (prompt 23 §2 · 07, prompt 24 §2): lugar de agora (laranja), próximo, "Sabia que" do país, volta.
@MainActor
struct TipsDayTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-15T14:20:00+09:00")!

    func stop(_ id: String, _ name: String, kind: ListKind = .place, sub: String? = nil, notes: String = "", queue: Int? = nil,
              hour: Int = 15, golden: Date? = nil, closes: String? = nil) -> DayTips.Stop {
        DayTips.Stop(id: id, placeId: id, name: name, kind: kind, sub: sub, notes: notes, queueMinutes: queue,
                     at: now.addingTimeInterval(Double(hour - 14) * 3600), closesAt: closes, golden: golden, inArea: true, peopleTip: nil)
    }

    @Test func dayOrderAndTones() {
        let cards = DayTips.build(now: now, region: .jp,
                                  current: stop("j05", "Fuunji", sub: "Ramen", notes: "Tsukemen. Só cash.", queue: 20),
                                  next: stop("j104", "Shinjuku Gyoen", kind: .photo, golden: now.addingTimeInterval(8000), closes: "16:00"),
                                  night: stop("j105", "Golden Gai", notes: "Cover de ¥ 500 a 1.000 por bar.", hour: 21),
                                  lastTrain: ("Yamanote", "00:40"), country: PocketRules.country(.jp), saved: [], time: Region.jp.timeString)
        let today = DayTips.filtered(cards, by: .now)
        #expect(today.first?.tone == .orange)
        #expect(today.first?.title == "Compre o ticket na máquina antes de entrar na fila")
        #expect(today.first?.detail.contains("Só cash.") == true)
        #expect(today.first?.tag == "Fuunji · agora")
        #expect(today[1].tag.hasPrefix("Gyoen · "))
        #expect(today[1].corner == "golden")
        #expect(today[1].title.hasPrefix("Fecha 16:00, e o golden é"))
        #expect(today[2].tone == .ink && today[2].tag == "sabia que" && today[2].corner == "Japão")
        #expect(today.contains { $0.tag.hasPrefix("Golden Gai") && $0.corner == "noite" })
        #expect(today.last?.title == "Último Yamanote sai 00:40")
        #expect(DayTips.filtered(cards, by: .etiquette).allSatisfy { $0.filters.contains(.country) })
        #expect(DayTips.filtered(cards, by: .saved).isEmpty)
    }

    @Test func romeMorningWithoutPlan() {
        let morning = ISO8601DateFormatter().date(from: "2027-04-15T09:00:00+02:00")!
        let cards = DayTips.build(now: morning, region: .it, current: nil, next: nil, night: nil,
                                  lastTrain: ("metrô", PocketRules.lastMetro(at: morning, region: .it)),
                                  country: PocketRules.country(.it), saved: ["it-coperto"], time: Region.it.timeString)
        let today = DayTips.filtered(cards, by: .now)
        #expect(today.contains { $0.title.contains("Cappuccino só até as 11h") })
        #expect(today.contains { $0.title.contains("Aperitivo") })
        #expect(today.last?.title == "Último metrô sai 23:30")
        #expect(DayTips.filtered(cards, by: .saved).map(\.id) == ["it-coperto"])
    }

    @Test func shortNames() {
        #expect(DayTips.short("Shinjuku Gyoen") == "Gyoen")
        #expect(DayTips.short("Fuunji · tsukemen") == "Fuunji")
        #expect(DayTips.short("Golden Gai") == "Golden Gai")
    }
}
