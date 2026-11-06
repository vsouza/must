import Foundation

/// Eventos de mentira pros prints (`-debugEvents fake`): nada de rede, nada de chave.
enum EventsFakes {
    static func events(region: Region, now: Date) -> [ShowEvent] {
        let calendar = region.calendar
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }
        switch region {
        case .bh:
            return [ShowEvent(id: "bandsintown:fake-bh-1", placeId: nil, kind: .show, title: "Noite Belga", venue: "Bar do Lourdes",
                              lat: -19.9335, lng: -43.9385, startsAt: at(20), runsUntil: nil, sessions: [], priceText: "R$ 30",
                              url: nil, source: .bandsintown, checkedAt: now)]
        case .jp:
            return [ShowEvent(id: "feed:tokyocheapo:fake-jp-1", placeId: nil, kind: .show, title: "Shibuya Anime Music Night",
                              venue: "Shibuya", lat: 35.6595, lng: 139.7005, startsAt: at(19), runsUntil: nil, sessions: [],
                              priceText: "¥ 2.500", url: nil, source: .feed, checkedAt: now)]
        case .it:
            return [ShowEvent(id: "ticketmaster:fake-it-1", placeId: nil, kind: .show, title: "Jazz a Trastevere", venue: "Trastevere",
                              lat: 41.8897, lng: 12.4695, startsAt: at(21), runsUntil: nil, sessions: [], priceText: "€ 15",
                              url: nil, source: .ticketmaster, checkedAt: now)]
        default:
            // Viagem criada no app: os fakes são só das de fábrica.
            return []
        }
    }
}
