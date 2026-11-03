import Foundation
import Testing
@testable import Must

/// Prompt 18 · A.1: cache do JSON decodificado (horários, extras, ingressos, cidades).


struct JSONMemoTests {
    @Test func cacheSeguePeloDataQuandoOSyncTroca() throws {
        let place = Place(id: "p", name: "Bar", cityId: "fixtureTokyo")
        place.hours = fixtureDinnerHours()
        #expect(place.hours?.periods?.count == 6)

        // O SwiftData trocou o Data por sync/merge sem passar pelo setter computado.
        place.hoursData = try JSONEncoder.board(timeZone: .gmt).encode(fixtureLateBarHours())
        #expect(place.hours?.periods?.count == 1)
    }

    @Test func decodificaUmaVezPorVersaoDoData() throws {
        let place = Place(id: "p", name: "Bar", cityId: "fixtureTokyo")
        place.hoursData = try JSONEncoder.board(timeZone: .gmt).encode(fixtureDinnerHours())
        for _ in 0..<100 { _ = place.hours }
        #expect(place.hoursMemo.misses == 1)
    }

    @Test func setterNaoPrecisaDecodificar() {
        let place = Place(id: "p", name: "Bar", cityId: "fixtureTokyo")
        place.hours = fixtureDinnerHours()
        for _ in 0..<50 { _ = place.hours }
        #expect(place.hoursMemo.misses == 0)
    }

    @Test func extrasETicketsTambemInvalidam() throws {
        let place = Place(id: "p", name: "Museu", cityId: "fixtureTokyo")
        place.tickets = [Ticket(at: fixtureAt("2026-11-15T10:00:00+09:00"), confirmation: "A1")]
        #expect(place.tickets.first?.confirmation == "A1")
        place.ticketsData = nil
        #expect(place.tickets.isEmpty)
        place.ticketsData = try JSONEncoder.board(timeZone: .gmt).encode([Ticket(at: fixtureAt("2026-11-16T10:00:00+09:00"), confirmation: "B2")])
        #expect(place.tickets.first?.confirmation == "B2")
    }

    @Test func cidadesDaViagemInvalidam() throws {
        let trip = TripInfo()
        trip.cities = [City(id: "fixtureTokyo", name: "Tóquio", from: nil, to: nil, tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76)]
        #expect(trip.city(id: "fixtureTokyo")?.name == "Tóquio")
        trip.citiesData = try JSONEncoder.board(timeZone: .gmt).encode([City(id: "kyoto", name: "Quioto", from: nil, to: nil, tz: "Asia/Tokyo", currency: "JPY", lat: 35.01, lng: 135.77)])
        #expect(trip.city(id: "kyoto")?.name == "Quioto")
        #expect(trip.city(id: "fixtureTokyo") == nil)
    }
}
