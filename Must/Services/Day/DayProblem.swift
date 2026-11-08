import Foundation
import SwiftData

/// Dias-problema (relatório do viajante, problema 7): chegada, troca de cidade e último dia são os três dias mais
/// estressantes e o app tratava como um dia qualquer. Puro: sai dos dados que já existem (voos, hospedagem por cidade,
/// datas da viagem). Sem rede e sem inventar nada: o que falta no cadastro vira um pedido ("cadastre o hotel"), não um palpite.
struct DayProblem: Equatable, Sendable {
    enum Kind: String, Sendable { case arrival, transfer, lastDay }

    var kind: Kind
    /// A linha principal da capa e do Bom dia: "Pouso 15:40 NRT · hotel em Shinjuku · sem plano pesado hoje".
    var headline: String
    /// Rótulo curto do dia ("Dia de chegada", "Dia de trem", "Último dia").
    var title: String
    /// A ação do bloco da capa quando a foto não existe ("pouso 15:40", "trem pra Kyoto", "saia às 15:25").
    var hero: String
    /// Dia leve: não montar nada pesado (chegada).
    var light: Bool
    /// Último dia com voo hoje: a hora de sair pro aeroporto.
    var leaveAt: Date?

    // MARK: Detecção

    /// `legs` = todas as pernas de todos os voos. `saveForEnd` = quantos Musts "fica pro fim" ainda faltam.
    static func detect(on date: Date, now: Date, region: Region, cities: [City], legs: [FlightSegment], tripEnd: Date?,
                       saveForEnd: Int = 0) -> DayProblem? {
        let cal = region.calendar
        let day = cal.startOfDay(for: date)
        if let arrival = arrival(on: day, now: now, region: region, cities: cities, legs: legs) { return arrival }
        if let last = lastDay(on: day, now: now, region: region, legs: legs, tripEnd: tripEnd, saveForEnd: saveForEnd) { return last }
        return transfer(on: day, region: region, cities: cities)
    }

    /// O dia-problema de `now` lendo voos e "fica pro fim" do container. Só em viagem com datas; BH de casa não tem.
    @MainActor
    static func today(context: ModelContext, trip: TripInfo?, region: Region, now: Date) -> DayProblem? {
        guard let trip, trip.hasTrip else { return nil }
        let legs = context.flights().flatMap(\.legs)
        let toSave = ((try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.saveForEnd }))) ?? []).filter { !$0.isDone }.count
        return detect(on: now, now: now, region: region, cities: trip.cities, legs: legs, tripEnd: trip.end, saveForEnd: toSave)
    }

    // MARK: Chegada

    /// Voo que entra no país da viagem e pousa hoje.
    static func arrivalLeg(on day: Date, region: Region, legs: [FlightSegment]) -> FlightSegment? {
        let cal = region.calendar
        return legs.filter { leg in
            guard let to = Airports.airport(leg.to), to.country == region.country else { return false }
            if let from = Airports.airport(leg.from), from.country == region.country { return false }
            return cal.isDate(leg.revisedArrives ?? leg.arrives ?? leg.landsEstimate, inSameDayAs: day)
        }.max { $0.landsEstimate < $1.landsEstimate }
    }

    private static func arrival(on day: Date, now: Date, region: Region, cities: [City], legs: [FlightSegment]) -> DayProblem? {
        guard let leg = arrivalLeg(on: day, region: region, legs: legs) else { return nil }
        let landed = leg.revisedArrives ?? leg.arrives
        let time = landed.map { region.timeString($0) }
        let isPast = landed.map { $0 <= now } ?? false
        var landing = isPast ? "Pousou" : "Pouso"
        if let time { landing += " \(time)" }
        landing += " \(leg.to)"
        if let terminal = leg.arrivalTerminal { landing += " T\(terminal)" }
        let city = cityOn(day, cities: cities, calendar: region.calendar)
        let hotel = hotelText(city?.lodging)
        let headline = [landing, hotel, "sem plano pesado hoje"].joined(separator: " · ")
        return DayProblem(kind: .arrival, headline: headline, title: "Dia de chegada",
                          hero: time.map { (isPast ? "pousou " : "pouso ") + $0 } ?? "dia de chegada", light: true, leaveAt: nil)
    }

    /// "hotel em Shinjuku" / "hotel Park Hyatt" / "cadastre o hotel".
    static func hotelText(_ lodging: CityLodging?) -> String {
        if let area = lodging?.neighborhood, !area.isEmpty { return "hotel em \(area)" }
        if let name = lodging?.name, !name.isEmpty { return "hotel \(name)" }
        return "cadastre o hotel"
    }

    // MARK: Troca de cidade

    private static func transfer(on day: Date, region: Region, cities: [City]) -> DayProblem? {
        let cal = region.calendar
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: day),
              let to = cityOn(day, cities: cities, calendar: cal), let from = cityOn(yesterday, cities: cities, calendar: cal),
              to.name != from.name else { return nil }
        let vehicle = ["JP", "IT", "FR", "ES", "PT", "DE", "GB", "CH"].contains(region.country) ? "Trem" : "Viagem"
        var parts = ["\(vehicle) pra \(to.name)", "mala"]
        if let out = from.lodging?.checkOut { parts.append("check-out \(hourText(out, region: region))") } else { parts.append("check-out do hotel") }
        if let inn = to.lodging?.checkIn { parts.append("check-in \(hourText(inn, region: region))") }
        return DayProblem(kind: .transfer, headline: parts.joined(separator: " · "), title: "Dia de trem",
                          hero: "\(vehicle.lowercased()) pra \(to.name)", light: false, leaveAt: nil)
    }

    // MARK: Último dia

    /// O voo que sai do país da viagem (o de volta): o último desse tipo.
    static func returnLeg(region: Region, legs: [FlightSegment]) -> FlightSegment? {
        legs.filter { leg in
            guard let from = Airports.airport(leg.from), from.country == region.country else { return false }
            if let to = Airports.airport(leg.to), to.country == region.country { return false }
            return true
        }.max { $0.departsNow < $1.departsNow }
    }

    private static func lastDay(on day: Date, now: Date, region: Region, legs: [FlightSegment], tripEnd: Date?,
                                saveForEnd: Int) -> DayProblem? {
        let cal = region.calendar
        let back = returnLeg(region: region, legs: legs)
        let isTripEnd = tripEnd.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let flightToday = back.map { cal.isDate($0.departsNow, inSameDayAs: day) } ?? false
        let flightTomorrow = back.flatMap { leg in cal.date(byAdding: .day, value: 1, to: day).map { cal.isDate(leg.departsNow, inSameDayAs: $0) } } ?? false
        guard isTripEnd || flightToday || flightTomorrow else { return nil }

        var parts = ["Último dia"]
        var tail: [String] = []
        if saveForEnd > 0 { tail.append("fica pro fim (\(saveForEnd))") }
        if PocketRules.country(region).cards.contains(where: { $0.kind == .taxFree }) { tail.append("tax-free") }
        var leave: Date?
        var hero = "último dia"
        if let back, flightToday {
            let at = FlightRules.leaveForAirport(departs: back.departsNow, international: FlightRules.isInternational(back))
            leave = at
            tail.append("saia pro aeroporto às \(region.timeString(at))")
            hero = "saia às \(region.timeString(at))"
        } else if let back, flightTomorrow {
            tail.append("voo amanhã \(region.timeString(back.departsNow)) \(back.from)")
            hero = "voo amanhã \(region.timeString(back.departsNow))"
        }
        parts[0] += tail.isEmpty ? "" : ":"
        let headline = tail.isEmpty ? parts[0] : parts[0] + " " + tail.joined(separator: " · ")
        return DayProblem(kind: .lastDay, headline: headline, title: "Último dia", hero: hero, light: false, leaveAt: leave)
    }

    // MARK: Cidade do dia

    /// A cidade em `day`: o trecho que contém o dia (no dia de troca, a nova), como `TripInfo.city(on:)`.
    static func cityOn(_ day: Date, cities: [City], calendar: Calendar) -> City? {
        let d = calendar.startOfDay(for: day)
        let dated = cities.filter { $0.from != nil && $0.to != nil }
        guard !dated.isEmpty else { return cities.first }
        if let hit = dated.last(where: { $0.from! <= d && d <= $0.to! }) { return hit }
        if let first = dated.first, d < first.from! { return first }
        return dated.last
    }

    /// "11h" / "11h30".
    static func hourText(_ date: Date, region: Region) -> String {
        let c = region.calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }
}
