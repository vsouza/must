import CoreLocation
import Foundation
import OSLog
import SwiftData

/// O fluxo Nova viagem (prompt 28, telas NovaViagem1…9) entrega um `NewTripDraft`; aqui ele vira viagem (§4):
/// registro (`trips.json`), container novo `must-<slug>-<4 letras>.store` com cidades, hospedagem, voos, lugares,
/// orçamento e câmbio, e a troca pra viagem nova quando a folha do fluxo fecha (o passo 9 ainda mostra "Pronto").
@MainActor
struct StoreTripCreator: TripCreating {
    let store: RegionStore

    func create(_ draft: NewTripDraft) async throws -> String {
        try store.create(draft).id
    }

    func existingCountryCodes() -> Set<String> {
        Set(store.trips.filter { $0.kind != .home }.map { $0.countryCode.uppercased() })
    }
}

enum NewTripError: LocalizedError {
    case noDestination

    var errorDescription: String? { "Falta o destino (passo 1)." }
}

/// Rascunho → `Trip` e conteúdo do container. Puro o bastante pra testar com um container em memória.
@MainActor
enum NewTripWriter {
    /// A viagem do registro. `start`/`end` do rascunho são a meia-noite UTC do dia escolhido no calendário.
    static func trip(from draft: NewTripDraft, taken: Set<TripID>, now: Date = AppClock.now) throws -> Trip {
        let code = draft.countryCode.uppercased()
        guard !code.isEmpty || !draft.name.isEmpty else { throw NewTripError.noDestination }
        let profile = CountryProfile.forCountry(code.isEmpty ? "ZZ" : code,
                                                currency: draft.currency.isEmpty ? nil : draft.currency,
                                                timeZone: draft.timeZoneId.isEmpty ? nil : draft.timeZoneId)
        let name = draft.name.isEmpty ? profile.name : draft.name
        let tz = draft.timeZoneId.isEmpty ? profile.timeZone : draft.timeZoneId
        let utc = BoardDates(timeZone: .gmt)
        let days = cityDays(draft)
        let cities = draft.cities.map { c -> Trip.TripCity in
            let (lat, lng) = coordinate(c)
            return Trip.TripCity(id: c.id, name: c.name, lat: lat, lng: lng, from: days[c.id]?.from, to: days[c.id]?.to,
                                 tz: c.timeZoneId ?? tz)
        }
        let first = draft.cities.first
        let home = first.flatMap { c -> Trip.TripHome? in
            guard c.lodgingName != nil || c.neighborhoodOnly != nil || c.lodgingAddress != nil else { return nil }
            return Trip.TripHome(name: c.lodgingName, address: c.lodgingAddress, lat: c.lodgingLatitude, lng: c.lodgingLongitude,
                                 neighborhood: c.neighborhoodOnly)
        }
        return Trip(id: Trip.newID(name: name, taken: taken), name: name, shortName: nil, countryCode: code.isEmpty ? "ZZ" : code,
                    currency: draft.currency.isEmpty ? profile.currency : draft.currency, timeZone: tz,
                    colorHex: draft.colorHex.isEmpty ? nil : draft.colorHex, kind: .trip,
                    start: draft.start.map(utc.dayString), end: draft.end.map(utc.dayString),
                    cities: cities, home: home, createdAt: now, archived: false, seedId: nil)
    }

    /// Cidade digitada à mão pode vir em (0, 0): "sem coordenada" — usa a hospedagem se houver; senão fica 0/0 e a
    /// sincronização resolve depois (TODO(p28:F0): resolver o centro da cidade no Places/geocoder na primeira sync).
    static func coordinate(_ c: NewTripDraft.City) -> (Double, Double) {
        if c.latitude != 0 || c.longitude != 0 { return (c.latitude, c.longitude) }
        if let lat = c.lodgingLatitude, let lng = c.lodgingLongitude { return (lat, lng) }
        return (0, 0)
    }

    /// Noites em sequência a partir do início ("yyyy-MM-dd" de entrada e saída de cada cidade). Sem datas: nada.
    static func cityDays(_ draft: NewTripDraft) -> [String: (from: String, to: String)] {
        guard let start = draft.start else { return [:] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let utc = BoardDates(timeZone: .gmt)
        var cursor = cal.startOfDay(for: start)
        var out: [String: (String, String)] = [:]
        for c in draft.cities {
            let next = cal.date(byAdding: .day, value: max(0, c.nights), to: cursor) ?? cursor
            out[c.id] = (utc.dayString(cursor), utc.dayString(next))
            cursor = next
        }
        return out
    }

    /// Grava no container novo (vazio) da viagem: datas, cidades com hospedagem, orçamento, câmbio, voos e lugares.
    static func fill(_ context: ModelContext, trip: Trip, draft: NewTripDraft, now: Date = AppClock.now) throws {
        let region = Region(trip: trip)
        let dates = BoardDates(timeZone: region.timeZone)
        let info = context.tripInfo()
        info.start = trip.start.flatMap(dates.day(from:))
        info.end = trip.end.flatMap(dates.day(from:))
        info.home = trip.home?.name ?? trip.home?.neighborhood
        let byId = Dictionary(draft.cities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        info.cities = trip.cities.map { c in
            let d = byId[c.id]
            let lodging = d.flatMap { d -> CityLodging? in
                guard d.lodgingName != nil || d.lodgingAddress != nil || d.neighborhoodOnly != nil else { return nil }
                return CityLodging(name: d.lodgingName, address: d.lodgingAddress, lat: d.lodgingLatitude, lng: d.lodgingLongitude,
                                   neighborhood: d.neighborhoodOnly, checkIn: d.checkIn, checkOut: d.checkOut,
                                   fromEmail: d.lodgingFromEmail ? true : nil)
            }
            return City(id: c.id, name: c.name, from: c.from.flatMap(dates.day(from:)), to: c.to.flatMap(dates.day(from:)),
                        tz: c.tz ?? trip.timeZone, currency: trip.currency, lat: c.lat, lng: c.lng, lodging: lodging)
        }

        let settings = context.settings(for: region)
        if let perDay = draft.perDayBudget, perDay > 0 { settings.perDayBudget = perDay }
        if let fx = draft.fxRate, fx > 0 {
            settings.fxRate = fx
            settings.fxDate = now
        }

        for (i, f) in draft.flights.enumerated() {
            guard let departs = f.departure ?? info.start else { continue }
            let leg = FlightSegment(number: f.number, from: f.from.uppercased(), to: f.to.uppercased(), departs: departs, arrives: f.arrival)
            let template = FlightRules.templateKey(for: [leg])
            context.insert(Flight(template: template, legs: [leg], checklist: ChecklistTemplates.items(template: template, legs: [leg]),
                                  order: i, createdAt: now))
        }

        // Listas sempre (o board nasce com as mesmas listas das de fábrica); lugares só os conferidos.
        let board = Board(version: Board.currentVersion, region: region, trip: nil, budget: nil, lists: listTemplate,
                          places: places(draft, trip: trip, now: now), expenses: nil, days: nil, events: nil)
        try BoardCodec(context: context, region: region).import(board: board)
        try context.save()
    }

    /// Lugares conferidos no passo 6. Sem `placeId` (a sincronização normal resolve); sem coordenada, o centro da
    /// cidade marcado como aproximado.
    static func places(_ draft: NewTripDraft, trip: Trip, now: Date) -> [BoardPlace] {
        let listIds = Set(listTemplate.map(\.id))
        let firstCity = trip.cities.first
        let savedAt = BoardDates(timeZone: trip.tz).dayString(now)
        return draft.places.enumerated().map { i, p in
            let city = p.cityId.flatMap { id in trip.cities.first { $0.id == id } } ?? firstCity
            let hasCoordinate = p.latitude != nil && p.longitude != nil && (p.latitude != 0 || p.longitude != 0)
            let list = p.listId.map { $0 == "coffee" ? "drink" : $0 }.flatMap { listIds.contains($0) ? $0 : nil } ?? "see"
            return BoardPlace(id: "n\(i + 1)-\(UUID().uuidString.prefix(6).lowercased())", name: p.name, nameLocal: nil, listId: list,
                              sub: nil, cityId: city?.id ?? "", area: nil,
                              lat: hasCoordinate ? p.latitude : city?.lat, lng: hasCoordinate ? p.longitude : city?.lng,
                              approx: hasCoordinate ? nil : true, placeId: p.googlePlaceId, price: nil, priceLevel: nil,
                              hours: nil, window: nil, reservation: nil, saveForEnd: nil, allowBudgetException: nil,
                              queueMinutes: nil, notes: p.note, source: Source(kind: .manual, url: nil, savedAt: savedAt),
                              done: nil, extra: nil, order: i, tickets: nil)
        }
    }

    /// As listas de uma viagem nova (as mesmas das de fábrica, sem kanji e com sub-listas genéricas).
    static let listTemplate: [BoardList] = [
        BoardList(id: "eat", name: "eat", kanji: nil, icon: "ramen", color: .eat, photo: nil, sub: ["Restaurante", "Street food", "Mercado", "Doces"], kind: nil),
        BoardList(id: "drink", name: "drink", kanji: nil, icon: "coquetel", color: .drink, photo: nil, sub: ["Café", "Bar", "Vinho"], kind: nil),
        BoardList(id: "see", name: "see", kanji: nil, icon: "templo-torii", color: .temple, photo: nil, sub: ["Monumento", "Mirante", "Praça", "Parque"], kind: nil),
        BoardList(id: "art", name: "art", kanji: nil, icon: "arte-galeria", color: .art, photo: nil, sub: ["Museu", "Igreja", "Galeria"], kind: .art),
        BoardList(id: "photo", name: "photo", kanji: nil, icon: "camera-foto", color: .photo, photo: nil, sub: ["Mirante", "Rua", "Arquitetura"], kind: .photo),
        BoardList(id: "shop", name: "shop", kanji: nil, icon: "compras", color: .shop, photo: nil, sub: nil, kind: nil),
        BoardList(id: "listen", name: "listen", kanji: nil, icon: "musica-ao-vivo", color: .listen, photo: nil, sub: nil, kind: nil),
        BoardList(id: "do", name: "do", kanji: nil, icon: "reserva-ancora", color: .night, photo: nil, sub: ["Aula", "Tour", "Passeio"], kind: .experience),
    ]
}
