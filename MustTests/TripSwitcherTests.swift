import Foundation
import Testing
@testable import Must

/// Minhas viagens (prompt 27 §7): as três regiões, a ativa marcada, a etiqueta de cada uma.
@MainActor
struct TripSwitcherTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, region: Region = .jp) -> Date {
        region.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 14))!
    }

    @Test func tresRegioesComAAtivaMarcada() {
        let rows = TripSwitcherModel.rows(active: .bh, now: date(2026, 11, 5), gps: .bh, doneCount: 21)
        #expect(rows.map(\.region) == [.bh, .jp, .it])
        #expect(rows.filter(\.isActive).map(\.region) == [.bh])
        #expect(rows.first { $0.region == .bh }?.subtitle == "sempre disponível · 21 feitos")
    }

    @Test func japaoNaViagemEAgora() {
        let rows = TripSwitcherModel.rows(active: .jp, now: date(2026, 11, 15), gps: .bh, doneCount: 38)
        let jp = rows.first { $0.region == .jp }
        #expect(jp?.tag == .agora)
        #expect(jp?.subtitle == "11–24 nov 2026 · dia 5 de 14 · 38 feitos")
        #expect(rows.first { $0.region == .bh }?.tag == .gps)
        #expect(rows.first { $0.region == .it }?.tag == .plano)
        #expect(rows.first { $0.region == .it }?.subtitle == "sem datas")
    }

    @Test func antesDaViagemContaOsDias() {
        let jp = TripSwitcherModel.rows(active: .bh, now: date(2026, 11, 5), gps: .bh, doneCount: 0).first { $0.region == .jp }
        #expect(jp?.tag == .plano)
        #expect(jp?.subtitle == "11–24 nov 2026 · em 6 dias")
    }

    @Test func novaViagemAparece() {
        #expect(TripSwitcherSheet.newTripEnabled)
    }

    @Test func trocarNaoApagaNada() throws {
        // `RegionStore.switchTo` abre o container da outra região e guarda o atual (não deleta arquivo).
        let dir = URL.temporaryDirectory.appending(path: "trip-switch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = RegionStore(directory: dir, defaults: UserDefaults(suiteName: "trip-switch-\(UUID().uuidString)")!, seedBundle: Bundle(for: Anchor.self))
        let first = store.region
        let other = Region.allCases.first { $0 != first }!
        store.choose(other, near: nil)
        #expect(store.region == other)
        #expect(!store.isAuto)
        #expect(store.retiredCount >= 1)
    }
    private final class Anchor {}
}
