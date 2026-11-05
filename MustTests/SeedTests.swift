import Foundation
import SwiftData
import Testing
@testable import Must

/// Seed de Roma (`data/seed-it.json`, prompt 24) e os bairros (`Must/Data/areas/roma.json`).
@MainActor
struct SeedTests {
    private final class Token {}
    private static var bundle: Bundle { Bundle(for: Token.self) }

    private static func seed() throws -> Board {
        let url = try #require(Region.it.seedURL(in: bundle), "seed-it.json fora do bundle de testes")
        return try BoardCodec.decode(Data(contentsOf: url))
    }

    private static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // MARK: Seed

    @Test func seedDeRomaDecodifica() throws {
        let board = try Self.seed()
        #expect(board.region == .it)
        #expect(board.places.count == 63)
        #expect(board.lists.count == 9)
        #expect(board.places.filter { $0.reservation != nil }.count == 7)
        #expect(Set(board.places.map(\.id)).count == 63)
        #expect(board.places.allSatisfy { $0.cityId == "roma" })
        #expect(board.budget?.perDay == 120)
        #expect(board.budget?.currency == "EUR")
        // Datas da viagem ainda [A CONFIRMAR]: placeholder 10–18/04/2027.
        #expect(board.trip?.start == "2027-04-10")
        #expect(board.trip?.end == "2027-04-18")
        #expect(board.events?.filter { $0.kind == .flight }.count == 3)
        #expect(board.lists.first { $0.id == "do" }?.kind == .experience)
        // Toda lista aponta pra um ícone do set (nada cai no genérico sem querer).
        for list in board.lists {
            #expect(list.icon.flatMap(MustIcon.init(rawValue:)) != nil, "ícone da lista \(list.id)")
        }
    }

    @Test func reservaDoBorgheseNoFusoDeRoma() throws {
        let board = try Self.seed()
        let borghese = try #require(board.places.first { $0.id == "r46" })
        #expect(borghese.reservation?.at == ISO8601DateFormatter().date(from: "2027-04-12T09:00:00Z"))
        #expect(borghese.listId == "art")
        #expect(borghese.area == "Villa Borghese")
    }

    @Test func seedCarregaNoContainer() throws {
        let container = try Self.container()
        let context = container.mainContext
        try RegionStore.seedIfEmpty(context, region: .it, bundle: Self.bundle)
        let places = try context.fetch(FetchDescriptor<Place>())
        #expect(places.count == 63)
        #expect(places.filter { $0.reservation != nil }.count == 7)
        #expect(try context.fetchCount(FetchDescriptor<MustList>()) == 9)
        let trip = context.tripInfo()
        #expect(trip.cities.map(\.id) == ["roma"])
        #expect(trip.cities.first?.tz == "Europe/Rome")
        #expect(context.settings(for: .it).seenSeedIds.count == 63)
    }

    @Test func mergeDoSeedEhIdempotente() throws {
        let container = try Self.container()
        let context = container.mainContext
        try RegionStore.seedIfEmpty(context, region: .it, bundle: Self.bundle)
        let events = try context.fetchCount(FetchDescriptor<TripEvent>())
        let flights = try context.fetchCount(FetchDescriptor<Flight>())
        #expect(events + flights > 0, "os voos placeholder entram")
        // Segunda e terceira abertura: o board já existe e passa pelo merge.
        try RegionStore.seedIfEmpty(context, region: .it, bundle: Self.bundle)
        try RegionStore.mergeSeed(context, region: .it, bundle: Self.bundle)
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 63)
        #expect(try context.fetchCount(FetchDescriptor<MustList>()) == 9)
        #expect(try context.fetchCount(FetchDescriptor<TripEvent>()) == events)
        #expect(try context.fetchCount(FetchDescriptor<Flight>()) == flights)

        // Lugar apagado não volta.
        let gone = try #require(try context.fetch(FetchDescriptor<Place>()).first { $0.id == "r10" })
        context.delete(gone)
        try context.save()
        try RegionStore.mergeSeed(context, region: .it, bundle: Self.bundle)
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 62)
    }

    @Test func mergeTrazLugarNovoDoSeed() throws {
        let container = try Self.container()
        let context = container.mainContext
        try RegionStore.seedIfEmpty(context, region: .it, bundle: Self.bundle)
        // Board antigo que ainda não tinha visto dois lugares do seed.
        for id in ["r80", "r81"] {
            let place = try #require(try context.fetch(FetchDescriptor<Place>()).first { $0.id == id })
            context.delete(place)
        }
        let settings = context.settings(for: .it)
        settings.seenSeedIds.removeAll { $0 == "r80" || $0 == "r81" }
        try context.save()
        try RegionStore.mergeSeed(context, region: .it, bundle: Self.bundle)
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 63)
        try RegionStore.mergeSeed(context, region: .it, bundle: Self.bundle)
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 63)
    }

    // MARK: Bairros

    private static let codes: [String: String] = [
        "Centro Storico": "CEN", "Trastevere": "TRA", "Monti": "MON", "Prati": "PRA", "Vaticano": "VAT",
        "Testaccio": "TES", "Ghetto": "GHE", "Campo Marzio": "CMA", "Aventino": "AVE", "Esquilino": "ESQ",
        "Flaminio": "FLA", "Ostiense": "OST", "Appia": "APP", "Villa Borghese": "VBO", "Monteverde": "MVE",
    ]

    @Test func quinzeBairrosDeRoma() {
        let areas = AreaCatalog.areas(for: .it)
        #expect(areas.count == 15)
        #expect(Dictionary(areas.map { ($0.name, $0.seal) }, uniquingKeysWith: { a, _ in a }) == Self.codes)
        #expect(areas.allSatisfy { $0.cityId == AreasIT.cityId })
        #expect(areas.allSatisfy { $0.nameLocal == nil }, "selo sem japonês nem enfeite: só sigla + nome latino")
        // Ids não colidem com os de Tóquio, Kyoto e BH.
        let others = Set((AreaCatalog.jp + AreaCatalog.bh).map(\.id))
        #expect(areas.allSatisfy { !others.contains($0.id) })
    }

    @Test func stampCodeNoJSON() throws {
        // `Area.stampCode` (agente A) lê a chave "stampCode"; o JSON já traz a sigla com esse nome.
        let url = try #require(Bundle.main.url(forResource: "roma", withExtension: "json")
                                 ?? Bundle(for: Token.self).url(forResource: "roma", withExtension: "json"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let areas = try #require(json["areas"] as? [[String: Any]])
        let codes = Dictionary(areas.compactMap { a in (a["name"] as? String).map { ($0, a["stampCode"] as? String ?? "") } },
                               uniquingKeysWith: { a, _ in a })
        #expect(codes == Self.codes)
    }

    @Test func vizinhosSimetricosComOsTemposDoPrompt() throws {
        let areas = AreaCatalog.areas(for: .it)
        let byId = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func minutes(_ a: String, _ b: String) -> Int? { byId[a]?.neighbors.first { $0.areaId == b }?.minutes }
        for area in areas {
            #expect(!area.neighbors.isEmpty, "\(area.name) sem vizinho")
            for n in area.neighbors {
                #expect(byId[n.areaId] != nil, "\(area.id) → \(n.areaId) não existe")
                #expect(minutes(n.areaId, area.id) == n.minutes, "\(area.id) ↔ \(n.areaId) não é simétrico")
            }
        }
        #expect(minutes("centro-storico", "ghetto") == 6)
        #expect(minutes("ghetto", "trastevere") == 8)
        #expect(minutes("monti", "centro-storico") == 12)
        #expect(minutes("prati", "vaticano") == 8)
        #expect(minutes("testaccio", "aventino") == 10)
        #expect(minutes("esquilino", "monti") == 8)
    }

    @Test func todoLugarDoSeedCaiNumBairroDeRoma() throws {
        let board = try Self.seed()
        let areas = AreaCatalog.areas(for: .it)
        let assigner = AreaAssigner(areas: areas)
        let names = Set(areas.map(\.name))
        for place in board.places {
            #expect(names.contains(place.area ?? ""), "\(place.id) \(place.name): bairro \(place.area ?? "nil") fora da tabela")
            #expect(assigner.areaId(name: place.area, cityId: place.cityId, lat: place.lat ?? 0, lng: place.lng ?? 0) != nil)
        }
        // Os bairros do design: Da Enzo em Trastevere, Colosseo em Monti, Borghese na Villa Borghese.
        let byId = Dictionary(board.places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(assigner.areaId(name: byId["r30"]?.area, cityId: "roma", lat: 0, lng: 0) == "monti")
        #expect(assigner.areaId(name: "Colosseo", cityId: "roma", lat: 0, lng: 0) == "monti")
        #expect(assigner.areaId(name: "Pincio", cityId: "roma", lat: 0, lng: 0) == "villa-borghese")
    }

    @Test func centroideDosBairrosPertoDosLugares() throws {
        // Sem nome, o lugar cai no bairro pelo centroide (até 1,2 km): a maioria dos lugares do seed acha o próprio.
        let board = try Self.seed()
        let areas = AreaCatalog.areas(for: .it)
        let assigner = AreaAssigner(areas: areas)
        let idByName = Dictionary(areas.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        let hits = board.places.filter { p in
            assigner.areaId(name: nil, cityId: "roma", lat: p.lat ?? 0, lng: p.lng ?? 0) == idByName[p.area ?? ""]
        }
        #expect(hits.count >= 40, "só \(hits.count) de 63 pelo centroide")
    }
}
