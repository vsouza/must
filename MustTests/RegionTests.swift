import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// As três regiões (prompt 24 §1): fuso, moeda, formato do dinheiro, GPS, container próprio e tema.
@MainActor
struct RegionTests {
    private final class Token {}

    // MARK: Fuso, moeda, calendário

    @Test func tresRegioesComFusoEMoeda() {
        #expect(Region.allCases == [.bh, .jp, .it])
        #expect(Region.bh.timeZone.identifier == "America/Sao_Paulo")
        #expect(Region.jp.timeZone.identifier == "Asia/Tokyo")
        #expect(Region.it.timeZone.identifier == "Europe/Rome")
        #expect(Region.it.calendar.timeZone.identifier == "Europe/Rome")
        #expect(Region.it.calendar.identifier == .gregorian)
        #expect(Region.allCases.map(\.currency) == ["BRL", "JPY", "EUR"])
        #expect(Region.allCases.map(\.currencySymbol) == ["R$", "¥", "€"])
        #expect(Region.allCases.map(\.country) == ["BR", "JP", "IT"])
        #expect(Region.it.displayName == "Roma")
        #expect(Region.it.countryName == "Itália")
        #expect(Region.it.kanji == nil)
        // A UI é sempre pt-BR, inclusive em Roma.
        #expect(Region.it.locale.identifier == "pt_BR")
    }

    @Test func euroNoFormatoDoMust() {
        #expect(Region.it.money(12.5) == "€ 12,50")
        #expect(Region.it.money(64) == "€ 64")
        #expect(Region.it.money(1_234.5) == "€ 1.234,50")
        #expect(Region.it.money(120, symbol: false) == "120")
        #expect(Region.bh.money(12.5) == "R$ 12,50")
        #expect(Region.jp.money(15_000) == "¥ 15.000")
        #expect(MoneyFormatStyle.symbol(for: "EUR") == "€")
    }

    @Test func orcamentoECambioPadrao() {
        #expect(Region.it.defaultBudget == 120)
        #expect("\(Region.it.money(64)) de \(Region.it.money(Region.it.defaultBudget))" == "€ 64 de € 120")
        #expect(Region.it.hasFX && Region.jp.hasFX && !Region.bh.hasFX)
        #expect(Region.it.fxUnitLabel == "€1")
        #expect(Region.jp.fxUnitLabel == "¥100")
        #expect(Region.jp.defaultFXRate == 0.036)
        #expect(Region.it.defaultFXRate > 1)
    }

    @Test func horaEDataNoFusoDeRoma() throws {
        // 2027-04-12T11:00:00+02:00 (Borghese) = 09:00 UTC.
        let at = try #require(BoardDates.parseDateTime("2027-04-12T11:00:00+02:00"))
        #expect(Region.it.timeString(at) == "11:00")
        #expect(Region.it.shortDay(at) == "12 abr")
        #expect(Region.it.utcOffsetLabel == "+01:00" || Region.it.utcOffsetLabel == "+02:00")
    }

    // MARK: GPS

    @Test(arguments: [
        (41.8955, 12.4823, Region?.some(.it)),   // Roma
        (41.9029, 12.4534, Region?.some(.it)),   // Vaticano
        (45.4642, 9.1900, Region?.some(.it)),    // Milão
        (37.5079, 15.0830, Region?.some(.it)),   // Catânia
        (35.6762, 139.6503, Region?.some(.jp)),  // Tóquio
        (-19.9245, -43.9352, Region?.some(.bh)), // BH
        (48.8566, 2.3522, Region?.none),         // Paris
        (40.7128, -74.0060, Region?.none),       // Nova York
    ])
    func detectaRegiaoPeloGPS(lat: Double, lng: Double, expected: Region?) {
        #expect(Region.detect(CLLocationCoordinate2D(latitude: lat, longitude: lng)) == expected)
    }

    // MARK: Container próprio

    @Test func cadaRegiaoTemOProprioStore() {
        #expect(Region.allCases.map(\.storeFileName) == ["must-bh.store", "must-jp.store", "must-it.store"])
        #expect(Set(Region.allCases.map(\.storeURL)).count == 3)
    }

    @Test func trocarPraRomaAbreMustItStoreComOSeed() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-tests-\(UUID().uuidString)")
        let suite = "must-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        #expect(store.region == .bh)

        store.switchTo(.it)
        #expect(store.region == .it)
        #expect(store.lastError == nil)
        #expect(defaults.string(forKey: RegionStore.regionKey) == "it")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "must-it.store").path()))
        let context = store.container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 63)
        let settings = context.settings(for: .it)
        #expect(settings.perDayBudget == 120)
        #expect(settings.fxRate == Region.it.defaultFXRate)
        #expect(context.tripInfo().cities.map(\.id) == ["roma"])
        #expect(context.tripInfo().cities.first?.currency == "EUR")

        // As outras regiões continuam com o board delas; voltar pra Roma não duplica nada.
        store.switchTo(.bh)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 50)
        store.switchTo(.it)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 63)
    }

    @Test func automaticoAbreRomaNaItalia() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-tests-\(UUID().uuidString)")
        let suite = "must-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        #expect(store.isAuto)
        store.followGPS(CLLocationCoordinate2D(latitude: 41.8890, longitude: 12.4700))
        #expect(store.region == .it)
        // Escolher à mão desliga o automático.
        store.choose(.jp, near: nil)
        #expect(!store.isAuto)
        store.followGPS(CLLocationCoordinate2D(latitude: 41.8890, longitude: 12.4700))
        #expect(store.region == .jp)
    }

    // MARK: Tema e textos

    @Test func temaDeRomaEhDaItalia() {
        #expect(TripTheme.forRegion(.it).country == "IT")
        #expect(TripTheme.forRegion(.jp).country == "JP")
        #expect(TripTheme.forRegion(.bh).country == "BR")
    }

    @Test func ajustesListamItalia() {
        #expect(Region.allCases.map(RegionPicker.label) == ["BH", "Japão", "Itália"])
        #expect(OfflineMapsView.sectionTitle(.it) == "Itália")
        #expect(MapPack.catalog.contains { $0.id == "it-roma" && $0.region == .it })
        let roma = try? #require(MapPack.catalog.first { $0.id == "it-roma" })
        #expect(roma?.bbox == [12.40, 41.83, 12.56, 41.95])
        #expect(roma?.contains(CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.4922)) == true) // Colosseo
    }

    @Test func cidadeEPaisNaoViramLugar() {
        for word in ["Roma", "Rome", "Itália", "Italia", "Italy", "Trastevere", "Vaticano"] {
            #expect(!PlaceExtractor.isPlausible(word), "\(word) não é nome de lugar")
        }
        #expect(PlaceExtractor.isPlausible("Da Enzo al 29"))
    }

    @Test func roteiroDeRomaNaoUsaAsLinhasDeBH() {
        #expect(TransitLoader.fileName(for: .it) != TransitLoader.fileName(for: .bh))
        #expect(TransitLoader.fileName(for: .jp) == "tokyo-lines")
    }

    @MainActor @Test func metroDeRomaEstaNoBundle() {
        let map = TransitLoader.load(.it)
        #expect(Set(map.lines.map(\.id)) == ["A", "B", "B1", "C"])
        #expect(map.lines.allSatisfy { $0.approx && $0.lastTrain == "23:30" })
    }
}
