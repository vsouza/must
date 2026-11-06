import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 28 · F2: criar (contrato `TripCreating`), arquivar e apagar viagens sem tocar nas outras.
@MainActor
struct TripStoreTests {
    private final class Token {}

    private func makeStore() throws -> (RegionStore, URL, () -> Void) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tripstore-\(UUID().uuidString)")
        let suite = "tripstore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        return (store, dir, {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        })
    }

    /// Portugal do desenho: Lisboa (5 noites) e Porto (3), 12–20 mar 2027, voo de ida, 3 lugares.
    private func portugal() -> NewTripDraft {
        var d = NewTripDraft()
        d.name = "Portugal"
        d.countryCode = "PT"
        d.currency = "EUR"
        d.timeZoneId = "Europe/Lisbon"
        d.colorHex = "#0A5C48"
        d.start = BoardDates.parseDateTime("2027-03-12T00:00:00Z")
        d.end = BoardDates.parseDateTime("2027-03-20T00:00:00Z")
        d.cities = [
            .init(id: "lisboa", name: "Lisboa", latitude: 38.7223, longitude: -9.1393, nights: 5,
                  lodgingName: "Casa do Alfama", lodgingAddress: "Rua dos Remédios 10"),
            .init(id: "porto", name: "Porto", latitude: 0, longitude: 0, nights: 3, neighborhoodOnly: "Ribeira"),
        ]
        d.flights = [.init(number: "TP 82", from: "gru", to: "lis", departure: BoardDates.parseDateTime("2027-03-11T22:00:00-03:00"),
                           arrival: nil, isReturn: false)]
        d.places = [
            .init(name: "Time Out Market", cityId: "lisboa", listId: "eat", latitude: 38.7069, longitude: -9.1459),
            .init(name: "Livraria Lello", cityId: "porto", listId: "shop"),
            .init(name: "Pastéis de Belém", cityId: "lisboa", listId: "coffee", latitude: 38.6975, longitude: -9.2033),
        ]
        d.perDayBudget = 90
        d.fxRate = 6.3
        return d
    }

    @Test func criaPortugalNumStoreNovoSemMexerNasOutras() throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0.hasSuffix(".store") }
        let creator = StoreTripCreator(store: store)
        #expect(creator.existingCountryCodes() == ["JP", "IT"])
        let trip = try store.create(portugal())
        #expect(trip.id.hasPrefix("portugal-") && trip.id.count == "portugal-".count + 4)
        #expect(trip.start == "2027-03-12" && trip.end == "2027-03-20")
        #expect(trip.cities.map(\.from) == ["2027-03-12", "2027-03-17"])
        #expect(trip.cities.map(\.to) == ["2027-03-17", "2027-03-20"])
        #expect(trip.home?.name == "Casa do Alfama")
        #expect(store.trips.map(\.id) == ["bh", "jp", "it", trip.id])
        #expect(store.pendingTrip == trip.id)
        #expect(store.region == .bh) // ainda não trocou: espera a folha fechar
        #expect(creator.existingCountryCodes().contains("PT"))

        store.openPending()
        #expect(store.region.rawValue == trip.id)
        #expect(store.region.currency == "EUR")
        #expect(store.region.profile.code == "PT")
        #expect(TripTheme.forRegion(store.region).coverRGB == 0x0A5C48)
        #expect(!store.isAuto)
        let context = store.container.mainContext
        let info = context.tripInfo()
        #expect(info.cities.map(\.id) == ["lisboa", "porto"])
        #expect(info.cities.first?.lodging?.address == "Rua dos Remédios 10")
        #expect(info.cities.last?.lodging?.neighborhood == "Ribeira")
        #expect(info.cities.last?.hasCoordinate == false)
        #expect(info.hasTrip)
        let settings = context.settings(for: store.region)
        #expect(settings.perDayBudget == 90)
        #expect(settings.fxRate == 6.3)
        let places = try context.fetch(FetchDescriptor<Place>())
        #expect(places.count == 3)
        #expect(Set(places.map { $0.list?.id ?? "" }) == ["eat", "shop", "drink"])
        #expect(places.first { $0.name == "Livraria Lello" }?.placeId == nil)
        let flights = try context.fetch(FetchDescriptor<Flight>())
        #expect(flights.count == 1)
        #expect(flights.first?.legs.first?.from == "GRU")
        #expect(flights.first?.checklist.isEmpty == false)
        // Viagem nova não tem seed: só os três lugares do passo 6.
        #expect(places.allSatisfy { $0.id.hasPrefix("n") })

        let after = try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0.hasSuffix(".store") }
        #expect(Set(after) == Set(before).union([trip.storeFileName]))
        // Reabrir o app: volta na viagem nova, com os dados.
        let reopened = RegionStore(directory: dir, defaults: try #require(UserDefaults(suiteName: "x-\(UUID())")), seedBundle: Bundle(for: Token.self))
        #expect(reopened.region(for: trip.id)?.displayName == "Portugal")
    }

    @Test func arquivarSomeDaListaEOsDadosFicam() throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let trip = try store.create(portugal(), openNow: true)
        store.archive(trip.id)
        #expect(!store.trips.contains { $0.id == trip.id })
        #expect(store.region == .bh) // estava aberta: volta pra casa
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: trip.storeFileName).path()))
        // Casa não arquiva.
        store.archive("bh")
        #expect(store.trips.contains { $0.id == "bh" })
    }

    @Test func apagarRemoveSoOStoreDela() throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        store.switchTo(.jp)
        let trip = try store.create(portugal(), openNow: true)
        store.delete(trip.id)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: trip.storeFileName).path()))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "must-jp.store").path()))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "must-bh.store").path()))
        #expect(store.trips.map(\.id) == ["bh", "jp", "it"])
        #expect(Region(rawValue: trip.id) == nil)
        #expect(store.region == .bh)
        // Casa não apaga.
        store.delete("bh")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "must-bh.store").path()))
        // O Japão continua com o board dele.
        store.switchTo(.jp)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 105)
    }

    @Test func viagemDeRegistroAbreComOMinhasViagens() throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        let trip = try store.create(portugal())
        let rows = TripSwitcherModel.rows(trips: store.trips, active: store.region,
                                          now: BoardDates.parseDateTime("2026-11-05T12:00:00Z")!, gps: nil, doneCount: 0)
        let row = try #require(rows.first { $0.region.rawValue == trip.id })
        #expect(row.title == "Portugal · Lisboa e Porto")
        #expect(row.subtitle == "12–20 mar 2027 · em 127 dias")
        #expect(row.tag == .plano)
    }
}
