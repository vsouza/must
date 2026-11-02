#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen ingresso`: cria (uma vez) uma experiência de exemplo com ingresso, só pra print do QA.
/// Dados de demonstração no board da região atual; não toca em nada que já existe.
@MainActor
enum TicketDemo {
    static let placeId = "demo-sushi-tsukiji"
    static let ticketId = "demo-ticket"

    static func ensure(context: ModelContext, region: Region) {
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let list: MustList
        if let found = lists.first(where: { $0.id == "demo-do" }) {
            list = found
        } else {
            list = MustList(id: "demo-do", name: "do", kanji: "体験", icon: .mustsLista, color: .night, order: 99, kind: .experience)
            context.insert(list)
        }
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        if places.contains(where: { $0.id == placeId }) { return }

        let dates = BoardDates(timeZone: region.timeZone)
        let day = dates.day(from: "2026-11-15") ?? AppClock.now
        let place = Place(id: placeId, name: "Aula de sushi com chef em Tsukiji", cityId: "tokyo1", lat: 35.6654, lng: 139.7707)
        place.nameLocal = "築地 寿司教室"
        place.list = list
        place.area = "Tsukiji"
        place.price = 12_000
        place.allowBudgetException = true
        place.extra = PlaceExtra(experience: ExperienceInfo(
            supplier: .viator, url: URL(string: "https://www.viator.com/"), durationMinutes: 180, priceFrom: 12_000, currency: "JPY",
            rating: 4.9, reviewCount: 1240, meetingPoint: "Portão 1 do Mercado Externo de Tsukiji 築地",
            meetingLat: 35.6654, meetingLng: 139.7707, languages: ["inglês"], groupMax: 8, freeCancellationHours: 24))
        place.tickets = [Ticket(id: ticketId, at: dates.time("10:00", on: day) ?? day, confirmation: "BR-7K2M-9931",
                                qrPayload: "BR-7K2M-9931", paid: 24_000, people: 2,
                                cancelUntil: dates.time("10:00", on: dates.day(from: "2026-11-13") ?? day))]
        context.insert(place)
        try? context.save()
    }
}
#endif
