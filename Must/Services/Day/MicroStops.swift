import CoreLocation
import Foundation

/// Micro-paradas geradas (prompt 23 §3): café perto do hotel, konbini/água antes de fila longa, descanso no hotel quando a
/// noite tem âncora depois das 19h, doce/vista no caminho, compra rápida. Duração fixa de 10 a 40 min; nunca âncora;
/// só entram num buraco que já existe entre duas paradas (com o deslocamento e a margem), então nada mais se move.
/// Determinístico: a mesma Linha volta igual em toda abertura.
enum MicroStops {
    /// Até onde um lugar do board conta como "perto" pra dar nome à micro-parada.
    static let nearMeters: CLLocationDistance = 700

    struct Words: Sendable, Hashable {
        var label: String
        var note: String
        var tag: String
        var cost: Double?
    }

    /// O que a micro-parada diz, por país (`data/countries/<cc>.json`, `day.micro`). País sem perfil: o genérico.
    static func words(_ kind: DayMicroKind, region: Region) -> Words {
        switch kind {
        case .view: return Words(label: "Vista no caminho", note: "micro · foto rápida no caminho", tag: "foto", cost: nil)
        case .show: return Words(label: "Em cartaz", note: "micro · em cartaz", tag: "cartaz", cost: nil)
        default: break
        }
        if let w = region.profile.day?.micro?[kind.rawValue] {
            return Words(label: w.label, note: w.note, tag: w.tag, cost: w.cost)
        }
        return switch kind {
        case .breakfast: Words(label: "Café da manhã", note: "micro · café perto do hotel", tag: "café", cost: nil)
        case .water: Words(label: "Água e um lanche", note: "micro · antes da fila", tag: "água", cost: nil)
        case .shop: Words(label: "Compra rápida", note: "micro · mercado ou farmácia no caminho", tag: region.currencySymbol, cost: nil)
        case .treat: Words(label: "Doce no caminho", note: "micro · uma pausa", tag: "doce", cost: nil)
        default: Words(label: "Descanso no hotel", note: "micro · 40 min · carregar o celular · trocar de roupa", tag: "zz", cost: nil)
        }
    }

    /// Ordem de tentativa. Compras na volta (Montar) passa a compra rápida pra frente; Roma ganha o gelato da tarde.
    static func priority(_ input: DayComposer.Input) -> [DayMicroKind] {
        var order: [DayMicroKind] = [.breakfast, .water, .rest]
        if input.region.profile.has(.treatMicroStop) { order.append(.treat) }
        order.append(.view)
        if input.includes.contains(.shopping) { order.insert(.shop, at: 1) } else { order.append(.shop) }
        // Por último: só ocupa buraco que sobrou (e só se o board tem exposição em temporada).
        order.append(.show)
        return order
    }

    static func insert(into board: [DayStop], input: DayComposer.Input, sun: SunDay, assigner: AreaAssigner) -> [DayStop] {
        guard !board.isEmpty else { return board }
        var timeline = board.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        var added = 0
        for kind in priority(input) where added < input.pace.microStops.upperBound {
            guard let micro = make(kind, timeline: timeline, input: input, sun: sun) else { continue }
            timeline.append(micro)
            timeline.sort { ($0.start, $0.id) < ($1.start, $1.id) }
            added += 1
        }
        // Micro-parada antes de uma parada já feita também ficou pra trás.
        for i in timeline.indices where timeline[i].kind == .micro {
            if let next = timeline[(i + 1)...].first(where: { $0.kind != .micro }), next.done { timeline[i].done = true }
        }
        return timeline
    }

    // MARK: Encaixe

    /// Início que cabe entre `prev` e `next` pra ficar `minutes` em `here`: chega depois de `prev` (ou de `floor`) e ainda sai
    /// a tempo de `next` (até `nextStart`, com o deslocamento e 5 min de margem). Grade de 5 min. `nil` = não cabe.
    static func fit(_ minutes: Int, at here: CLLocationCoordinate2D, prev: DayStop?, next: DayStop, nextStart: Date? = nil,
                    floor: Date? = nil, latest: Bool, input: DayComposer.Input) -> Date? {
        let prevEnd = max(prev?.end ?? .distantPast, floor ?? .distantPast)
        guard prevEnd > .distantPast else { return nil }
        let prevSpot = prev.flatMap(DayComposer.coordinate) ?? input.hotel
        let early = roundUp(prevEnd.addingTimeInterval(Double(travel(prevSpot, here, input)) * 60), day: input.date)
        let leaveBy = (nextStart ?? next.start).addingTimeInterval(-Double(travel(here, DayComposer.coordinate(next), input) + DayNowRules.margin + minutes) * 60)
        let late = roundDown(leaveBy, day: input.date)
        guard early <= late else { return nil }
        return latest ? late : early
    }

    static func travel(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?, _ input: DayComposer.Input) -> Int {
        DayComposer.minutes(a, b, walkMaxKm: input.walkMaxKm, travel: input.travel)
    }

    static func roundUp(_ date: Date, day: Date) -> Date {
        let minutes = (date.timeIntervalSince(day) / 60).rounded(.up)
        return day.addingTimeInterval((minutes / 5).rounded(.up) * 5 * 60)
    }

    static func roundDown(_ date: Date, day: Date) -> Date {
        let minutes = (date.timeIntervalSince(day) / 60).rounded(.down)
        return day.addingTimeInterval((minutes / 5).rounded(.down) * 5 * 60)
    }

    private static func at(_ hour: Int, _ minute: Int = 0, _ input: DayComposer.Input) -> Date {
        input.date.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    // MARK: Cada tipo

    static func make(_ kind: DayMicroKind, timeline: [DayStop], input: DayComposer.Input, sun: SunDay) -> DayStop? {
        let boardIndices = timeline.indices.filter { timeline[$0].kind != .micro }
        guard !boardIndices.isEmpty else { return nil }
        let inDay = Set(timeline.compactMap(\.placeId))
        let d = kind.minutes
        var w = words(kind, region: input.region)
        func stop(_ start: Date, _ here: CLLocationCoordinate2D, area: String?, place: SolverPlace? = nil) -> DayStop {
            if let place { w.label = named(place, kind: kind) }
            return DayStop(id: "m-\(kind.rawValue)", placeId: place?.id, kind: .micro, start: start, end: start.addingTimeInterval(Double(d) * 60),
                           label: w.label, note: w.note, tag: w.tag, area: area, cost: place.flatMap { $0.price } ?? w.cost,
                           micro: kind, lat: here.latitude, lng: here.longitude)
        }
        /// Pares (anterior, seguinte) de cada buraco, em ordem.
        let gaps: [(prev: DayStop, next: DayStop)] = zip(timeline, timeline.dropFirst()).map { ($0, $1) }

        switch kind {
        case .breakfast:
            // Antes da primeira parada, perto do hotel, entre 07:00 e 10:30.
            guard let first = timeline.first else { return nil }
            // O dia já começa num café do board: não tem café da manhã antes.
            if let morning = input.stops.min(by: { $0.start < $1.start })?.place, isCoffee(morning) { return nil }
            let here = input.hotel
            guard let start = fit(d, at: here, prev: nil, next: first, floor: at(7, 0, input), latest: true, input: input),
                  start <= at(10, 30, input) else { return nil }
            let cafe = nearest(in: input.catalog, to: here, excluding: inDay, at: start, input: input, where: isCoffee)
            return stop(start, here, area: nil, place: cafe)

        case .water:
            // Antes de fila longa (≥ 15 min, sem reserva): logo antes de entrar na fila, do lado.
            if let qi = boardIndices.first(where: { !timeline[$0].isBooked && (timeline[$0].queueMinutes ?? 0) >= 15 && $0 > 0 }),
               let here = DayComposer.coordinate(timeline[qi]),
               let start = fit(d, at: here, prev: timeline[qi - 1], next: timeline[qi], nextStart: DayNowRules.arriveBy(timeline[qi]),
                               latest: true, input: input) {
                w.note = "micro · antes da fila de ~\(timeline[qi].queueMinutes ?? 0) min"
                return stop(start, here, area: timeline[qi].area)
            }
            // Senão, depois de uma âncora longa (≥ 1 h 40) que acaba antes das 16h.
            for (prev, next) in gaps where prev.kind == .anchor && prev.minutes >= 100 && prev.end <= at(16, 0, input) {
                guard let here = DayComposer.coordinate(prev),
                      let start = fit(d, at: here, prev: prev, next: next, latest: false, input: input) else { continue }
                w.note = "micro · na saída · antes de seguir"
                return stop(start, here, area: prev.area)
            }
            return nil

        case .rest:
            // A noite tem âncora (reserva/ingresso) depois das 19h: 40 min no hotel no buraco da tarde antes dela.
            guard let evening = timeline.firstIndex(where: { $0.isBooked && $0.start >= at(19, 0, input) }), evening > 0 else { return nil }
            for k in stride(from: evening, to: 0, by: -1) {
                let prev = timeline[k - 1], next = timeline[k]
                guard prev.end >= at(14, 30, input) else { break }
                if let start = fit(d, at: input.hotel, prev: prev, next: next, latest: false, input: input) {
                    return stop(start, input.hotel, area: nil)
                }
            }
            return nil

        case .treat:
            // Doce da tarde (Roma: gelato), saindo de uma parada entre 14:30 e 18:30.
            for (prev, next) in gaps where prev.end >= at(14, 30, input) && prev.end <= at(18, 30, input) {
                guard let here = DayComposer.coordinate(prev),
                      let start = fit(d, at: here, prev: prev, next: next, latest: false, input: input) else { continue }
                let shop = nearest(in: input.catalog, to: here, excluding: inDay, at: start, input: input) { p in
                    let t = "\(p.name) \(p.sub ?? "")".lowercased()
                    return t.contains("gelat") || t.contains("sorvet") || t.contains("taiyaki")
                }
                return stop(start, here, area: prev.area, place: shop)
            }
            return nil

        case .view:
            // "Foto no golden" pedida e o dia sem golden: 15 min de foto onde se estiver no começo do golden.
            if input.includes.contains(.goldenPhoto), !timeline.contains(where: { $0.anchor == .golden }), let golden = sun.goldenPM {
                for (prev, next) in gaps {
                    guard let here = DayComposer.coordinate(prev),
                          let early = fit(d, at: here, prev: prev, next: next, latest: false, input: input),
                          let late = fit(d, at: here, prev: prev, next: next, latest: true, input: input) else { continue }
                    let target = roundDown(golden.start, day: input.date)
                    guard early <= target, target <= late else { continue }
                    w.label = "Foto no golden"
                    w.note = "micro · golden \(input.region.timeString(golden.start))–\(input.region.timeString(golden.end))"
                    return stop(target, here, area: prev.area)
                }
            }
            // Vista no meio do trecho mais longo (≥ 1,2 km).
            let long = gaps.compactMap { pair -> (prev: DayStop, next: DayStop, km: Double)? in
                guard let a = DayComposer.coordinate(pair.prev), let b = DayComposer.coordinate(pair.next) else { return nil }
                let km = DaySolver.streetKm(a, b)
                return km >= 1.2 ? (pair.prev, pair.next, km) : nil
            }.sorted { $0.km > $1.km }
            for gap in long {
                guard let a = DayComposer.coordinate(gap.prev), let b = DayComposer.coordinate(gap.next) else { continue }
                let mid = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
                if let start = fit(d, at: mid, prev: gap.prev, next: gap.next, latest: false, input: input) {
                    return stop(start, mid, area: gap.prev.area)
                }
            }
            return nil

        case .show:
            return exhibition(timeline: timeline, gaps: gaps, inDay: inDay, input: input, minutes: d, words: w)

        case .shop:
            // A caminho: sai de uma parada e compra antes de seguir pra próxima (de preferência à tarde).
            let ordered = gaps.filter { $0.prev.end >= at(15, 0, input) } + gaps.filter { $0.prev.end < at(15, 0, input) }
            for (prev, next) in ordered {
                guard let here = DayComposer.coordinate(prev),
                      let start = fit(d, at: here, prev: prev, next: next, latest: true, input: input) else { continue }
                let shop = nearest(in: input.catalog, to: here, excluding: inDay, at: start, input: input) { $0.role == .shop }
                return stop(start, here, area: prev.area, place: shop)
            }
            return nil
        }
    }

    /// Exposição em cartaz (museu/galeria do board) perto do buraco: só se está em temporada hoje, aberta durante a visita
    /// (e fechando depois dela) e cabe entre duas paradas sem mexer em nenhuma. Nunca entra lugar que já está no dia.
    /// Dá pra trocar a faixa de 700 m por até 1,2 km: a exposição é o motivo da parada.
    static let showNearMeters: CLLocationDistance = 1_200

    private static func exhibition(timeline: [DayStop], gaps: [(prev: DayStop, next: DayStop)], inDay: Set<String>,
                                   input: DayComposer.Input, minutes d: Int, words w: Words) -> DayStop? {
        let cal = input.region.calendar
        let cities = Set(input.stops.map { AreaCatalog.cityGroup(forCityId: $0.place.cityId) })
        let showing = input.catalog.filter { p in
            guard !p.done, !inDay.contains(p.id), p.kind == .art, p.lat != 0 || p.lng != 0, let art = p.extra?.art,
                  art.runsFrom != nil || art.runsUntil != nil, art.isRunning(on: input.date, calendar: cal) else { return false }
            return cities.isEmpty || cities.contains(AreaCatalog.cityGroup(forCityId: p.cityId))
        }
        guard !showing.isEmpty else { return nil }
        for (prev, next) in gaps {
            guard let from = DayComposer.coordinate(prev) else { continue }
            let spot = CLLocation(latitude: from.latitude, longitude: from.longitude)
            let near = showing.map { ($0, $0.location.distance(from: spot)) }.filter { $0.1 <= showNearMeters }
                .sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
            for (place, _) in near {
                let here = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
                guard let early = fit(d, at: here, prev: prev, next: next, latest: false, input: input),
                      let late = fit(d, at: here, prev: prev, next: next, latest: true, input: input) else { continue }
                let end = early.addingTimeInterval(Double(d) * 60)
                let tz = input.region.timeZone
                guard place.hours?.isOpen(at: early, timeZone: tz) != false, place.hours?.isOpen(at: end, timeZone: tz) != false else { continue }
                let closes = place.hours?.closesAt(early, timeZone: tz)
                if let closes, let hm = closes.split(separator: ":").compactMap({ Int($0) }) as [Int]?, hm.count == 2,
                   input.date.addingTimeInterval(Double(max(hm[0] * 60 + hm[1], hm[0] == 0 ? 1440 : 0)) * 60) < end { continue }
                let room = d + Int(late.timeIntervalSince(early) / 60)
                var note = "micro · em cartaz · cabe \(room) min"
                if let closes { note += " · fecha \(closes)" }
                return DayStop(id: "m-show", placeId: place.id, kind: .micro, start: early, end: end, label: "\(place.name) · em cartaz",
                               note: note, tag: w.tag, area: place.area ?? prev.area, cost: place.extra?.art?.priceAdult ?? place.price,
                               micro: .show, lat: place.lat, lng: place.lng)
            }
        }
        return nil
    }

    static func isCoffee(_ p: SolverPlace) -> Bool {
        let sub = (p.sub ?? "").lowercased()
        return p.listColor == .coffee || sub.contains("café") || sub.contains("cafe") || sub.contains("coffee")
    }

    /// "Fuglen Tokyo" / "Isetan · compra rápida" / "Fatamorgana · gelato".
    static func named(_ place: SolverPlace, kind: DayMicroKind) -> String {
        switch kind {
        case .shop: "\(place.name) · compra rápida"
        case .treat:
            place.name.lowercased().contains("gelat") ? place.name
                : "\(place.name) · \((place.sub ?? "").lowercased().contains("gelat") ? "gelato" : "doce")"
        default: place.name
        }
    }

    /// Lugar do board mais perto de `here` (até 700 m), da mesma cidade do dia, que não está no dia nem feito e não está
    /// fechado na hora. Desempate pelo id (determinístico).
    static func nearest(in catalog: [SolverPlace], to here: CLLocationCoordinate2D, excluding: Set<String>, at start: Date,
                        input: DayComposer.Input, where match: (SolverPlace) -> Bool) -> SolverPlace? {
        let spot = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let cities = Set(input.stops.map { AreaCatalog.cityGroup(forCityId: $0.place.cityId) })
        return catalog
            .filter { !$0.done && !excluding.contains($0.id) && ($0.lat != 0 || $0.lng != 0) && match($0) }
            .filter { cities.isEmpty || cities.contains(AreaCatalog.cityGroup(forCityId: $0.cityId)) }
            .filter { $0.hours?.isOpen(at: start, timeZone: input.region.timeZone) != false }
            .map { ($0, $0.location.distance(from: spot)) }
            .filter { $0.1 <= nearMeters }
            .min { ($0.1, $0.0.id) < ($1.1, $1.0.id) }?.0
    }
}
