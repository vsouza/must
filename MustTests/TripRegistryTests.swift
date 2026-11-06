import Foundation
import Testing
@testable import Must

/// Prompt 28 §3.2: `trips.json` semeado com as três de fábrica (mesmos arquivos `.store`); criar, arquivar e tirar
/// uma viagem não toca nas outras.
struct TripRegistryTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "trips-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func newTrip(_ id: TripID) -> Trip {
        Trip(id: id, name: "Portugal", shortName: nil, countryCode: "PT", currency: "EUR", timeZone: "Europe/Lisbon",
             colorHex: "#0A5C48", kind: .trip, start: "2027-03-12", end: "2027-03-20",
             cities: [.init(id: "lisboa", name: "Lisboa", lat: 38.7223, lng: -9.1393)], home: nil,
             createdAt: Date(timeIntervalSince1970: 1_800_000_000), archived: false, seedId: nil)
    }

    @Test func semeiaAsTresDeFabricaComOsMesmosArquivos() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = TripRegistry(directory: dir)
        #expect(registry.trips.map(\.id) == ["bh", "jp", "it"])
        #expect(registry.trips.map(\.storeFileName) == ["must-bh.store", "must-jp.store", "must-it.store"])
        #expect(registry.trips.map(\.seedId) == ["bh", "jp", "it"])
        #expect(registry.trips.map(\.countryCode) == ["BR", "JP", "IT"])
        #expect(registry.trip("bh")?.kind == .home)
        #expect(registry.trip("jp")?.start == "2026-11-11" && registry.trip("jp")?.end == "2026-11-24")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "trips.json").path()))
        // Os nomes de arquivo batem com os de antes do registro.
        #expect(Region.allCases.map(\.storeFileName) == registry.trips.map(\.storeFileName))
    }

    @Test func reabreOQueFoiGravado() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = TripRegistry(directory: dir)
        a.upsert(newTrip("portugal-k3f9"))
        let b = TripRegistry(directory: dir)
        #expect(b.trips.map(\.id) == ["bh", "jp", "it", "portugal-k3f9"])
        #expect(b.trip("portugal-k3f9") == newTrip("portugal-k3f9"))
        #expect(b.trip("portugal-k3f9")?.storeFileName == "must-portugal-k3f9.store")
    }

    @Test func arquivarETirarNaoTocamNasOutras() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = TripRegistry(directory: dir)
        registry.upsert(newTrip("portugal-k3f9"))
        registry.setArchived("it", true)
        #expect(registry.visible.map(\.id) == ["bh", "jp", "portugal-k3f9"])
        #expect(registry.trip("it")?.archived == true)
        registry.remove("portugal-k3f9")
        let reopened = TripRegistry(directory: dir)
        #expect(reopened.trips.map(\.id) == ["bh", "jp", "it"])
        #expect(reopened.trip("jp") == BuiltInTrip.jp)
        #expect(reopened.trip("bh") == BuiltInTrip.bh)
    }

    @Test func arquivoIlegivelNaoEhSobrescrito() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "trips.json")
        try Data("{ quebrado".utf8).write(to: url)
        let registry = TripRegistry(directory: dir)
        #expect(registry.trips.map(\.id) == ["bh", "jp", "it"])
        registry.upsert(newTrip("portugal-k3f9"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ quebrado")
    }

    @Test func idNovoComSlugEQuatroLetras() {
        var letters = ["k3f9"].makeIterator()
        #expect(Trip.newID(name: "Portugal", random: { letters.next() ?? "zzzz" }) == "portugal-k3f9")
        #expect(Trip.newID(name: "São Tomé & Príncipe", random: { "ab12" }) == "sao-tome-principe-ab12")
        #expect(Trip.newID(name: "  ", random: { "ab12" }) == "viagem-ab12")
        // Colisão: tenta outro sufixo.
        var seq = ["aaaa", "bbbb"].makeIterator()
        #expect(Trip.newID(name: "Portugal", taken: ["portugal-aaaa"], random: { seq.next()! }) == "portugal-bbbb")
        #expect(Trip.randomSuffix().count == 4)
    }

    @Test func datasDaViagem() throws {
        let trip = newTrip("portugal-k3f9")
        let range = try #require(trip.range)
        let cal = trip.calendar
        #expect(cal.component(.day, from: range.lowerBound) == 12)
        #expect(trip.contains(try #require(BoardDates.parseDateTime("2027-03-15T10:00:00+00:00"))))
        #expect(!trip.contains(try #require(BoardDates.parseDateTime("2027-03-21T10:00:00+00:00"))))
        #expect(BuiltInTrip.it.range == nil)
    }
}
