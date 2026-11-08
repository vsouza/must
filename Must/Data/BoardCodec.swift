import Foundation
import OSLog
import SwiftData

enum BoardError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case wrongRegion(file: Region, current: Region)
    case unknownList(place: String, list: String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            "Esse board é da versão \(v); o Must lê as versões 1 e 2."
        case .wrongRegion(let file, let current):
            "Esse board é de \(file.displayName), mas a viagem aberta é \(current.displayName). Troque de viagem (Minhas viagens) antes de importar."
        case .unknownList(let place, let list):
            "O lugar “\(place)” aponta pra lista “\(list)”, que não existe no arquivo nem no board."
        case .unreadable(let detail):
            "Não consegui ler o arquivo: \(detail)"
        }
    }
}

/// O que um import mudou.
struct ImportSummary: Equatable, Sendable {
    var listsInserted = 0
    var listsUpdated = 0
    var placesInserted = 0
    var placesUpdated = 0
    var citiesCreated: [String] = []
    var expensesInserted = 0
    var daysUpserted = 0

    var description: String {
        var parts: [String] = []
        if placesInserted > 0 { parts.append("+\(placesInserted) lugares") }
        if placesUpdated > 0 { parts.append("\(placesUpdated) atualizados") }
        if listsInserted > 0 { parts.append("+\(listsInserted) listas") }
        if !citiesCreated.isEmpty { parts.append("cidades criadas: \(citiesCreated.joined(separator: ", "))") }
        if expensesInserted > 0 { parts.append("+\(expensesInserted) gastos") }
        if daysUpserted > 0 { parts.append("\(daysUpserted) dias") }
        return parts.isEmpty ? "nada mudou" : parts.joined(separator: " · ")
    }
}

/// Board (JSON) ↔ modelos SwiftData de uma região.
@MainActor
struct BoardCodec {
    let context: ModelContext
    let region: Region

    private var dates: BoardDates { BoardDates(timeZone: region.timeZone) }

    // MARK: JSON

    nonisolated static func decode(_ data: Data) throws -> Board {
        do {
            return try JSONDecoder.board.decode(Board.self, from: data)
        } catch let error as DecodingError {
            throw BoardError.unreadable(Self.describe(error))
        }
    }

    nonisolated static func encode(_ board: Board) throws -> Data {
        let tz: TimeZone = board.region.timeZone
        return try JSONEncoder.board(timeZone: tz).encode(board)
    }

    nonisolated private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let ctx):
            "falta “\(key.stringValue)” em \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            "\(ctx.debugDescription) (\(ctx.codingPath.map(\.stringValue).joined(separator: ".")))"
        @unknown default:
            error.localizedDescription
        }
    }

    // MARK: Import

    /// Upsert por `id`, sem apagar nada que já existe.
    /// - `merge: true`: o que o arquivo traz como nulo (placeId, horários, feito…) não apaga o cache local.
    /// - `merge: false`: os campos do arquivo substituem os do aparelho.
    @discardableResult
    func `import`(board: Board, merge: Bool = true) throws -> ImportSummary {
        guard Board.readableVersions.contains(board.version) else { throw BoardError.unsupportedVersion(board.version) }
        guard board.region == region else { throw BoardError.wrongRegion(file: board.region, current: region) }

        var summary = ImportSummary()
        let existingLists = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<MustList>()).map { ($0.id, $0) })
        let existingPlaces = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Place>()).map { ($0.id, $0) })

        // Valida antes de mexer em qualquer coisa.
        let fileListIds = Set(board.lists.map(\.id))
        for place in board.places where !fileListIds.contains(place.listId) && existingLists[place.listId] == nil {
            throw BoardError.unknownList(place: place.name, list: place.listId)
        }

        importTrip(board.trip)
        importBudget(board.budget)

        // Listas
        var lists = existingLists
        let nextOrder = (existingLists.values.map(\.order).max() ?? -1) + 1
        for (index, item) in board.lists.enumerated() {
            let icon = item.icon.flatMap(MustIcon.init(rawValue:)) ?? .mustsLista
            if let list = lists[item.id] {
                list.name = item.name
                list.color = item.color
                if item.icon != nil || !merge { list.icon = icon }
                if item.kanji != nil || !merge { list.kanji = item.kanji }
                if item.photo != nil || !merge { list.photo = item.photo }
                if item.sub != nil || !merge { list.subs = item.sub ?? [] }
                if item.kind != nil || !merge { list.kind = item.kind ?? .place }
                summary.listsUpdated += 1
            } else {
                let list = MustList(id: item.id, name: item.name, kanji: item.kanji, icon: icon, color: item.color,
                                    photo: item.photo, subs: item.sub ?? [], order: existingLists.isEmpty ? index : nextOrder + index,
                                    kind: item.kind ?? .place)
                context.insert(list)
                lists[item.id] = list
                summary.listsInserted += 1
            }
        }

        // Cidades conhecidas (as que faltarem são criadas).
        let trip = context.tripInfo()
        var cities = trip.cities

        // Lugares
        var places = existingPlaces
        for item in board.places {
            if !cities.contains(where: { $0.id == item.cityId }) {
                cities.append(City(id: item.cityId, name: Self.cityName(from: item.cityId), from: nil, to: nil,
                                   tz: region.timeZone.identifier, currency: region.currency,
                                   lat: item.lat ?? region.defaultCenter.latitude, lng: item.lng ?? region.defaultCenter.longitude))
                summary.citiesCreated.append(item.cityId)
            }

            let place: Place
            if let existing = places[item.id] {
                place = existing
                summary.placesUpdated += 1
            } else {
                place = Place(id: item.id, name: item.name, cityId: item.cityId)
                context.insert(place)
                places[item.id] = place
                summary.placesInserted += 1
            }
            apply(item, to: place, list: lists[item.listId], merge: merge)
        }
        if !summary.citiesCreated.isEmpty { trip.cities = cities }

        summary.expensesInserted = try importExpenses(board.expenses ?? [], places: places)
        summary.daysUpserted = try importDays(board.days ?? [], places: places)
        try importEvents(board.events ?? [])
        try importFlights(board.flights ?? [])
        try importGifts(board.gifts ?? [])

        try context.save()
        Log.data.info("import \(region.rawValue): \(summary.description, privacy: .public)")
        return summary
    }

    private func apply(_ item: BoardPlace, to place: Place, list: MustList?, merge: Bool) {
        place.name = item.name
        place.list = list
        place.cityId = item.cityId
        place.windows = item.window ?? (merge ? place.windows : [])
        place.saveForEnd = item.saveForEnd ?? (merge ? place.saveForEnd : false)
        place.allowBudgetException = item.allowBudgetException ?? (merge ? place.allowBudgetException : false)
        place.notes = item.notes ?? (merge ? place.notes : "")

        func pick<T>(_ new: T?, _ old: T?) -> T? { merge ? (new ?? old) : new }
        place.nameLocal = pick(item.nameLocal, place.nameLocal)
        place.sub = pick(item.sub, place.sub)
        place.area = pick(item.area, place.area)
        place.price = pick(item.price, place.price)
        place.priceLevel = pick(item.priceLevel, place.priceLevel)
        place.queueMinutes = pick(item.queueMinutes, place.queueMinutes)
        place.reservation = pick(item.reservation, place.reservation)
        place.source = pick(item.source, place.source)
        place.done = pick(item.done, place.done)
        place.placeId = pick(item.placeId, place.placeId)
        if item.hours != nil || !merge { place.hours = item.hours }
        if item.extra != nil || !merge { place.extra = item.extra }
        if item.tickets != nil || !merge { place.tickets = item.tickets ?? [] }
        place.order = item.order ?? (merge ? place.order : 0)

        // Coordenada resolvida no aparelho não volta a ser chute.
        let localIsResolved = !place.approx && place.placeId != nil
        if let lat = item.lat, let lng = item.lng, !(merge && localIsResolved && item.approx == true) {
            place.lat = lat
            place.lng = lng
            place.approx = item.approx ?? false
        }
    }

    private func importTrip(_ item: BoardTrip?) {
        guard let item else { return }
        let trip = context.tripInfo()
        let d = dates
        if let start = item.start { trip.start = d.day(from: start) }
        if let end = item.end { trip.end = d.day(from: end) }
        if let home = item.home { trip.home = home }
        guard let incoming = item.cities else { return }
        var cities = trip.cities
        for c in incoming {
            let city = City(id: c.id, name: c.name, from: c.from.flatMap(d.day(from:)), to: c.to.flatMap(d.day(from:)),
                            tz: c.tz ?? region.timeZone.identifier, currency: c.currency ?? region.currency,
                            lat: c.lat ?? region.defaultCenter.latitude, lng: c.lng ?? region.defaultCenter.longitude)
            if let i = cities.firstIndex(where: { $0.id == c.id }) { cities[i] = city } else { cities.append(city) }
        }
        trip.cities = cities
    }

    private func importBudget(_ item: BoardBudget?) {
        let settings = context.settings(for: region)
        guard let item else { return }
        if let perDay = item.perDay { settings.perDayBudget = perDay }
        if let walk = item.walkMaxKm { settings.walkMaxKm = walk }
        if let start = item.dayStart { settings.dayStart = start }
    }

    /// Gastos não têm id no schema: dedupe por (instante, valor, lugar).
    private func importExpenses(_ items: [BoardExpense], places: [String: Place]) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<Expense>())
        var keys = Set(existing.map { Self.expenseKey(at: $0.at, amount: $0.amount, placeId: $0.place?.id) })
        var inserted = 0
        for item in items {
            let key = Self.expenseKey(at: item.at, amount: item.amount, placeId: item.placeId)
            guard !keys.contains(key) else { continue }
            context.insert(Expense(at: item.at, amount: item.amount, category: item.category ?? .other,
                                   place: item.placeId.flatMap { places[$0] }, method: item.method ?? .card))
            keys.insert(key)
            inserted += 1
        }
        return inserted
    }

    private static func expenseKey(at: Date, amount: Double, placeId: String?) -> String {
        "\(Int(at.timeIntervalSince1970))|\(amount)|\(placeId ?? "-")"
    }

    /// Dias: upsert pela data; as paradas do arquivo substituem as do dia.
    private func importDays(_ items: [BoardDay], places: [String: Place]) throws -> Int {
        let d = dates
        let existing = try context.fetch(FetchDescriptor<PlannedDay>())
        var byDate = Dictionary(uniqueKeysWithValues: existing.map { ($0.date, $0) })
        var count = 0
        for item in items {
            guard let date = d.day(from: item.date) else { continue }
            let day: PlannedDay
            if let found = byDate[date] {
                day = found
                if let kind = item.kind { day.kind = kind }
                if let budget = item.budget { day.budget = budget }
                if let walk = item.walk { day.walk = walk }
                if let accepted = item.accepted { day.accepted = accepted }
            } else {
                day = PlannedDay(date: date, kind: item.kind ?? .free, budget: item.budget ?? context.settings(for: region).perDayBudget,
                                 walk: item.walk ?? .normal, accepted: item.accepted ?? true)
                context.insert(day)
                byDate[date] = day
            }
            if let stops = item.stops {
                for old in day.stops { context.delete(old) }
                day.stops = []
                for (i, s) in stops.enumerated() {
                    let at = s.at.flatMap { d.time($0, on: date) } ?? date
                    let stop = Stop(place: places[s.placeId], at: at, order: i, done: s.done ?? false)
                    context.insert(stop)
                    day.stops.append(stop)
                }
            }
            count += 1
        }
        return count
    }

    /// Eventos: dedupe por (instante, título). `kind: flight` não vira evento: vai pras reservas de voo (prompt 15 · C).
    private func importEvents(_ items: [BoardEvent]) throws {
        let existing = try context.fetch(FetchDescriptor<TripEvent>())
        var keys = Set(existing.map { "\(Int($0.at.timeIntervalSince1970))|\($0.title)" })
        for item in items where item.kind != .flight {
            let key = "\(Int(item.at.timeIntervalSince1970))|\(item.title)"
            guard keys.insert(key).inserted else { continue }
            context.insert(TripEvent(at: item.at, title: item.title, kind: item.kind ?? .event, note: item.note ?? "",
                                     allDay: item.allDay ?? false, weatherDependent: item.weatherDependent ?? false))
        }
        // Voo no formato antigo (evento "LA3553 · BH → São Paulo"): trechos soltos, agrupados em reservas.
        let legacy = items.filter { $0.kind == .flight }.map { FlightRules.legacyLeg(title: $0.title, at: $0.at, note: $0.note) }
        for chain in FlightChains.bookings(from: legacy) {
            try insertFlight(pnr: nil, legs: chain, checkedKg: nil, cabinKg: nil, template: nil, checklist: nil)
        }
    }

    /// Presentes (`gifts`, v3). Id que já existe é atualizado; id novo entra. Gasto não é recriado (o export de `expenses` já o traz).
    private func importGifts(_ items: [BoardGift]) throws {
        let known = Dictionary(try context.fetch(FetchDescriptor<Gift>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in items {
            let gift: Gift
            if let existing = known[item.id] {
                gift = existing
            } else {
                gift = Gift(id: item.id, title: item.title)
                context.insert(gift)
            }
            gift.title = item.title
            gift.person = item.person ?? ""
            gift.quantity = max(1, item.quantity ?? 1)
            gift.estimatedPrice = item.estimatedPrice ?? 0
            gift.paidPrice = item.paidPrice
            gift.boughtAt = item.boughtAt
            gift.sourceRaw = item.source ?? GiftSource.name.rawValue
            gift.sourceURL = item.sourceURL
            gift.sourceLabel = item.sourceLabel ?? ""
            gift.videoClip = item.videoClip
            gift.placeId = item.placeId
            gift.storeName = item.storeName ?? ""
            gift.storeLat = item.storeLat
            gift.storeLng = item.storeLng
            gift.storeAddress = item.storeAddress ?? ""
            gift.chain = item.chain ?? false
            gift.note = item.note ?? ""
            gift.order = item.order ?? 0
        }
    }

    /// Reservas de voo do board (`flights`). Dedupe pelo primeiro trecho (número + partida).
    private func importFlights(_ items: [BoardFlight]) throws {
        for item in items where !item.legs.isEmpty {
            let legs = item.legs.map { leg in
                FlightSegment(number: leg.number, from: leg.from, to: leg.to, departs: leg.departs, arrives: leg.arrives,
                          seat: leg.seat, terminal: leg.terminal, gate: leg.gate, note: leg.note)
            }
            try insertFlight(pnr: item.pnr, legs: legs, checkedKg: item.checkedKg, cabinKg: item.cabinKg,
                             template: item.template, checklist: item.checklist, carrier: item.carrier)
        }
    }

    /// Grava uma reserva se o primeiro trecho ainda não está no banco. Sem checklist no arquivo, usa o modelo.
    @discardableResult
    func insertFlight(pnr: String?, legs: [FlightSegment], checkedKg: Int?, cabinKg: Int?, template: String?,
                      checklist: [ChecklistItem]?, carrier: String? = nil) throws -> Bool {
        guard let first = legs.first else { return false }
        let known = try context.fetch(FetchDescriptor<Flight>())
        let duplicate = known.contains { flight in
            guard let existing = flight.firstLeg else { return false }
            return existing.number == first.number && abs(existing.departs.timeIntervalSince(first.departs)) < 60
        }
        guard !duplicate else { return false }
        let key = template ?? FlightRules.templateKey(for: legs)
        let items = checklist ?? ChecklistTemplates.items(template: key, legs: legs)
        let order = known.count
        context.insert(Flight(pnr: pnr ?? "", carrier: carrier ?? FlightRules.carrierName(FlightRules.carrierCode(of: first.number)),
                              template: key, checkedKg: checkedKg, cabinKg: cabinKg, legs: legs, checklist: items, order: order))
        return true
    }

    /// Board antigo: os voos que estavam como evento (`TripEvent` kind flight) viram reservas, sem perder nada.
    /// Roda a cada abertura; sem voo antigo, não faz nada.
    func migrateFlightEvents() throws {
        let events = try context.fetch(FetchDescriptor<TripEvent>()).filter { $0.kind == .flight }
        guard !events.isEmpty else { return }
        let legs = events.map { FlightRules.legacyLeg(title: $0.title, at: $0.at, note: $0.note.isEmpty ? nil : $0.note) }
        for chain in FlightChains.bookings(from: legs) {
            try insertFlight(pnr: nil, legs: chain, checkedKg: nil, cabinKg: nil, template: nil, checklist: nil)
        }
        events.forEach(context.delete)
        try context.save()
        Log.data.info("\(events.count, privacy: .public) voo(s) do board antigo viraram reservas")
    }

    static func cityName(from id: String) -> String {
        let letters = id.trimmingCharacters(in: .decimalDigits)
        return letters.prefix(1).uppercased() + letters.dropFirst()
    }

    // MARK: Export

    func export() throws -> Board {
        let d = dates
        let settings = context.settings(for: region)
        let trip = try context.fetch(FetchDescriptor<TripInfo>()).first
        let lists = try context.fetch(FetchDescriptor<MustList>(sortBy: [SortDescriptor(\.order), SortDescriptor(\.id)]))
        let places = try context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.id)]))
        let expenses = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.at)]))
        let days = try context.fetch(FetchDescriptor<PlannedDay>(sortBy: [SortDescriptor(\.date)]))
        let events = try context.fetch(FetchDescriptor<TripEvent>(sortBy: [SortDescriptor(\.at), SortDescriptor(\.title)]))
        let flights = context.flights()
        let gifts = context.gifts()

        let boardTrip = trip.map { t in
            BoardTrip(start: t.start.map(d.dayString), end: t.end.map(d.dayString), home: t.home,
                      cities: t.cities.map { c in
                          BoardCity(id: c.id, name: c.name, from: c.from.map(d.dayString), to: c.to.map(d.dayString),
                                    tz: c.tz, currency: c.currency, lat: c.lat, lng: c.lng)
                      })
        }

        return Board(
            version: Board.currentVersion,
            region: region,
            trip: boardTrip,
            budget: BoardBudget(perDay: settings.perDayBudget, currency: region.currency,
                                walkMaxKm: settings.walkMaxKm, dayStart: settings.dayStart),
            lists: lists.map { l in
                BoardList(id: l.id, name: l.name, kanji: l.kanji, icon: l.iconRaw, color: l.color, photo: l.photo,
                          sub: l.subs.isEmpty ? nil : l.subs, kind: l.kind == .place ? nil : l.kind)
            },
            places: places.map { p in
                BoardPlace(id: p.id, name: p.name, nameLocal: p.nameLocal, listId: p.list?.id ?? "", sub: p.sub,
                           cityId: p.cityId, area: p.area, lat: p.lat, lng: p.lng, approx: p.approx, placeId: p.placeId,
                           price: p.price, priceLevel: p.priceLevel, hours: p.hours, window: p.windows,
                           reservation: p.reservation, saveForEnd: p.saveForEnd, allowBudgetException: p.allowBudgetException,
                           queueMinutes: p.queueMinutes, notes: p.notes, source: p.source, done: p.done, extra: p.extra,
                           order: p.order, tickets: p.tickets.isEmpty ? nil : p.tickets)
            },
            expenses: expenses.map { e in
                BoardExpense(at: e.at, amount: e.amount, category: e.category, placeId: e.place?.id, method: e.method)
            },
            days: days.map { day in
                BoardDay(date: d.dayString(day.date), kind: day.kind, budget: day.budget, walk: day.walk,
                         stops: day.orderedStops.compactMap { s in
                             s.place.map { BoardStop(placeId: $0.id, at: d.timeString(s.at), done: s.done) }
                         },
                         accepted: day.accepted)
            },
            events: events.filter { $0.kind != .flight }.map { e in
                BoardEvent(at: e.at, title: e.title, kind: e.kind, note: e.note.isEmpty ? nil : e.note,
                           allDay: e.allDay, weatherDependent: e.weatherDependent)
            },
            flights: flights.map { f in
                BoardFlight(pnr: f.pnr.isEmpty ? nil : f.pnr, carrier: f.carrier.isEmpty ? nil : f.carrier,
                            template: f.template.isEmpty ? nil : f.template, checkedKg: f.checkedKg, cabinKg: f.cabinKg,
                            legs: f.legs.map { l in
                                BoardFlightLeg(number: l.number, from: l.from, to: l.to, departs: l.departs, arrives: l.arrives,
                                               seat: l.seat, terminal: l.terminal, gate: l.gate, note: l.note)
                            },
                            checklist: f.checklist.isEmpty ? nil : f.checklist)
            },
            gifts: gifts.isEmpty ? nil : gifts.map { g in
                BoardGift(id: g.id, title: g.title, person: g.person.isEmpty ? nil : g.person, quantity: g.quantity,
                          estimatedPrice: g.estimatedPrice, paidPrice: g.paidPrice, boughtAt: g.boughtAt,
                          source: g.sourceRaw, sourceURL: g.sourceURL, sourceLabel: g.sourceLabel.isEmpty ? nil : g.sourceLabel,
                          videoClip: g.videoClip, placeId: g.placeId, storeName: g.storeName.isEmpty ? nil : g.storeName,
                          storeLat: g.storeLat, storeLng: g.storeLng, storeAddress: g.storeAddress.isEmpty ? nil : g.storeAddress, chain: g.chain ? true : nil,
                          note: g.note.isEmpty ? nil : g.note, order: g.order)
            }
        )
    }

    /// "must-bh-2026-10-31.json"
    func exportFileName(on date: Date = AppClock.now) -> String {
        "must-\(region.rawValue)-\(dates.dayString(date)).json"
    }
}
