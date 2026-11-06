import CoreLocation
import Foundation
import Testing
@testable import Must

/// Região automática com N viagens (prompt 28 §3.10): datas de hoje › país do GPS (a mais recente) › casa.
struct RegionAutoTests {
    private func day(_ s: String) -> Date { BoardDates.parseDateTime("\(s)T12:00:00+00:00")! }

    private func trip(_ id: String, _ cc: String, start: String? = nil, end: String? = nil, created: TimeInterval,
                      archived: Bool = false, city: (Double, Double)? = nil) -> Trip {
        Trip(id: id, name: id, shortName: nil, countryCode: cc, currency: "EUR", timeZone: "Europe/Lisbon", colorHex: nil,
             kind: .trip, start: start, end: end,
             cities: city.map { [.init(id: id, name: id, lat: $0.0, lng: $0.1)] } ?? [], home: nil,
             createdAt: Date(timeIntervalSince1970: created), archived: archived, seedId: nil)
    }

    private var all: [Trip] {
        BuiltInTrip.all + [
            trip("portugal-k3f9", "PT", start: "2027-03-12", end: "2027-03-20", created: 1_900_000_000),
            trip("japao-2027", "JP", created: 1_900_000_100),
        ]
    }

    @Test func viagemComHojeNasDatasGanhaDoGPS() {
        // Em BH, mas é 15 nov 2026: o Japão está nas datas.
        #expect(RegionAuto.pick(trips: all, now: day("2026-11-15"), gpsCountry: "BR") == "jp")
        #expect(RegionAuto.pick(trips: all, now: day("2027-03-15"), gpsCountry: nil) == "portugal-k3f9")
    }

    @Test func foraDasDatasValeOPaisDoGPSAMaisRecente() {
        #expect(RegionAuto.pick(trips: all, now: day("2026-10-01"), gpsCountry: "IT") == "it")
        // Duas no Japão: a criada por último.
        #expect(RegionAuto.pick(trips: all, now: day("2026-10-01"), gpsCountry: "JP") == "japao-2027")
        #expect(RegionAuto.pick(trips: all, now: day("2026-10-01"), gpsCountry: "PT") == "portugal-k3f9")
        // No Brasil, a casa (a única do país).
        #expect(RegionAuto.pick(trips: all, now: day("2026-10-01"), gpsCountry: "BR") == "bh")
    }

    @Test func semNadaCaiEmCasa() {
        #expect(RegionAuto.pick(trips: all, now: day("2026-10-01"), gpsCountry: "FR") == "bh")
        #expect(RegionAuto.pick(trips: all, now: day("2026-10-01"), gpsCountry: nil) == "bh")
    }

    @Test func arquivadaNaoEntra() {
        var trips = all
        trips[trips.firstIndex { $0.id == "japao-2027" }!].archived = true
        #expect(RegionAuto.pick(trips: trips, now: day("2026-10-01"), gpsCountry: "JP") == "jp")
    }

    @Test func paisDoGPSPelasCaixasEPelaCidadeDaViagem() {
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        #expect(RegionAuto.country(at: CLLocationCoordinate2D(latitude: 41.1579, longitude: -8.6291), trips: all) == "PT")
        #expect(RegionAuto.country(at: paris, trips: all) == nil)
        let franca = trip("franca-ab12", "FR", created: 1, city: (48.85, 2.35))
        #expect(RegionAuto.country(at: paris, trips: all + [franca]) == "FR")
    }

    @MainActor @Test func storeSegueARegra() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "auto-\(UUID().uuidString)")
        let suite = "auto-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let bh = CLLocationCoordinate2D(latitude: -19.92, longitude: -43.93)
        store.followGPS(tokyo, now: day("2026-10-01"))
        #expect(store.region == .jp)
        // Durante a viagem, voltar pra BH no GPS não tira do Japão.
        store.followGPS(bh, now: day("2026-11-15"))
        #expect(store.region == .jp)
        store.followGPS(bh, now: day("2026-12-01"))
        #expect(store.region == .bh)
    }

    private final class Token {}
}
