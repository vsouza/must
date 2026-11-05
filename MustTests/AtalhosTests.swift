import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import Must

/// Atalhos (prompt 25 · D): gesto, grade e linhas perto — tudo do aparelho.
@MainActor
struct AtalhosTests {
    @Test func deslizePraDireitaAbreOsAtalhos() {
        let now = Region.jp.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 14, minute: 20))!
        #expect(CapaSwipe.action(for: .right, now: now, region: .jp) == .atalhos)
        #expect(CapaSwipe.action(for: .left, now: now, region: .jp) == .route(.dicas))
        #expect(CapaSwipe.action(for: .down, now: now, region: .jp) == nil)
    }

    @Test func suicaNoJapaoCarteiraNoBrasil() {
        let jp = AtalhosRules.walletCard(region: .jp, transitName: "Suica", balance: 1240, notedNote: nil, walletCount: 3)
        #expect(jp.label == "Wallet" && jp.title.contains("Suica"))
        let bh = AtalhosRules.walletCard(region: .bh, transitName: nil, balance: nil, notedNote: nil, walletCount: 0)
        #expect(bh.label == "Carteira" && !bh.title.contains("Suica"))
        let bhCard = AtalhosRules.walletCard(region: .bh, transitName: "BHBus", balance: 25, notedNote: nil, walletCount: 1)
        #expect(bhCard.title.hasPrefix("BHBus"))
    }

    @Test func sosPorPais() {
        #expect(AtalhosRules.sosCard(region: .jp).detail.hasPrefix("119"))
        #expect(AtalhosRules.sosCard(region: .bh).detail.hasPrefix("192"))
        #expect(AtalhosRules.sosCard(region: .it).detail.hasPrefix("112"))
    }

    @Test func gradeViraUmaColunaNoXXXL() {
        #expect(AtalhosRules.columns(for: .large) == 2)
        #expect(AtalhosRules.columns(for: .xxxLarge) == 1)
        #expect(AtalhosRules.columns(for: .accessibility3) == 1)
    }

    @Test func linhasPertoDeShinjukuEmLetrasLatinas() throws {
        let here = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)
        let lines = try #require(AtalhosRules.lines(near: here, transit: TransitLoader.load(.jp), areas: AreaCatalog.areas(for: .jp), region: .jp))
        #expect(lines.station == "Shinjuku")
        #expect(lines.lines.contains { $0.code == "JY" && $0.name == "Yamanote" })
        #expect(lines.lines.allSatisfy { $0.name.unicodeScalars.allSatisfy { $0.value < 0x3000 } })
    }

    @Test func bhLongeDoMetroNaoInventaEstacao() {
        // Savassi fica longe da Linha 1.
        let savassi = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)
        #expect(AtalhosRules.lines(near: savassi, transit: TransitLoader.load(.bh), areas: AreaCatalog.areas(for: .bh), region: .bh) == nil)
    }

    @Test func notaDoUltimoTrem() {
        let note = AtalhosRules.note(lastTrain: LastTrain(label: "Último Yamanote → Hibiya Shinjuku → Naka-Meguro", time: "23:58"),
                                     leaveAt: "15:20", next: "Gyoen")
        #expect(note == "último Yamanote 23:58 · saia às 15:20 pro Gyoen")
    }
}
