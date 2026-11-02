#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen experiencias`: experiências de exemplo na Must do e um jantar reservado às 19:00 que conflita com uma delas.
/// Só cria o que não existe (ids `demo-…`); o resto do board não é tocado.
@MainActor
enum ExperienceDemo {
    static func ensure(context: ModelContext, region: Region) {
        TicketDemo.ensure(context: context, region: region)
        let existing = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        guard !existing.contains(where: { $0.id == "demo-exp-teamlab" }) else { return }

        let list = ExperienceStore.list(in: context)
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let dates = BoardDates(timeZone: region.timeZone)
        let day = dates.day(from: "2026-11-15") ?? AppClock.now
        let nextDay = dates.day(from: "2026-11-16") ?? day
        let cityId = region == .jp ? "tokyo1" : "bh"
        func at(_ hhmm: String, _ date: Date) -> Date { dates.time(hhmm, on: date) ?? date }

        let udatsu = Place(id: "demo-udatsu", name: "Udatsu", cityId: cityId, lat: 35.6700, lng: 139.7560)
        udatsu.list = lists.first { $0.id == "eat" }
        udatsu.reservation = Reservation(at: at("19:00", day), party: 2)
        context.insert(udatsu)

        func experience(_ id: String, _ name: String, lat: Double, lng: Double, order: Int, info: ExperienceInfo) {
            let place = Place(id: id, name: name, cityId: cityId, lat: lat, lng: lng)
            place.list = list
            place.order = order
            place.approx = true
            place.extra = PlaceExtra(experience: info)
            context.insert(place)
        }
        experience("demo-exp-teamlab", "teamLab Borderless · ingresso com hora", lat: 35.6605, lng: 139.7414, order: 1, info: ExperienceInfo(
            supplier: .klook, url: URL(string: "https://www.klook.com/"), durationMinutes: 120, priceFrom: 3_200, currency: "JPY",
            rating: 4.8, reviewCount: 4_800, meetingPoint: "Azabudai Hills", languages: ["inglês"], freeCancellationHours: 24,
            sessions: [EventSession(at: at("14:00", day), title: "entrada 14:00–14:30", bought: true)]))
        experience("demo-exp-izakaya", "Tour de izakayas em Shinjuku, à noite", lat: 35.6938, lng: 139.7034, order: 2, info: ExperienceInfo(
            supplier: .getYourGuide, url: URL(string: "https://www.getyourguide.com.br/"), durationMinutes: 180, priceFrom: 9_800,
            currency: "JPY", rating: 4.7, reviewCount: 890, languages: ["inglês"], groupMax: 10,
            sessions: [EventSession(at: at("19:30", day), title: "saída 19:30")]))
        experience("demo-exp-photowalk", "Photowalk analógico em Yanaka", lat: 35.7270, lng: 139.7700, order: 3, info: ExperienceInfo(
            supplier: .airbnb, url: URL(string: "https://www.airbnb.com.br/"), durationMinutes: 150, priceFrom: 6_500, currency: "JPY",
            rating: 4.9, languages: ["inglês"], sessions: [EventSession(at: at("15:00", nextDay), title: "encontro 15:00")]))
        try? context.save()
    }
}
#endif
