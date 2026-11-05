import Foundation
import Testing
@testable import Must

/// Bolso por país (prompt 23 §2 · 08, prompt 24 §2): conteúdo offline, câmbio guardado, Suica anotada, último metrô de Roma.
@MainActor
struct PocketRulesTests {
    func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func everyRegionHasAFullGrid() {
        for region in Region.allCases {
            let cards = PocketRules.cards(for: region, context: PocketContext(now: Date()))
            #expect(cards.count >= 8, "\(region)")
            #expect(cards.first?.kind == .exchange)
            #expect(cards.first?.tone == .ink)
            #expect(cards.dropFirst().first?.tone == .orange)
            #expect(Set(cards.map(\.id)).count == cards.count, "ids repetidos em \(region)")
            #expect(PocketRules.phrases(for: region).count == 20, "\(region)")
            #expect(!PocketRules.tips(for: region).isEmpty)
        }
    }

    @Test func romeRules() {
        let cards = PocketRules.cards(for: .it, context: PocketContext(now: date("2027-04-15T11:40:00+02:00")))
        let byKind = Dictionary(uniqueKeysWithValues: cards.map { ($0.kind, $0) })
        #expect(byKind[.ticket]?.value == "€ 1,50")
        #expect(byKind[.ticket]?.detail.contains("100 min") == true)
        #expect(byKind[.tipping]?.value.contains("€ 1–3") == true)
        #expect(byKind[.water]?.value.contains("Nasoni") == true)
        #expect(byKind[.churches]?.detail.contains("12:30–15:30") == true)
        #expect(byKind[.caution]?.value.contains("Bus 64") == true)
        #expect(byKind[.riposo]?.value == "13–16")
        #expect(byKind[.booking]?.value == "€ 5")
        #expect(PocketRules.tips(for: .it).contains { $0.moment == .morning && $0.title.contains("11h") })
    }

    @Test func romeLastMetroLaterOnFridayAndSaturday() {
        #expect(PocketRules.lastMetro(at: date("2027-04-15T21:00:00+02:00"), region: .it) == "23:30") // quinta
        #expect(PocketRules.lastMetro(at: date("2027-04-16T21:00:00+02:00"), region: .it) == "01:30") // sexta
        #expect(PocketRules.lastMetro(at: date("2027-04-18T00:30:00+02:00"), region: .it) == "01:30") // madrugada de sábado p/ domingo
        #expect(PocketRules.lastMetro(at: date("2027-04-18T21:00:00+02:00"), region: .it) == "23:30") // domingo
    }

    @Test func exchangeUsesStoredRateWhenItMakesSense() {
        #expect(PocketRules.rate(.jp, stored: 0.04) == 0.04)
        #expect(PocketRules.rate(.jp, stored: 1) == 0.036) // padrão de BH guardado no Japão: ignora
        #expect(PocketRules.rate(.it, stored: 1) == 6.4)
        #expect(PocketRules.rate(.it, stored: 6.1) == 6.1)
        #expect(PocketRules.exchangeValue(.jp, rate: 0.036, unit: 100) == "¥100\nR$ 3,60")
        #expect(PocketRules.convert(1000, region: .jp, rate: 0.036) == 36)
        #expect(abs(PocketRules.convert(36, region: .jp, rate: 0.036, toBRL: false) - 1000) < 0.001)
    }

    @Test func transitBalanceAndLastTrainComeFromContext() {
        let ctx = PocketContext(now: Date(), brlPerUnit: 0.036, transitBalance: 1240,
                                lastTrain: LastTrain(label: "Último Yamanote → Hibiya Shinjuku → Naka-Meguro", time: "23:58"))
        let cards = PocketRules.cards(for: .jp, context: ctx)
        #expect(cards.first { $0.kind == .transitCard }?.value == "¥ 1.240")
        let train = cards.first { $0.kind == .lastTrain }
        #expect(train?.value == "23:58")
        #expect(train?.detail == "Yamanote → Hibiya · Shinjuku → Naka-Meguro")
        #expect(PocketRules.cards(for: .jp, context: PocketContext(now: Date())).first { $0.kind == .transitCard }?.value == "anotar")
    }

    @Test func phrasesShowOnlyLatinLetters() {
        for region in Region.allCases {
            for phrase in PocketRules.phrases(for: region) {
                let text = phrase.latin + phrase.meaning
                #expect(!text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) },
                        "\(phrase.latin)")
            }
        }
    }

    @Test func cashOnlyFromNotes() {
        #expect(PocketRules.cashOnly(notes: "Balcão, chef fala inglês. Levar dinheiro."))
        #expect(PocketRules.cashOnly(notes: "Só cash."))
        #expect(!PocketRules.cashOnly(notes: "Tsukemen."))
    }

    @Test func momentOfDay() {
        let tz = Region.jp
        #expect(PocketRules.moment(at: date("2026-11-15T08:00:00+09:00"), region: tz) == .morning)
        #expect(PocketRules.moment(at: date("2026-11-15T14:20:00+09:00"), region: tz) == .afternoon)
        #expect(PocketRules.moment(at: date("2026-11-15T21:00:00+09:00"), region: tz) == .night)
        #expect(PocketRules.moment(at: date("2026-11-15T23:40:00+09:00"), region: tz) == .back)
    }
}
