import CoreLocation
import Foundation
import SwiftData
import SwiftUI

/// Uma parada do dia aceito, já sem `@Model` (a Home lê isso no `body`).
struct HomeStop: Identifiable, Hashable, Sendable {
    var id: UUID
    var placeId: String
    var name: String
    /// Posição no roteiro, de 1.
    var number: Int
    var done: Bool
    var isCurrent: Bool
}

/// O dia aceito de hoje, resumido pro card (prompt 18 · B.10).
struct HomeDay: Sendable {
    /// Bairro do dia: o com mais paradas. `nil` se nenhuma parada tem bairro.
    var areaId: String?
    var title: String
    var seal: String
    var sealSub: String?
    /// "+ Shin-Okubo e Nakano · 14:20 · 18°"
    var subtitle: String
    var stops: [HomeStop]
    /// Próxima parada não feita. `nil` = dia feito.
    var current: HomeStop?
    /// Linha do bloco "Agora": "fila ~20 min · saia 14:35 · 9 min a pé".
    var currentDetail: String?
    /// Lugar da parada atual (pra "Ir agora" → Como chegar).
    var currentPlaceId: String?
    var allDone: Bool { current == nil && !stops.isEmpty }
}

/// Um bairro do "Amanhã, pra onde?" com o chip de contexto (tempo, golden, museus fechados, reserva).
struct HomeAreaCard: Identifiable, Hashable, Sendable {
    var entry: AreaEntry
    var context: String?
    var id: String { entry.id }
}

/// Estado da Início (prompt 18 · B.9–12). Tudo que a tela mostra sai daqui, calculado **fora do `body`**.
///
/// Recalcula só nos gatilhos: minuto (timer de 60 s), posição (≥ 50 m), salvar no SwiftData (lugares, dia, gasto),
/// voltar pra frente e a previsão chegar. Não decodifica JSON novo (os `Data` têm cache por objeto, A.1).
@MainActor
@Observable
final class HomeState {
    /// Entrada de um recálculo: valores que a Home já tem; nada de `@Model` sai daqui.
    struct Inputs {
        var region: Region
        var now: Date
        var trip: TripInfo?
        var places: [Place]
        var expenses: [Expense]
        var days: [PlannedDay]
        var location: CLLocation?
        var tomorrowWeather: DayWeather?
        var nowTemp: Double?
    }

    /// Dia aceito de hoje (nil = sem dia montado).
    private(set) var day: HomeDay?
    /// "Hoje, pra onde?": os 3 bairros com mais musts abertos agora (sem dia). Sem nada aberto, os 3 com mais musts.
    private(set) var pick: [AreaEntry] = []
    /// `true` quando `pick` caiu no fallback (nada aberto agora no que tem horário).
    private(set) var pickIsFallback = false
    /// "Amanhã, pra onde?": 3 bairros com mais musts e o chip de contexto.
    private(set) var tomorrow: [HomeAreaCard] = []
    /// Gasto de hoje (na moeda da região). O orçamento fica em Ajustes › Dia.
    private(set) var spentToday: Double = 0
    /// Lugares do board abertos agora a até 1,5 km.
    private(set) var openNearbyCount = 0
    /// "Sáb · 15 nov" e "Tóquio · dia 3/5".
    private(set) var dateLine = ""
    private(set) var cityLine = ""
    /// Temperatura agora ("18°"), se a previsão já chegou.
    private(set) var tempText: String?
    /// Foto escolhida de cada bairro visível (`AreaHeroes`).
    private(set) var heroes: [String: CCPhoto] = [:]
    /// Quantos musts o board tem por bairro (pra "Hoje, pra onde?" e pro título do card).
    private(set) var areaIndex = AreaIndex.empty

    @ObservationIgnored private var candidates: [String: [AreaHeroes.Candidate]] = [:]
    @ObservationIgnored private var requestedHeroes: Set<String> = []
    @ObservationIgnored private let openIndex = OpenNowIndex()
    /// Recálculos feitos (pros testes: só recalcula nos gatilhos).
    @ObservationIgnored private(set) var refreshCount = 0

    /// Bairros cuja foto a tela mostra agora. Muda quando muda o dia, o pick ou amanhã.
    var visibleAreaIds: [String] {
        var ids: [String] = []
        if let areaId = day?.areaId { ids.append(areaId) }
        ids += pick.map(\.id)
        ids += tomorrow.map(\.id)
        return ids.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Chave do `.task` que busca as fotos: troca quando os bairros visíveis trocam.
    var heroKey: String { visibleAreaIds.joined(separator: ",") }

    func area(_ id: String) -> Area? { areaIndex.area(id) }

    /// Recalcula tudo. Chamado só nos gatilhos da Início.
    func refresh(_ i: Inputs) {
        refreshCount += 1
        let cal = i.region.calendar
        let now = i.now
        let tz = i.region.timeZone

        // Mesmo instante pros abertos, o bairro e o "Agora".
        let placeRefs = i.places.map(Self.areaPlace)
        let snapshot = openIndex.snapshot(for: i.places, now: now, timeZone: tz, location: i.location)
        let openIds = Set(i.places.filter { snapshot.isOpen($0.id) }.map(\.id))
        let index = AreaIndex.build(areas: AreaCatalog.areas(for: i.region), places: placeRefs, openIds: openIds)
        areaIndex = index
        let placesById = Dictionary(i.places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        spentToday = Self.spent(i.expenses, on: now, region: i.region)
        openNearbyCount = i.places.filter { place in
            !place.isDone && snapshot.isOpen(place.id) && (snapshot.distance(place.id).map { $0 <= 1500 } ?? false)
        }.count

        dateLine = Self.dateLine(now, region: i.region)
        cityLine = Self.cityLine(now, region: i.region, trip: i.trip)
        tempText = i.nowTemp.map { "\(Int($0.rounded()))°" }

        // Hoje: dia aceito ou pick.
        let start = cal.startOfDay(for: now)
        let today = i.days.first { $0.date == start && $0.accepted }
        if let today {
            day = Self.homeDay(today, index: index, placesById: placesById, now: now, region: i.region,
                               location: i.location, tempText: tempText)
            pick = []
        } else {
            day = nil
            pick = index.openNow(limit: 3)
            pickIsFallback = pick.isEmpty
            if pickIsFallback { pick = index.mostMusts(limit: 3) }
        }

        // Amanhã: 3 bairros com mais musts e o chip do que pesa (reserva, museu fechado, golden, tempo).
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let tomorrowDay = i.days.first { $0.date == tomorrowDate }
        tomorrow = index.mostMusts(limit: 3).map { entry in
            HomeAreaCard(entry: entry, context: Self.tomorrowContext(entry, tomorrowDate: tomorrowDate, tomorrowDay: tomorrowDay,
                                                                     weather: i.tomorrowWeather, placesById: placesById,
                                                                     region: i.region))
        }

        // Candidatos à foto: musts verificados primeiro, depois a ordem do board (ver `AreaEntry.placeIds`).
        candidates = [:]
        for id in visibleAreaIds {
            guard let entry = index.entry(id) else { continue }
            candidates[id] = entry.placeIds.compactMap { placeId in
                placesById[placeId].map { AreaHeroes.Candidate(name: $0.name, coordinate: $0.coordinate) }
            }
        }
    }

    /// Busca a foto de cada bairro visível que ainda não tem (cache primeiro, rede só se preciso). Sem rede, nada.
    func loadHeroes(services: Services, region: Region, cityName: String) async {
        let heroesService = AreaHeroes(photos: services.photos)
        let todo = visibleAreaIds.filter { heroes[$0] == nil && !requestedHeroes.contains($0) }
        guard !todo.isEmpty else { return }
        requestedHeroes.formUnion(todo)
        var jobs: [(id: String, area: Area, candidates: [AreaHeroes.Candidate])] = []
        for id in todo {
            guard let area = areaIndex.area(id) else { requestedHeroes.remove(id); continue }
            jobs.append((id, area, candidates[id] ?? []))
        }
        await withTaskGroup(of: (String, CCPhoto?).self) { group in
            for job in jobs {
                group.addTask {
                    (job.id, await heroesService.photo(region: region, area: job.area, candidates: job.candidates, cityName: cityName))
                }
            }
            for await (id, photo) in group {
                requestedHeroes.remove(id)
                if let photo { heroes[id] = photo }
            }
        }
    }

    // MARK: Cálculo (puro, testável)

    static func areaPlace(_ p: Place) -> AreaPlace {
        AreaPlace(id: p.id, name: p.name, areaName: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng,
                  kind: p.list?.color, isDone: p.isDone, verified: p.placeId != nil, order: p.order,
                  hasReservation: p.reservation != nil)
    }

    static func spent(_ expenses: [Expense], on now: Date, region: Region) -> Double {
        let range = region.dayRange(now)
        return expenses.filter { range.contains($0.at) }.reduce(0) { $0 + $1.amount }
    }

    static func homeDay(_ day: PlannedDay, index: AreaIndex, placesById: [String: Place], now: Date, region: Region,
                        location: CLLocation?, tempText: String?) -> HomeDay {
        let ordered = day.orderedStops.filter { $0.place != nil }
        let firstOpen = ordered.firstIndex { !$0.done }
        var rows: [HomeStop] = []
        for (n, stop) in ordered.enumerated() {
            guard let place = stop.place else { continue }
            rows.append(HomeStop(id: stop.id, placeId: place.id, name: place.name, number: n + 1, done: stop.done,
                                 isCurrent: n == firstOpen))
        }
        let placeIds = ordered.compactMap { $0.place?.id }
        let areaId = AreaIndex.dayArea(stopPlaceIds: placeIds, index: index)
        let area = areaId.flatMap(index.area)
        let neighbors = areaId.map { AreaIndex.dayNeighbors(stopPlaceIds: placeIds, main: $0, index: index) } ?? []
        let neighborText = neighbors.prefix(2).map(\.name)
        var sub = neighborText.isEmpty ? [] : ["+ " + neighborText.joined(separator: " e ")]
        sub.append(region.timeString(now))
        if let tempText { sub.append(tempText) }

        var current: HomeStop?
        var detail: String?
        var currentPlaceId: String?
        if let i = firstOpen, let stop = ordered.dropFirst(i).first, let place = stop.place {
            current = rows[i]
            currentPlaceId = place.id
            var parts: [String] = []
            if let queue = place.queueMinutes { parts.append("fila ~\(queue) min") }
            if let distance = place.distance(from: location) {
                let walk = Walk.minutes(distance)
                if let leave = region.calendar.date(byAdding: .minute, value: -(walk + 5), to: stop.at) {
                    parts.append("saia \(region.timeString(leave))")
                }
                // A pé até 2 km; acima disso não é caminhada (o trem entra no Como chegar).
                parts.append(distance <= 2000 ? "\(Walk.shortText(distance)) a pé" : Walk.distanceText(distance))
            } else {
                parts.append("às \(region.timeString(stop.at))")
            }
            detail = parts.joined(separator: " · ")
        }
        return HomeDay(
            areaId: areaId, title: area?.name ?? "Hoje", seal: area?.seal ?? "済", sealSub: area?.stampSub,
            subtitle: sub.joined(separator: " · "), stops: rows, current: current, currentDetail: detail,
            currentPlaceId: currentPlaceId
        )
    }

    /// Um chip por bairro, na ordem: reserva amanhã, museu fechado amanhã, golden, tempo.
    static func tomorrowContext(_ entry: AreaEntry, tomorrowDate: Date, tomorrowDay: PlannedDay?, weather: DayWeather?,
                                placesById: [String: Place], region: Region) -> String? {
        let cal = region.calendar
        let members = entry.placeIds.compactMap { placesById[$0] }
        var weekday = Date.FormatStyle(locale: region.locale, calendar: cal).weekday(.abbreviated)
        weekday.timeZone = region.timeZone
        let wd = tomorrowDate.formatted(weekday).replacingOccurrences(of: ".", with: "").lowercased()

        if members.contains(where: { $0.hasReservation(on: tomorrowDate, calendar: cal) }) {
            return "reserva \(wd)"
        }
        let noon = tomorrowDate.addingTimeInterval(12 * 3600)
        if members.contains(where: { $0.kind == .art && $0.hours?.isOpen(at: noon, timeZone: region.timeZone) == false }) {
            return "museus \(wd) ✕"
        }
        let photoDay = tomorrowDay?.kind == .photo || entry.dominant == .photo
        if photoDay, let golden = SunService.day(noon, entry.area.centroid.clCoordinate, timeZone: region.timeZone).goldenPM {
            return "golden \(region.timeString(golden.start))"
        }
        if let weather { return weather.short }
        return nil
    }

    static func dateLine(_ now: Date, region: Region) -> String {
        var weekday = Date.FormatStyle(locale: region.locale, calendar: region.calendar).weekday(.abbreviated)
        weekday.timeZone = region.timeZone
        var month = Date.FormatStyle(locale: region.locale, calendar: region.calendar).month(.abbreviated)
        month.timeZone = region.timeZone
        let w = now.formatted(weekday).replacingOccurrences(of: ".", with: "")
        let m = now.formatted(month).replacingOccurrences(of: ".", with: "")
        let d = region.calendar.component(.day, from: now)
        return "\(w.prefix(1).uppercased() + w.dropFirst()) · \(d) \(m)"
    }

    /// "Tóquio · dia 3/5" (cidade da viagem e o dia dentro da estadia); em BH, a cidade e o dia da semana.
    static func cityLine(_ now: Date, region: Region, trip: TripInfo?) -> String {
        let cal = region.calendar
        guard let city = trip?.city(on: now, calendar: cal), let from = city.from, let to = city.to else {
            return region.displayName
        }
        let start = cal.startOfDay(for: from), end = cal.startOfDay(for: to)
        let total = (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let current = (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: now)).day ?? 0) + 1
        return "\(city.name) · dia \(min(max(current, 1), total))/\(total)"
    }
}
