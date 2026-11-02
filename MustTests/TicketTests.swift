import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 14 · C (fatia 2): ingresso e experiência no board (export/import), QR, sessão comprada.
@MainActor
struct TicketTests {
    @Test func qrImageComesFromAPayload() throws {
        let image = try #require(TicketQR.image(for: "BR-7K2M-9931"))
        #expect(image.size.width > 0)
        #expect(TicketQR.image(for: "") == nil)
    }

    @Test func experienceAndTicketRoundTripThroughTheBoardFile() throws {
        let container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let codec = BoardCodec(context: container.mainContext, region: .jp)
        let dates = BoardDates(timeZone: Region.jp.timeZone)
        let day = try #require(dates.day(from: "2026-11-15"))
        let at = try #require(dates.time("10:00", on: day))
        let cancelDay = try #require(dates.day(from: "2026-11-13"))
        let cancel = try #require(dates.time("10:00", on: cancelDay))
        let session = EventSession(at: at, title: "Turma das 10h", bought: true)
        let ticket = Ticket(id: "t1", at: at, sessionId: session.id, confirmation: "BR-7K2M-9931", qrPayload: "BR-7K2M-9931",
                            paid: 24_000, people: 2, cancelUntil: cancel)
        let info = ExperienceInfo(supplier: .viator, url: URL(string: "https://www.viator.com/"), durationMinutes: 180,
                                  priceFrom: 12_000, currency: "JPY", rating: 4.9, reviewCount: 1240,
                                  meetingPoint: "Portão 1 do Mercado Externo de Tsukiji", languages: ["inglês"],
                                  groupMax: 8, freeCancellationHours: 24, sessions: [session])
        let board = Board(version: 1, region: .jp,
                          lists: [BoardList(id: "exp", name: "do", color: .night, kind: .experience)],
                          places: [BoardPlace(id: "e1", name: "Aula de sushi com chef em Tsukiji", listId: "exp", cityId: "tokyo1",
                                              lat: 35.6654, lng: 139.7707, extra: PlaceExtra(experience: info), tickets: [ticket])])

        try codec.import(board: board)
        let exported = try codec.export()
        let place = try #require(exported.places.first { $0.id == "e1" })
        #expect(place.extra?.experience?.supplier == .viator)
        #expect(place.extra?.experience?.sessions.first?.bought == true)
        #expect(place.tickets == [ticket])
        #expect(exported.lists.first { $0.id == "exp" }?.kind == .experience)

        // Pela codificação do arquivo (ida e volta), e importar de novo não duplica nada.
        let data = try BoardCodec.encode(exported)
        let back = try BoardCodec.decode(data)
        #expect(back.places.first { $0.id == "e1" }?.tickets == [ticket])
        try codec.import(board: back)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Place>(predicate: #Predicate { $0.id == "e1" })) == 1)
        let stored = try #require(container.mainContext.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.id == "e1" })).first)
        #expect(stored.tickets == [ticket])
        #expect(stored.kind == .experience)
    }

    @Test func ticketForASessionMarksItBought() {
        var extra = PlaceExtra(experience: ExperienceInfo(sessions: [EventSession(at: .now, title: "Turma")]))
        let id = extra.experience?.sessions.first?.id ?? ""
        #expect(extra.experience?.sessions.first?.bought == false)
        extra.markBought([id])
        #expect(extra.experience?.sessions.first?.bought == true)
    }

    @Test func experienceKindUsesItsRawValue() throws {
        let data = try JSONEncoder().encode(ListKind.experience)
        #expect(String(decoding: data, as: UTF8.self) == "\"experience\"")
        #expect(try JSONDecoder().decode(ListKind.self, from: Data("\"experience\"".utf8)) == .experience)
    }
}
