import CoreLocation
import Foundation
import Testing
@testable import Must

/// Quero… (prompt 25 · A.3): "cabe HH:MM" — o encaixe de 25 min não move nenhuma parada.
@MainActor
struct QueroTests {
    private let plan = DayEngineStub.qaDay
    private var cal: Calendar { Region.jp.calendar }
    private func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: plan.date)! }
    /// Bic Camera, na saída leste de Shinjuku.
    private let bic = CLLocationCoordinate2D(latitude: 35.69185, longitude: 139.7028)
    private let origin = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)

    @Test func cabeNumBuracoSemMexerNasParadas() throws {
        let slot = try #require(DayFit.slot(at: bic, plan: plan, now: at(9, 40), region: .jp, origin: origin))
        #expect(slot.end.timeIntervalSince(slot.start) == 25 * 60)
        let stop = DayFit.stop(placeId: "q1", name: "Bic Camera", note: "", slot: slot, area: "shinjuku", at: bic)
        let out = DayFit.inserting(stop, into: plan, date: plan.date, region: .jp)
        #expect(out.stops.count == plan.stops.count + 1)
        // Todas as outras paradas ficam onde estavam.
        for old in plan.stops {
            let same = try #require(out.stops.first { $0.id == old.id })
            #expect(same.start == old.start && same.end == old.end)
        }
        // E a nova não encosta em nenhuma.
        for other in plan.stops { #expect(slot.end <= other.start || slot.start >= other.end) }
        #expect(slot.detour <= DayFit.onTheWayMinutes)
    }

    @Test func passadoNaoConta() {
        let slot = DayFit.slot(at: bic, plan: plan, now: at(20, 0), region: .jp, origin: origin)
        #expect(slot.map { $0.start >= at(20, 0) } ?? true)
    }

    @Test func semDiaSaiAgora() throws {
        let slot = try #require(DayFit.slot(at: bic, plan: nil, now: at(14, 2), region: .jp, origin: origin))
        #expect(slot.start >= at(14, 2) && slot.start <= at(14, 20))
        #expect(slot.after == nil && slot.before == nil)
        #expect(DayFit.slot(at: bic, plan: nil, now: at(22, 40), region: .jp, origin: origin) == nil)
    }

    @Test func fechaAntesNaoCabe() {
        #expect(DayFit.slot(at: bic, plan: nil, now: at(18, 50), region: .jp, origin: origin,
                            closesAt: QueroModel.closing("19h", on: at(18, 50), region: .jp)) == nil)
        #expect(QueroModel.closing("19h30", on: at(9, 0), region: .jp) == at(19, 30))
    }

    @Test func listaDaVontade() {
        let lists = [MustList(id: "eat", name: "eat", icon: .cafe, color: .eat), MustList(id: "shop", name: "shop", icon: .cafe, color: .shop)]
        #expect(QueroSave.list(for: WantParser.parseLocal("quero comprar um Seiko"), lists: lists)?.id == "shop")
        #expect(QueroSave.list(for: WantParser.parseLocal("quero comer um pão de queijo"), lists: lists)?.id == "eat")
        let source = QueroSave.source(text: " quero comprar um Seiko ", region: .jp)
        #expect(source.caption == "quero comprar um Seiko")
        #expect(source.author == QueroSave.marker)
    }
}
