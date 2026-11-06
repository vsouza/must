import Foundation
import SwiftData
import Testing
@testable import Must

/// Rodada 23 · G: o que os testes de digitação e de internet ruim acharam, travado em teste de unidade.
@MainActor
struct RobustnessTests {
    // MARK: Número digitado (crash: `Int(_:)` de 1e20, NaN ou infinito ao reler o campo)

    @Test func numberInputRejectsNaNInfinityAndHuge() {
        #expect(NumberInput.double("nan") == nil)
        #expect(NumberInput.double("inf") == nil)
        #expect(NumberInput.double("-infinity") == nil)
        #expect(NumberInput.double("99999999999999999999") == nil)
        #expect(NumberInput.double("1e400") == nil)
        #expect(NumberInput.double("12.5") == 12.5)
        #expect(NumberInput.double(" 1400 ") == 1400)
    }

    @Test func numberInputIntIsASCIIAndClamped() {
        #expect(NumberInput.int("五百") == nil)
        #expect(NumberInput.int("٣٠") == nil) // dígitos arábicos: isNumber, mas Int(_:) não lê
        #expect(NumberInput.int("90 min") == 90)
        #expect(NumberInput.int("9223372036854775807999") == NumberInput.maxInt)
        #expect(NumberInput.int("") == nil)
    }

    @Test func roundedNeverTraps() {
        #expect(NumberInput.rounded(.nan) == nil)
        #expect(NumberInput.rounded(.infinity) == nil)
        #expect(NumberInput.rounded(1e20) == nil)
        #expect(NumberInput.rounded(24_000.4) == 24_000)
        #expect(NumberInput.intText(nil) == "")
        #expect(NumberInput.intText(1e19) == "")
    }

    /// Preço colado com 20 dígitos ou "nan" no Ingresso/Carteira/Compras não vira valor (e a tela não cai ao reler).
    @Test func ticketMoneyParseIsFinite() {
        #expect(TicketMoney.parse("nan") == 0)
        #expect(TicketMoney.parse("inf") == 0)
        #expect(TicketMoney.parse("100000000000000000000000") == 0)
        #expect(TicketMoney.parse("24.000") == 24_000)
        #expect(TicketMoney.parse("12,50") == 12.5)
    }

    /// Editar lugar: o preço digitado "nan" ou gigante não vai pro board (o Gasto lia `Int(price)` e caía).
    @Test func placeDraftPriceIgnoresGarbage() throws {
        let container = RegionStore.inMemoryContainer()
        let context = ModelContext(container)
        defer { withExtendedLifetime(container) {} }
        let list = MustList(id: "eat", name: "eat", icon: .cafe, color: .eat)
        context.insert(list)
        for (typed, expected) in [("nan", nil), ("99999999999999999999", nil), ("38,90", 38.9), ("1.250", 1250.0)] as [(String, Double?)] {
            let place = Place(id: "t-\(typed)", name: "x", cityId: "bh")
            context.insert(place)
            var draft = PlaceDraft()
            draft.priceText = typed
            draft.apply(to: place, name: "x", list: list, region: .bh)
            #expect(place.price == expected, "\(typed)")
        }
    }

    // MARK: Internet ruim (`-debugNetwork flaky|dropping`)

    @Test func flakyFaultsAreFortyPercent() {
        #expect(NetworkChaos.fault(roll: 0.05) == .timeout)
        #expect(NetworkChaos.fault(roll: 0.15) == .server)
        #expect(NetworkChaos.fault(roll: 0.20) == .tooMany)
        #expect(NetworkChaos.fault(roll: 0.30) == .truncated)
        #expect(NetworkChaos.fault(roll: 0.39) == .invalidJSON)
        #expect(NetworkChaos.fault(roll: 0.40) == .none)
        #expect(NetworkChaos.fault(roll: 0.99) == .none)
    }

    @Test func droppingAlternatesStartingOnline() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(!NetworkChaos.droppingIsOffline(at: start.addingTimeInterval(1), period: 4, since: start))
        #expect(NetworkChaos.droppingIsOffline(at: start.addingTimeInterval(5), period: 4, since: start))
        #expect(!NetworkChaos.droppingIsOffline(at: start.addingTimeInterval(9), period: 4, since: start))
    }

    /// No host de testes os modos DEBUG ficam desligados (a suíte nunca dorme 8 s nem perde resposta).
    @Test func chaosIsOffInTestHost() {
        #expect(NetworkChaos.mode == .off)
    }

    /// Foto do Google cortada no meio (rede caindo) não vai pro disco: lá ela ficaria quebrada por 30 dias.
    @Test func truncatedPhotoIsNotComplete() {
        let full = PhotoFixtures.jpeg(200, 260)
        #expect(PlacePhotoStore.isCompleteImage(full))
        #expect(!PlacePhotoStore.isCompleteImage(full.prefix(full.count / 2)))
        #expect(!PlacePhotoStore.isCompleteImage(Data("{\"places\": [".utf8)))
        #expect(!PlacePhotoStore.isCompleteImage(Data()))
    }

    // MARK: Colar texto não fica "Lendo o texto…" pra sempre

    @Test func deadlineCutsSlowWork() async {
        let clock = ContinuousClock()
        let start = clock.now
        let slow = await TravelTextExtractor.withDeadline(.milliseconds(150)) { () async throws -> Int in
            try await Task.sleep(for: .seconds(10))
            return 1
        }
        #expect(slow == nil)
        #expect(clock.now - start < .seconds(3))
        let fast = await TravelTextExtractor.withDeadline(.seconds(2)) { 7 }
        #expect(fast == 7)
    }

    /// Modelo travado: o texto cai nas palavras-chave dentro do teto, com os lugares do 📍.
    @Test func stuckModelFallsBackToKeywords() async {
        let clock = ContinuousClock()
        let start = clock.now
        let text = String(repeating: "Dia 1 em Shinjuku: 📍 Ichiran Shibuya e 📍 Fuunji. ", count: 120)
        let draft = await TravelTextExtractor.analyze(text, onDevice: true, knownAreas: [], blockTimeout: .milliseconds(200),
                                                      totalTimeout: .milliseconds(400)) { _ in
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
        #expect(clock.now - start < .seconds(5))
        #expect(draft.via == "palavras-chave")
        #expect(!draft.places.isEmpty)
    }

    @Test func gpsHopParses() {
        let hops = LocationService.parseHops("16:-19.93,-43.93; 7:35.69,139.70;lixo;3:1")
        #expect(hops.count == 2)
        #expect(hops.first?.after == 7)
        #expect(hops.first?.lat == 35.69)
        #expect(hops.last?.lng == -43.93)
    }
}
