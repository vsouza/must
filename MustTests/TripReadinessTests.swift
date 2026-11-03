import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Rodada 21 · fatia 5 (prontidão da viagem): o que tem que estar certo antes de embarcar em 11/11.
@MainActor
struct TripReadinessTests {
    private final class Token {}
    private static var bundle: Bundle { Bundle(for: Token.self) }
    private static let jpDates = BoardDates(timeZone: Region.jp.timeZone)

    /// Container em memória; quem chama guarda o `ModelContainer` enquanto usa o contexto.
    private static func jpContainer() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private static func jpSeed() throws -> Board {
        let url = try #require(Region.jp.seedURL(in: bundle), "seed-jp.json fora do bundle de testes")
        return try BoardCodec.decode(Data(contentsOf: url))
    }

    // MARK: 1 · TripInfo

    @Test func tripInfoCoversTheWholeJapanTrip() throws {
        let container = try Self.jpContainer()
        let context = container.mainContext
        try BoardCodec(context: context, region: .jp).import(board: Self.jpSeed())
        let trip = context.tripInfo()

        #expect(trip.hasTrip)
        #expect(trip.start.map(Self.jpDates.dayString) == "2026-11-11")
        #expect(trip.end.map(Self.jpDates.dayString) == "2026-11-24")
        #expect(trip.home == "Naka-Meguro")
        #expect(Region.jp.timeZone.identifier == "Asia/Tokyo")
        #expect(Region.jp.currency == "JPY")
    }

    @Test func citiesFollowTheRouteTokyoKyotoTokyo() throws {
        let container = try Self.jpContainer()
        let context = container.mainContext
        try BoardCodec(context: context, region: .jp).import(board: Self.jpSeed())
        let cities = context.tripInfo().cities
        #expect(cities.map(\.id) == ["tokyo1", "kyoto", "tokyo2"])
        #expect(cities.allSatisfy { $0.tz == "Asia/Tokyo" })

        // tokyo1 começa no dia da chegada (voo de NY sai 12/11 e pousa 13/11 em Tóquio), não em 11/11 (saída de BH).
        let expected: [(String, String, String)] = [
            ("tokyo1", "2026-11-13", "2026-11-17"),
            ("kyoto", "2026-11-17", "2026-11-20"),
            ("tokyo2", "2026-11-20", "2026-11-24"),
        ]
        for (id, from, to) in expected {
            let city = try #require(cities.first { $0.id == id })
            #expect(city.from.map(Self.jpDates.dayString) == from, "\(id) começa em \(from)")
            #expect(city.to.map(Self.jpDates.dayString) == to, "\(id) termina em \(to)")
        }
        // Cada troca de cidade é no mesmo dia: o fim de uma é o começo da próxima.
        for (a, b) in zip(cities, cities.dropFirst()) {
            #expect(a.to == b.from)
        }
    }

    @Test func cityDatesStayInsideTheTrip() throws {
        let container = try Self.jpContainer()
        let context = container.mainContext
        try BoardCodec(context: context, region: .jp).import(board: Self.jpSeed())
        let trip = context.tripInfo()
        let start = try #require(trip.start)
        let end = try #require(trip.end)
        for city in trip.cities {
            let from = try #require(city.from)
            let to = try #require(city.to)
            #expect(from >= start && to <= end, "\(city.id) fora de 11–24/11")
        }
    }

    // MARK: 2 · Seed completo e válido

    @Test func everyJapanPlaceIsValid() throws {
        let board = try Self.jpSeed()
        let cityIds = Set(board.trip?.cities?.map(\.id) ?? [])
        let listIds = Set(board.lists.map(\.id))
        #expect(cityIds == ["tokyo1", "kyoto", "tokyo2"])

        #expect(Set(board.places.map(\.id)).count == board.places.count, "ids de lugar repetidos")
        #expect(Set(board.lists.map(\.id)).count == board.lists.count, "ids de lista repetidos")

        for place in board.places {
            #expect(cityIds.contains(place.cityId), "\(place.id) aponta pra cidade fora da viagem: \(place.cityId)")
            #expect(listIds.contains(place.listId), "\(place.id) aponta pra lista inexistente: \(place.listId)")
            // Japão inteiro (de Okinawa a Hokkaido): nada de coordenada invertida ou zerada.
            let lat = try #require(place.lat, "\(place.id) sem latitude")
            let lng = try #require(place.lng, "\(place.id) sem longitude")
            #expect((24...46).contains(lat) && (122...154).contains(lng), "\(place.id) fora do Japão")
            #expect(place.name.isEmpty == false)
        }
    }

    @Test func reservationsFallInsideTheTrip() throws {
        let board = try Self.jpSeed()
        let start = try #require(Self.jpDates.day(from: "2026-11-11"))
        let end = try #require(Self.jpDates.day(from: "2026-11-25"))
        for place in board.places {
            guard let at = place.reservation?.at else { continue }
            #expect(at >= start && at < end, "reserva de \(place.id) fora da viagem")
        }
    }

    // MARK: 3 · Mapas offline (catálogo; nada é baixado aqui)

    @Test func mapCatalogDecodesWithTokyoAndKyoto() throws {
        let packs = MapPack.load(from: Self.bundle)
        #expect(packs.isEmpty == false, "map-packs.json não decodificou no bundle de testes")
        #expect(packs.contains { $0.region == .bh }, "falta o recorte de BH")

        let jp = packs.filter { $0.region == .jp }
        let tokyo = try #require(jp.first { $0.id == "jp-tokyo" })
        let kyoto = try #require(jp.first { $0.id == "jp-kansai" })
        #expect(tokyo.title == "Tóquio")
        #expect(kyoto.title.hasPrefix("Kyoto"))

        // Os recortes têm que cobrir o centro das cidades da viagem.
        #expect(tokyo.contains(CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)))
        #expect(kyoto.contains(CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681)))
        // E um recorte é do tamanho de uma cidade (não o país inteiro).
        #expect(tokyo.bbox[2] - tokyo.bbox[0] < 1 && kyoto.bbox[2] - kyoto.bbox[0] < 1)
    }

    // MARK: 6 · Carteira: Suica e JR Pass por padrão no Japão

    @Test func walletStarterAddsSuicaAndJRPassOnce() throws {
        let container = try Self.jpContainer()
        let context = container.mainContext
        WalletStarter.ensure(context, region: .jp)
        let items = context.walletItems()
        #expect(items.map(\.kind) == [.transitCard, .railPass])
        #expect(items.first?.name == "Suica")
        #expect(items.first?.balance == nil, "saldo é anotado à mão, nunca chutado")

        // Rodar de novo não duplica.
        WalletStarter.ensure(context, region: .jp)
        #expect(context.walletItems().count == 2)

        // Apagado não volta.
        context.delete(try #require(items.first))
        try context.save()
        WalletStarter.ensure(context, region: .jp)
        #expect(context.walletItems().map(\.kind) == [.railPass])
    }

    @Test func walletStarterStaysOutOfBH() throws {
        let container = try Self.jpContainer()
        let context = container.mainContext
        WalletStarter.ensure(context, region: .bh)
        #expect(context.walletItems().isEmpty)
    }
}
