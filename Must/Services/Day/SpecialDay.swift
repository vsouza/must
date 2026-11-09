import Foundation
import SwiftData

/// Dias especiais em Hoje (relatório do viajante, problema 7): chegada, troca de cidade e último dia, com o essencial de
/// cada um. Regra determinística sobre dados que já existem (voos, datas e hospedagem por cidade, reservas de trem, "fica pro
/// fim"); **o que não existe não aparece** (nada de palpite). O tipo do dia vem de `DayProblem.detect`, que a capa e o Bom dia
/// já usam, então todo mundo concorda sobre que dia é hoje.
struct SpecialDay: Equatable, Sendable {
    typealias Kind = DayProblem.Kind

    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        /// SF Symbol.
        var icon: String
        var title: String
        var detail: String?
        var done: Bool = false
    }

    /// Reserva de trem (ou outro transporte com hora) que cai no dia.
    struct Train: Equatable, Sendable {
        var name: String
        var at: Date
        var detail: String?
    }

    /// O que o dia precisa saber (tudo já lido do container, nada de SwiftData aqui).
    struct Inputs: Sendable {
        var cities: [City] = []
        var legs: [FlightSegment] = []
        var tripEnd: Date?
        /// Nomes dos Musts "fica pro fim" que ainda faltam.
        var saveForEnd: [String] = []
        /// Itens da fase "ao pousar" do voo de chegada (checklist).
        var arrivalChecklist: [ChecklistItem] = []
        var trains: [Train] = []
        /// O país tem cartão de tax-free no Bolso.
        var taxFree: Bool = false
    }

    var kind: Kind
    /// "Chegada" · "Troca de cidade" · "Último dia".
    var title: String
    /// A linha do `DayProblem` (a mesma da capa e do Bom dia).
    var headline: String
    var items: [Item]
    /// Dia leve: não montar nada pesado.
    var light: Bool
    /// Último dia com voo hoje: a hora de sair pro aeroporto.
    var leaveAt: Date?
    /// Nome da cidade onde o dia acontece (troca de cidade: a de destino).
    var cityName: String?

    // MARK: Detecção

    static func detect(on date: Date, now: Date, region: Region, inputs i: Inputs) -> SpecialDay? {
        guard let problem = DayProblem.detect(on: date, now: now, region: region, cities: i.cities, legs: i.legs, tripEnd: i.tripEnd,
                                              saveForEnd: i.saveForEnd.count) else { return nil }
        let cal = region.calendar
        let day = cal.startOfDay(for: date)
        let city = DayProblem.cityOn(day, cities: i.cities, calendar: cal)
        let trainsToday = i.trains.filter { cal.isDate($0.at, inSameDayAs: day) }.sorted { $0.at < $1.at }
        var items: [Item]
        let title: String
        switch problem.kind {
        case .arrival:
            title = "Chegada"
            items = arrivalItems(day: day, now: now, region: region, city: city, inputs: i, trains: trainsToday)
        case .transfer:
            title = "Troca de cidade"
            items = transferItems(day: day, region: region, cities: i.cities, to: city, trains: trainsToday)
        case .lastDay:
            title = "Último dia"
            items = lastDayItems(day: day, region: region, problem: problem, inputs: i)
        }
        items = items.filter { !$0.title.isEmpty }
        return SpecialDay(kind: problem.kind, title: title, headline: problem.headline, items: items, light: problem.light,
                          leaveAt: problem.leaveAt, cityName: city?.name)
    }

    /// Lê voos, "fica pro fim" e reservas de trem do container. Só em viagem com datas.
    @MainActor
    static func today(context: ModelContext, trip: TripInfo?, region: Region, now: Date) -> SpecialDay? {
        guard let trip, trip.hasTrip else { return nil }
        let flights = context.flights()
        let legs = flights.flatMap(\.legs)
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let cal = region.calendar
        let day = cal.startOfDay(for: now)
        let arrivalLeg = DayProblem.arrivalLeg(on: day, region: region, legs: legs)
        let checklist = arrivalLeg.flatMap { leg in flights.first { $0.legs.contains { $0.id == leg.id } } }?
            .checklist.filter { $0.phase == .arrival } ?? []
        let save = places.filter { $0.saveForEnd && !$0.isDone }.map(\.name)
        let trains = places.compactMap { trainBooking(name: $0.name, note: $0.reservation?.note, at: $0.reservation?.at) }
            + places.flatMap { p in p.tickets.compactMap { trainBooking(name: p.name, note: nil, at: $0.at) } }
        let inputs = Inputs(cities: trip.cities, legs: legs, tripEnd: trip.end, saveForEnd: save, arrivalChecklist: checklist,
                            trains: trains, taxFree: PocketRules.country(region).cards.contains { $0.kind == .taxFree })
        return detect(on: now, now: now, region: region, inputs: inputs)
    }

    // MARK: Trem

    /// Só vira trem o que se diz trem (nome ou nota): Shinkansen, Nozomi/Hikari, Express, Skyliner, "trem pra …".
    static func trainBooking(name: String, note: String?, at: Date?) -> Train? {
        guard let at else { return nil }
        let text = (name + " " + (note ?? "")).lowercased()
        let words = ["shinkansen", "nozomi", "hikari", "trem ", "trem·", "train", "skyliner", "narita express", "n'ex", "frecciarossa", "italo", "leonardo express"]
        guard words.contains(where: { text.contains($0) }) || text.hasPrefix("trem") else { return nil }
        return Train(name: name, at: at, detail: note)
    }

    // MARK: Chegada

    private static func arrivalItems(day: Date, now: Date, region: Region, city: City?, inputs i: Inputs, trains: [Train]) -> [Item] {
        var out: [Item] = []
        if let leg = DayProblem.arrivalLeg(on: day, region: region, legs: i.legs) {
            let landed = leg.revisedArrives ?? leg.arrives
            let isPast = landed.map { $0 <= now } ?? false
            var line = isPast ? "Pousou" : "Pouso"
            if let landed { line += " \(region.timeString(landed))" }
            line += " · \(leg.to)"
            if let t = leg.arrivalTerminal { line += " T\(t)" }
            out.append(Item(id: "pouso", icon: "airplane.arrival", title: line, detail: leg.number, done: isPast))
        }
        for t in trains {
            out.append(Item(id: "trem-\(t.name)", icon: "tram.fill", title: "\(t.name) · \(region.timeString(t.at))", detail: t.detail))
        }
        for c in i.arrivalChecklist {
            out.append(Item(id: "chk-\(c.id)", icon: c.done ? "checkmark.circle.fill" : "circle", title: c.title, detail: c.note, done: c.done))
        }
        if let l = city?.lodging, let item = lodgingItem(l, region: region, checkIn: true) { out.append(item) }
        out.append(Item(id: "descanso", icon: "fork.knife", title: "Comer perto e descansar",
                        detail: "hoje o dia é leve: um lugar a pé do hotel e dormir cedo"))
        return out
    }

    // MARK: Troca de cidade

    private static func transferItems(day: Date, region: Region, cities: [City], to: City?, trains: [Train]) -> [Item] {
        let cal = region.calendar
        let from = cal.date(byAdding: .day, value: -1, to: day).flatMap { DayProblem.cityOn($0, cities: cities, calendar: cal) }
        var out: [Item] = []
        out.append(Item(id: "mala", icon: "suitcase.rolling", title: "Mala pronta",
                        detail: from.map { "saindo de \($0.name)" }))
        if let out1 = from?.lodging?.checkOut {
            let name = from?.lodging?.name.map { " de \($0)" } ?? ""
            out.append(Item(id: "checkout", icon: "door.left.hand.open", title: "Check-out\(name) até \(DayProblem.hourText(out1, region: region))"))
        }
        for t in trains {
            let dest = to.map { " pra \($0.name)" } ?? ""
            out.append(Item(id: "trem-\(t.name)", icon: "tram.fill", title: "Trem\(dest) · \(region.timeString(t.at))",
                            detail: t.detail ?? t.name))
        }
        if let l = to?.lodging, let item = lodgingItem(l, region: region, checkIn: true) { out.append(item) }
        if let to {
            out.append(Item(id: "depois", icon: "map", title: "Depois do trem, o dia é só em \(to.name)",
                            detail: "o dia monta só com lugares de \(to.name)"))
        }
        return out
    }

    // MARK: Último dia

    private static func lastDayItems(day: Date, region: Region, problem: DayProblem, inputs i: Inputs) -> [Item] {
        var out: [Item] = []
        if let leave = problem.leaveAt, let back = DayProblem.returnLeg(region: region, legs: i.legs) {
            out.append(Item(id: "aeroporto", icon: "airplane.departure", title: "Saia pro aeroporto às \(region.timeString(leave))",
                            detail: "\(back.number) · voo \(region.timeString(back.departsNow)) \(back.from)"))
        } else if let back = DayProblem.returnLeg(region: region, legs: i.legs),
                  region.calendar.date(byAdding: .day, value: 1, to: day).map({ region.calendar.isDate(back.departsNow, inSameDayAs: $0) }) == true {
            out.append(Item(id: "voo", icon: "airplane.departure", title: "Voo amanhã \(region.timeString(back.departsNow)) · \(back.from)",
                            detail: back.number))
        }
        if !i.saveForEnd.isEmpty {
            let shown = i.saveForEnd.prefix(4).map { DayText.head($0) }.joined(separator: ", ")
            let more = i.saveForEnd.count > 4 ? " e mais \(i.saveForEnd.count - 4)" : ""
            out.append(Item(id: "fim", icon: "flag.checkered", title: "Ficou pro fim (\(i.saveForEnd.count))", detail: shown + more))
        }
        if i.taxFree {
            out.append(Item(id: "taxfree", icon: "creditcard", title: "Tax-free: leve o passaporte", detail: "sem ele a loja não devolve o imposto"))
        }
        out.append(Item(id: "malas", icon: "suitcase.rolling", title: "Malas e carregadores", detail: "confira a franquia no cartão do voo"))
        return out
    }

    // MARK: Hospedagem

    private static func lodgingItem(_ l: CityLodging, region: Region, checkIn: Bool) -> Item? {
        let name = [l.name, l.neighborhood].compactMap { $0 }.filter { !$0.isEmpty }
        guard !name.isEmpty || !(l.address ?? "").isEmpty else { return nil }
        var title = name.isEmpty ? "Hotel" : name.joined(separator: " · ")
        if checkIn, let at = l.checkIn { title += " · check-in \(DayProblem.hourText(at, region: region))" }
        return Item(id: "hotel", icon: "bed.double", title: title, detail: l.address)
    }
}
