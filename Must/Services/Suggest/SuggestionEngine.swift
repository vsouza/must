import CoreLocation
import Foundation

/// Ranker local e determinístico da capa (prompt 26 §2). Sem rede: só o que já está no aparelho.
/// `relevância = proximidade (0–3) + encaixe de horário (0–3) + no board (2) + gosto (0–2) + urgência (+2) − repetição (−2)`.
/// Empate: o que fecha/começa antes. Até 4 cartões; no máximo um evento e um indicado.
enum SuggestionEngine {
    static let maxCards = 4
    /// Caminhada máxima de um Must (min) e de um evento (min).
    static let mustWalkMinutes = 15
    static let eventWalkMinutes = 20
    /// Linha reta → rua.
    static let streetFactor = 1.25

    static func suggest(_ i: SuggestInputs) -> [Suggestion] {
        var all: [Suggestion] = []
        if let plan = planCard(i) { all.append(plan) }
        all += mustCards(i)
        all += eventCards(i)
        if let light = lightCard(i) { all.append(light) }
        let ranked = pick(all.filter { !i.dismissed.contains($0.id) }, i: i)
        if !ranked.isEmpty { return ranked }
        return fallback(i)
    }

    // MARK: Montagem

    /// Ordena, tira lugar repetido e respeita os tetos (1 evento, 1 indicado). Indicado só entra se sobrou vaga.
    static func pick(_ cards: [Suggestion], i: SuggestInputs) -> [Suggestion] {
        let sorted = cards.sorted { a, b in
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            let (x, y) = (a.urgencyMinutes ?? .max, b.urgencyMinutes ?? .max)
            return x != y ? x < y : a.id < b.id
        }
        var out: [Suggestion] = []
        var seenPlaces: Set<String> = []
        var events = 0
        for card in sorted where out.count < maxCards {
            if let place = card.placeId, !seenPlaces.insert(place).inserted { continue }
            if card.kind == .event {
                if events >= 1 { continue }
                events += 1
            }
            out.append(card)
        }
        if out.count < maxCards, let indicated = indicatedCard(i, taken: Set(out.compactMap(\.placeId))),
           !i.dismissed.contains(indicated.id) {
            out.append(indicated)
        }
        return out
    }

    /// A capa nunca fica vazia: sem nada aberto/compatível, os Musts mais perto que você ainda não fez.
    static func fallback(_ i: SuggestInputs) -> [Suggestion] {
        guard let here = i.here else { return [] }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        return i.places.filter { !$0.done && !i.dismissed.contains("must:\($0.id)") }
            .map { ($0, CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: origin) * streetFactor) }
            .sorted { $0.1 < $1.1 }.prefix(maxCards)
            .map { place, meters in
                Suggestion(id: "must:\(place.id)", kind: .must, style: .ink, label: "MUST \(place.listName.uppercased())",
                           trailing: Walk.distanceText(meters), title: place.name, meta: place.sub ?? "no seu board",
                           reasons: ["perto", "no board"], placeId: place.id, eventId: nil, coordinate: place.coordinate, url: nil,
                           score: 0, urgencyMinutes: nil)
            }
    }

    // MARK: 1 · Plano

    static func planCard(_ i: SuggestInputs) -> Suggestion? {
        guard let stop = i.plan else { return nil }
        let late = stop.lateSince.map { "desde \(i.region.timeString($0))" }
        return Suggestion(id: "plan:\(stop.id)", kind: .plan, style: .ink, label: "NO PLANO · AGORA", trailing: nil,
                          title: stop.label, meta: [stop.action, late].compactMap { $0 }.joined(separator: " · "),
                          reasons: ["no plano", late == nil ? "agora" : "atrasado"], placeId: stop.placeId, eventId: nil,
                          coordinate: stop.lat.flatMap { lat in stop.lng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } },
                          url: nil, score: 100, urgencyMinutes: 0)
    }

    // MARK: 2 e 3 · Musts perto, abertos, fecha logo

    static func mustCards(_ i: SuggestInputs) -> [Suggestion] {
        guard let here = i.here else { return [] }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let windows = currentWindows(i.now, region: i.region)
        var out: [Suggestion] = []
        for place in i.places where !place.done {
            if place.kind == .photo { continue } // photo entra pela luz
            let meters = CLLocation(latitude: place.lat, longitude: place.lng).distance(from: origin) * streetFactor
            let walk = Walk.minutes(meters)
            guard walk <= mustWalkMinutes else { continue }
            guard let fit = fit(place, windows: windows, now: i.now, region: i.region) else { continue }
            var reasons = ["perto"]
            var score = proximity(walk: walk) + Double(fit.score) + 2 + Double(i.taste[place.color] ?? 0)
            if place.isIndoor, let rain = i.rainInMinutes, rain <= 120 {
                score += 1.5
                reasons.insert("chuva em \(rain) min · coberto", at: 0)
            }
            reasons.append("no board")
            if fit.good { reasons.append("hora certa") }
            if (i.taste[place.color] ?? 0) >= 2 { reasons.append("seu gosto") }
            var kind = Suggestion.Kind.must
            var label = "MUST \(place.listName.uppercased()) · \(fit.open ? "ABERTO" : "NO SEU HORÁRIO")"
            var urgency: Int?
            if let left = fit.closesIn, left <= 60 {
                score += 2
                kind = .closing
                label = "MUST \(place.listName.uppercased()) · FECHA LOGO"
                reasons.insert("fecha em \(left) min", at: 0)
                urgency = left
            }
            if i.shownEarlier.contains("must:\(place.id)") { score -= 2 }
            let meta = [fit.closesText.map { "fecha \($0)" }, place.sub].compactMap { $0 }.joined(separator: " · ")
            out.append(Suggestion(id: "must:\(place.id)", kind: kind, style: .ink, label: label, trailing: Walk.distanceText(meters),
                                  title: place.name, meta: meta.isEmpty ? "no seu board" : meta, reasons: reasons, placeId: place.id,
                                  eventId: nil, coordinate: place.coordinate, url: nil, score: score, urgencyMinutes: urgency))
        }
        return out
    }

    struct Fit { var score: Int; var open: Bool; var good: Bool; var closesIn: Int?; var closesText: String? }

    /// Encaixe de horário (0–3). `nil` = não vale agora (fechado, ou fora da janela do lugar).
    static func fit(_ place: SuggestPlace, windows: Set<String>, now: Date, region: Region) -> Fit? {
        let compatible = place.windows.isEmpty || !place.windows.isDisjoint(with: windows)
        switch place.state {
        case .closed: return nil
        case .open(let until):
            let left = until.flatMap { minutesUntil($0, now: now, region: region) }
            // Aberto e na janela dele = 3; aberto fora da janela (um café às 18h) = 1.
            return Fit(score: compatible ? 3 : 1, open: true, good: compatible, closesIn: left, closesText: until.map(shortTime))
        case .unknown:
            guard compatible else { return nil }
            return Fit(score: place.windows.isEmpty ? 1 : 2, open: false, good: !place.windows.isEmpty, closesIn: nil, closesText: nil)
        }
    }

    static func proximity(walk: Int) -> Double {
        switch walk {
        case ...5: 3
        case ...10: 2
        default: 1
        }
    }

    /// Janelas do dia em que `now` está (fuso da região).
    static func currentWindows(_ now: Date, region: Region) -> Set<String> {
        let c = region.calendar.dateComponents([.hour, .minute], from: now)
        let t = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        var out: Set<String> = []
        if t >= 6, t < 11.5 { out.insert("morning") }
        if t >= 11, t < 15 { out.insert("lunch") }
        if t >= 14, t < 18 { out.insert("afternoon") }
        if t >= 18, t < 22 { out.insert("dinner") }
        if t >= 18 || t < 4 { out.insert("night") }
        return out
    }

    /// Minutos até "22:00" (hoje; se já passou, é depois da meia-noite: amanhã).
    static func minutesUntil(_ hhmm: String, now: Date, region: Region) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let c = region.calendar.dateComponents([.hour, .minute], from: now)
        var delta = parts[0] * 60 + parts[1] - ((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if delta < 0 { delta += 1440 }
        return delta
    }

    /// "22:00" → "22h", "22:30" → "22:30".
    static func shortTime(_ hhmm: String) -> String {
        guard hhmm.hasSuffix(":00"), let hour = Int(hhmm.dropLast(3)) else { return hhmm }
        return "\(hour)h"
    }

    // MARK: 4 · Eventos

    static func eventCards(_ i: SuggestInputs) -> [Suggestion] {
        guard let here = i.here else { return [] }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        var out: [Suggestion] = []
        for event in i.events {
            guard let lat = event.lat, let lng = event.lng, let start = event.startsAt else { continue }
            let minutes = Int(start.timeIntervalSince(i.now) / 60)
            guard minutes >= -30, minutes <= 4 * 60 else { continue } // começa nas próximas 4 h (ou começou há pouco)
            let meters = CLLocation(latitude: lat, longitude: lng).distance(from: origin) * streetFactor
            let walk = Walk.minutes(meters)
            guard walk <= eventWalkMinutes else { continue }
            let color = event.kind == .exhibition ? "see" : (event.kind == .match ? "sport" : "listen")
            let taste = i.taste[color] ?? 0
            var score = proximity(walk: walk) + (minutes <= 120 ? 3 : 2) + Double(taste)
            var reasons = ["perto"]
            if minutes <= 90 { score += 2; reasons.append("começa em \(max(minutes, 0)) min") } else { reasons.append("hoje") }
            if taste >= 1 { reasons.append("seu gosto") }
            if i.shownEarlier.contains("event:\(event.id)") { score -= 2 }
            let time = i.region.timeString(start)
            out.append(Suggestion(id: "event:\(event.id)", kind: .event, style: .orange,
                                  label: "EVENTO · \(minutes < 0 ? "ROLANDO" : "HOJE")", trailing: Walk.distanceText(meters),
                                  title: event.title, meta: [event.venue, event.priceText, time].compactMap { $0 }.joined(separator: " · "),
                                  reasons: reasons, placeId: event.placeId, eventId: event.id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                  url: event.url, score: score, urgencyMinutes: max(minutes, 0)))
        }
        return out
    }

    // MARK: 5 · Luz

    static func lightCard(_ i: SuggestInputs) -> Suggestion? {
        guard let light = i.light, let here = i.here else { return nil }
        // Chuva a caminho: não sugere foto ao ar livre.
        if let rain = i.rainInMinutes, rain <= 60, light.isToday { return nil }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let candidates = i.places.filter { $0.kind == .photo && !$0.done }
            .map { ($0, CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: origin) * streetFactor) }
            .sorted { $0.1 < $1.1 }
        guard let (place, meters) = candidates.first else { return nil }
        let walk = Walk.minutes(meters)
        guard walk <= 25 else { return nil }
        let minutesToStart = Int(light.start.timeIntervalSince(i.now) / 60)
        let soon = light.isToday && minutesToStart <= 90
        var score = proximity(walk: min(walk, 15)) + (soon ? 3 : 1) + 2 + Double(i.taste[place.color] ?? 0)
        var reasons = ["luz boa", "perto", "no board"]
        if soon { score += 2; reasons[0] = minutesToStart > 0 ? "golden em \(minutesToStart) min" : "golden agora" }
        if i.shownEarlier.contains("light:\(place.id)") { score -= 2 }
        let day = light.isToday ? "" : "amanhã "
        return Suggestion(id: "light:\(place.id)", kind: .light, style: .paper, label: "MUST PHOTO · GOLDEN \(day)\(i.region.timeString(light.start))",
                          trailing: Walk.distanceText(meters), title: place.name,
                          meta: "luz até \(i.region.timeString(light.end))" + (place.sub.map { " · \($0)" } ?? ""),
                          reasons: reasons, placeId: place.id, eventId: nil, coordinate: place.coordinate, url: nil, score: score,
                          urgencyMinutes: light.isToday ? max(minutesToStart, 0) : nil)
    }

    // MARK: 6 · Indicados (fora do board)

    static func indicatedCard(_ i: SuggestInputs, taken: Set<String>) -> Suggestion? {
        guard let here = i.here else { return nil }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let best = i.indicated
            .filter { !$0.sources.allSatisfy { $0 == NearbySource.wikipedia } && $0.openNow != false && !i.boardNames.contains($0.name.lowercased()) }
            .compactMap { place -> (NearbyPlace, Double, Double)? in
                let meters = CLLocation(latitude: place.lat, longitude: place.lng).distance(from: origin) * streetFactor
                guard Walk.minutes(meters) <= mustWalkMinutes else { return nil }
                let hot = (place.popularity ?? 0) > 0.9
                let rating = place.rating ?? 0
                guard hot || (rating >= 4.4 && (place.ratingCount ?? 0) >= 100) else { return nil }
                return (place, meters, (hot ? 2 : 0) + rating)
            }
            .max { $0.2 < $1.2 }
        guard let (place, meters, _) = best else { return nil }
        let hot = (place.popularity ?? 0) > 0.9
        let reason = hot ? "em alta hoje" : "nota \((place.rating ?? 0).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))))"
        let source = place.sources.first(where: { $0 != NearbySource.board })?.chip
        return Suggestion(id: "indicated:\(place.id)", kind: .indicated, style: .paper, label: "INDICADO · FORA DO BOARD",
                          trailing: Walk.distanceText(meters), title: place.name,
                          meta: [place.category?.replacingOccurrences(of: "_", with: " "), source.map { "via \($0)" }].compactMap { $0 }.joined(separator: " · "),
                          reasons: ["perto", reason], placeId: nil, eventId: nil, coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                          url: URL(string: "maps://?daddr=\(place.lat),\(place.lng)&dirflg=w"),
                          score: 0, urgencyMinutes: nil)
    }
}
