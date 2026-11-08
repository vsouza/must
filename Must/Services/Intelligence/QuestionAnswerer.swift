import CoreLocation
import Foundation

/// Tipo de pergunta que o respondedor sabe responder sem modelo.
enum QuestionKind: String, Sendable, CaseIterable {
    /// "dá tempo de <lugar>?"
    case timeFor
    /// "quanto custa <lugar>?"
    case price
    /// "abre/fecha que horas?", "tá aberto?"
    case hours
    /// "como chego em <lugar/bairro>?"
    case route
    /// "vale a pena <lugar>?"
    case worth
    /// "o que eu faço agora?", "o que tem perto?"
    case nowNearby
    case unknown
}

/// Resposta curta e factual. `recognized == false` = não entendeu: o texto diz o que sabe responder e a tela oferece
/// "Continuar no Assistente".
struct QuestionAnswer: Sendable, Equatable {
    var kind: QuestionKind
    var text: String
    var placeId: String?
    var recognized: Bool
}

/// Respondedor **determinístico** das perguntas (prompt "pergunta"): usa só o que o app já tem (board da viagem, dia/`DayClock`,
/// deslocamento do solver, horário com `PlaceTrust`). Roda sempre que não há Foundation Models e serve de base factual
/// quando há. Nunca inventa lugar nem número: sem dado, diz que não tem.
enum QuestionAnswerer {
    static let margin = DayNowRules.margin

    // MARK: Entrada

    static func answer(_ question: String, snapshot s: AssistantSnapshot, clock: DayClock? = nil) -> QuestionAnswer {
        let text = QueroQuestion.normalize(question)
        let kind = classify(text)
        let place = findPlace(in: text, snapshot: s)
        switch kind {
        case .timeFor:
            guard let place else { return needsPlace(kind, "dá tempo") }
            return timeFor(place, snapshot: s, clock: clock)
        case .price:
            guard let place else { return needsPlace(kind, "o preço") }
            return price(place, snapshot: s)
        case .hours:
            guard let place else { return needsPlace(kind, "o horário") }
            return hours(place, snapshot: s)
        case .route:
            if let place { return route(to: place.coordinate, name: place.name, placeId: place.id, snapshot: s, clock: clock) }
            if let area = findArea(in: text, snapshot: s) {
                return route(to: area.centroid.clCoordinate, name: area.name, placeId: nil, snapshot: s, clock: clock, area: area)
            }
            return needsPlace(kind, "como chegar")
        case .worth:
            guard let place else { return needsPlace(kind, "se vale a pena") }
            return worth(place, snapshot: s)
        case .nowNearby:
            return nowNearby(snapshot: s, clock: clock)
        case .unknown:
            return unknown()
        }
    }

    // MARK: Classificação

    /// Por palavra-chave, em texto já normalizado (minúsculas, sem acento).
    static func classify(_ t: String) -> QuestionKind {
        func has(_ words: String...) -> Bool { words.contains { phrase in " \(t) ".contains(" \(phrase) ") } }
        if has("da tempo", "da tempo de", "tenho tempo", "chego a tempo", "da pra", "da para", "consigo", "sobra tempo") && !has("quanto custa") {
            return .timeFor
        }
        if has("quanto custa", "quanto e", "quanto fica", "quanto sai", "quanto pago", "qual o preco", "qual preco", "preco", "custa", "ingresso custa", "e caro") {
            return .price
        }
        if has("abre", "abre que horas", "fecha", "que horas abre", "que horas fecha", "ate que horas", "horario", "esta aberto", "ta aberto", "aberto", "aberta", "funciona") {
            return .hours
        }
        if has("como chego", "como eu chego", "como vou", "como ir", "como faco pra chegar", "como faco para chegar", "como chegar", "como volto",
               "como fui", "qual caminho", "qual a rota", "rota pra", "ir de", "chegar em", "chegar no", "chegar na", "chegar ao") {
            return .route
        }
        if has("vale a pena", "vale ir", "vale a visita", "vale", "compensa", "e bom", "presta") {
            return .worth
        }
        if has("o que eu faco agora", "o que faco agora", "o que fazer agora", "o que fazer", "o que tem perto", "o que tem por perto", "o que tem aqui",
               "o que tem por aqui", "o que ha perto", "o que posso fazer", "o que fazer agora", "e agora", "o que eu faco", "tem algo perto",
               "tem alguma coisa perto", "qual a proxima", "qual proxima parada", "o que vem agora") {
            return .nowNearby
        }
        return .unknown
    }

    // MARK: Reconhecer o lugar

    private static let nameStopwords: Set<String> = [
        "de", "do", "da", "dos", "das", "e", "o", "a", "os", "as", "em", "no", "na", "the", "restaurante", "bar", "cafe", "casa", "loja",
        "museu", "parque", "ramen", "templo", "santuario",
    ]

    /// O lugar do board citado no texto (nome ou nome local latino; tolerante a acento e caixa). Prefere a cidade de hoje.
    static func findPlace(in normalizedText: String, snapshot s: AssistantSnapshot) -> SolverPlace? {
        let textTokens = Set(normalizedText.split(separator: " ").map(String.init))
        let padded = " \(normalizedText) "
        var best: (place: SolverPlace, score: Double)?
        for p in s.catalog {
            var top = 0.0
            for candidate in [p.name, p.nameLocal].compactMap({ $0 }) {
                let name = QueroQuestion.normalize(candidate)
                guard !name.isEmpty else { continue }
                if padded.contains(" \(name) ") { top = max(top, 2 + Double(name.count) / 100); continue }
                let tokens = name.split(separator: " ").map(String.init).filter { $0.count >= 3 && !nameStopwords.contains($0) }
                guard !tokens.isEmpty else { continue }
                let hit = tokens.filter { token in textTokens.contains(token) || textTokens.contains { $0.count >= 5 && token.hasPrefix($0) } }
                let longest = hit.map(\.count).max() ?? 0
                guard longest >= 4 else { continue }
                let ratio = Double(hit.count) / Double(tokens.count)
                // Nome curto (1–2 palavras úteis) precisa casar inteiro; nome longo, mais da metade.
                guard tokens.count <= 2 ? ratio >= 1 : ratio > 0.5 else { continue }
                top = max(top, ratio)
            }
            guard top > 0 else { continue }
            let score = top + (AssistantEngine.sameCity(p, s) ? 0.5 : 0)
            if best == nil || score > best!.score { best = (p, score) }
        }
        return best?.place
    }

    static func findArea(in normalizedText: String, snapshot s: AssistantSnapshot) -> Area? {
        let padded = " \(normalizedText) "
        return AreaCatalog.areas(for: s.region).first { area in
            ([area.name] + area.aliases).contains { alias in
                let n = QueroQuestion.normalize(alias)
                return n.count >= 3 && padded.contains(" \(n) ")
            }
        }
    }

    // MARK: Origem, deslocamento e relógio

    /// De onde se parte: GPS, senão o lugar da parada de agora/próxima do dia.
    static func origin(_ s: AssistantSnapshot, clock: DayClock?) -> (coordinate: CLLocationCoordinate2D, basis: String)? {
        if let here = s.here { return (here, "daqui") }
        if let current = clock?.now?.current ?? clock?.upcoming?.stop, let c = coordinate(of: current, snapshot: s) {
            return (c, "de \(current.label)")
        }
        if let next = s.nextStop { return (next.place.coordinate, "de \(next.place.name)") }
        return nil
    }

    static func coordinate(of stop: DayStop, snapshot s: AssistantSnapshot) -> CLLocationCoordinate2D? {
        if let lat = stop.lat, let lng = stop.lng { return CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        return stop.placeId.flatMap { id in s.catalog.first { $0.id == id }?.coordinate }
    }

    static func leg(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, snapshot s: AssistantSnapshot) -> Leg {
        DaySolver.leg(a, b, walkMax: s.walkMaxKm)
    }

    /// Próxima âncora fixa (reserva/ingresso) que ainda não começou: do relógio, senão das paradas do snapshot.
    struct Anchor { var label: String; var start: Date; var coordinate: CLLocationCoordinate2D? }

    static func nextAnchor(_ s: AssistantSnapshot, clock: DayClock?) -> Anchor? {
        if let plan = clock?.active {
            if let a = plan.stops.filter({ $0.kind == .anchor && $0.start > s.now }).min(by: { $0.start < $1.start }) {
                return Anchor(label: a.label, start: a.start, coordinate: coordinate(of: a, snapshot: s))
            }
            return nil
        }
        if let a = s.stops.filter({ $0.isAnchor && !$0.done && $0.at > s.now }).min(by: { $0.at < $1.at }) {
            return Anchor(label: a.place.name, start: a.at, coordinate: a.place.coordinate)
        }
        return nil
    }

    // MARK: Horário

    /// Horário com confiança: `confirmed` só com períodos do Google.
    struct HoursFact {
        var confirmed: Bool
        var openAtArrival: Bool?
        var closesAt: String?
        var todayText: String?
    }

    static func hoursFact(_ p: SolverPlace, at date: Date, tz: TimeZone) -> HoursFact {
        guard let h = p.hours, h.hasPeriods else { return HoursFact(confirmed: false, openAtArrival: nil, closesAt: nil, todayText: nil) }
        return HoursFact(confirmed: true, openAtArrival: h.isOpen(at: date, timeZone: tz), closesAt: h.closesAt(date, timeZone: tz),
                         todayText: h.todayText(date, timeZone: tz))
    }

    private static func clockDate(_ hhmm: String, near date: Date, region: Region) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var cal = region.calendar
        cal.timeZone = region.timeZone
        let base = cal.startOfDay(for: date)
        guard let d = cal.date(byAdding: .minute, value: parts[0] * 60 + parts[1], to: base) else { return nil }
        // Fechar às 01:00 depois da meia-noite: o relógio de fechamento cai no dia seguinte.
        return d < date.addingTimeInterval(-3600) ? cal.date(byAdding: .day, value: 1, to: d) : d
    }

    // MARK: Tipos de pergunta

    static func timeFor(_ p: SolverPlace, snapshot s: AssistantSnapshot, clock: DayClock?) -> QuestionAnswer {
        let r = s.region
        func out(_ text: String) -> QuestionAnswer { QuestionAnswer(kind: .timeFor, text: text, placeId: p.id, recognized: true) }
        guard let from = origin(s, clock: clock) else {
            return out("Não sei de onde você parte (sem localização e sem dia montado), então não calculo o deslocamento até \(p.name).")
        }
        let travel = leg(from: from.coordinate, to: p.coordinate, snapshot: s)
        let stay = DaySolver.duration(p)
        let arrive = s.now.addingTimeInterval(Double(travel.minutes) * 60)
        let leaveThere = arrive.addingTimeInterval(Double(stay) * 60)
        let way = travel.mode == .walk ? "a pé" : "de trem"
        var head = "\(travel.minutes) min \(way) até lá, fica \(durationText(stay))"
        var problems: [String] = []
        var notes: [String] = []

        // Horário do lugar.
        let fact = hoursFact(p, at: arrive, tz: r.timeZone)
        if fact.confirmed {
            if fact.openAtArrival == false {
                let next = p.hours?.nextOpening(after: arrive, timeZone: r.timeZone)
                problems.append("fechado quando você chega (\(r.timeString(arrive)))" + (next.map { " — abre \($0.day.map { "\($0) " } ?? "")às \($0.time)" } ?? ""))
            } else if let close = fact.closesAt, let closeDate = clockDate(close, near: arrive, region: r), closeDate < leaveThere {
                let left = max(0, Int(closeDate.timeIntervalSince(arrive) / 60))
                problems.append("fecha às \(close), sobram \(left) min lá")
            }
        } else {
            notes.append(PlaceTrust.hoursEstimated)
        }

        // Próxima âncora.
        if let anchor = nextAnchor(s, clock: clock) {
            let back = anchor.coordinate.map { leg(from: p.coordinate, to: $0, snapshot: s).minutes } ?? 0
            let leaveBy = anchor.start.addingTimeInterval(-Double(back + margin) * 60)
            if leaveThere <= leaveBy {
                head += ", sai às \(r.timeString(leaveBy)) pro \(anchor.label) das \(r.timeString(anchor.start))"
            } else {
                let over = Int(leaveThere.timeIntervalSince(leaveBy) / 60)
                problems.append("passa \(over) min da hora de sair pro \(anchor.label) das \(r.timeString(anchor.start)) (saída \(r.timeString(leaveBy)))")
            }
        }

        let verdict = problems.isEmpty ? "Dá" : "Não dá"
        var text = "\(verdict): \(head)"
        if !problems.isEmpty { text += ". Motivo: " + problems.joined(separator: "; ") }
        text += "."
        if !notes.isEmpty { text += " (" + notes.joined(separator: ", ") + ")" }
        if problems.isEmpty, fact.confirmed == false { text = text.replacingOccurrences(of: "Dá:", with: "Dá, pelo que sei:") }
        return out(text)
    }

    static func price(_ p: SolverPlace, snapshot s: AssistantSnapshot) -> QuestionAnswer {
        let r = s.region
        var bits: [String] = []
        if let art = p.extra?.art, let adult = art.priceAdult {
            bits.append(adult == 0 ? "entrada grátis" : "entrada \(r.money(adult))" + (art.priceStudent.map { " (estudante \(r.money($0)))" } ?? ""))
        }
        if let price = p.price, price > 0 { bits.append("cerca de \(r.money(price)) por pessoa (valor do board)") }
        if p.price == 0, bits.isEmpty { bits.append("grátis") }
        let paid = p.tickets.compactMap(\.paid).reduce(0, +)
        if paid > 0 { bits.append("ingresso já pago: \(r.money(paid))") }
        if let session = p.extra?.art?.sessions.filter({ $0.at > s.now && !$0.soldOut }).min(by: { $0.at < $1.at }), let sp = session.price {
            bits.append("sessão \(r.shortDayTime(session.at)) por \(r.money(sp))")
        }
        let text = bits.isEmpty ? "\(p.name): sem preço guardado." : "\(p.name): " + bits.joined(separator: " · ") + "."
        return QuestionAnswer(kind: .price, text: text, placeId: p.id, recognized: true)
    }

    static func hours(_ p: SolverPlace, snapshot s: AssistantSnapshot) -> QuestionAnswer {
        let r = s.region
        func out(_ text: String) -> QuestionAnswer { QuestionAnswer(kind: .hours, text: text, placeId: p.id, recognized: true) }
        let fact = hoursFact(p, at: s.now, tz: r.timeZone)
        guard fact.confirmed else {
            let windows = p.windows.isEmpty ? "" : " Pelo board é de " + p.windows.map(\.label).joined(separator: " e ") + "."
            return out("\(p.name): sem horário confirmado (\(PlaceTrust.hoursEstimated)).\(windows) Sincronize em Ajustes pra ver o do Google.")
        }
        var text = "\(p.name): hoje \(fact.todayText ?? "sem horário")"
        if fact.openAtArrival == true {
            text += fact.closesAt.map { ". Aberto agora, fecha às \($0)" } ?? ". Aberto agora (24 h)"
        } else if let next = p.hours?.nextOpening(after: s.now, timeZone: r.timeZone) {
            text += ". Fechado agora, abre \(next.day.map { "\($0) " } ?? "")às \(next.time)"
        } else {
            text += ". Fechado agora"
        }
        return out(text + ".")
    }

    static func route(to dest: CLLocationCoordinate2D, name: String, placeId: String?, snapshot s: AssistantSnapshot, clock: DayClock?,
                      area: Area? = nil) -> QuestionAnswer {
        func out(_ text: String) -> QuestionAnswer { QuestionAnswer(kind: .route, text: text, placeId: placeId, recognized: true) }
        guard let from = origin(s, clock: clock) else {
            return out("Não sei de onde você parte (sem localização e sem dia montado). Abra \(name) no mapa pra traçar a rota.")
        }
        // Linha: a perna do dia (se o destino é parada) ou o vizinho direto da tabela de bairros.
        var line: String?
        if let placeId, let plan = clock?.active, let stop = plan.stops.first(where: { $0.placeId == placeId }),
           let leg = plan.leg(before: stop), !leg.detail.isEmpty {
            line = leg.detail
        }
        if line == nil, let area, let current = AreaCatalog.areas(for: s.region).first(where: { $0.name == s.areaName }),
           let n = current.neighbors.first(where: { $0.areaId == area.id }) {
            line = "\(n.mode.label)\(n.line.map { " · \($0.name)" } ?? "") \(n.minutes) min"
        }
        let l = leg(from: from.coordinate, to: dest, snapshot: s)
        let mode = l.mode == .walk ? "a pé" : "de trem/metrô"
        var text = "Até \(name): \(l.minutes) min \(mode) (\(Walk.distanceText(l.km * 1000)))"
        if let line { text += " · \(line)" }
        text += ". Estimativa sem rede; o Ir mostra a rota de verdade."
        return out(text)
    }

    static func worth(_ p: SolverPlace, snapshot s: AssistantSnapshot) -> QuestionAnswer {
        let r = s.region
        var bits: [String] = []
        bits.append("\(p.name) é um \(s.listName(p))" + (p.area.map { " em \($0)" } ?? ""))
        let note = p.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { bits.append("sua nota: “\(QueroQuestion.shorten(note, maxCharacters: 140))”") }
        if p.done { bits.append("você já foi (済)") }
        if p.saveForEnd { bits.append("fica pro fim da viagem") }
        if p.reservation != nil { bits.append("tem reserva marcada") }
        if let day = s.stops.first(where: { $0.place.id == p.id }) { bits.append("está no dia de hoje às \(r.timeString(day.at))") }
        if !AssistantEngine.sameCity(p, s) { bits.append("é de outra cidade, não entra no dia de hoje") }
        if let kind = AssistantEngine.kindNote(p, s) { bits.append(kind) }
        let text = bits.joined(separator: " · ") + "."
        let honest = note.isEmpty && !p.saveForEnd ? " Não tenho nota nem avaliação guardada pra dizer mais." : ""
        return QuestionAnswer(kind: .worth, text: text + honest, placeId: p.id, recognized: true)
    }

    static func nowNearby(snapshot s: AssistantSnapshot, clock: DayClock?) -> QuestionAnswer {
        let r = s.region
        func out(_ text: String, _ id: String? = nil) -> QuestionAnswer { QuestionAnswer(kind: .nowNearby, text: text, placeId: id, recognized: true) }
        // 1) O dia manda: parada de agora / próxima.
        if let now = clock?.now {
            var text = "Agora: \(now.current.label)"
            if let time = clock?.actionTime { text += " — \(clock?.actionVerb ?? "saia") às \(r.timeString(time))" }
            if let next = now.next { text += ", depois \(next.label) às \(r.timeString(next.start))" }
            return out(text + ".", now.current.placeId)
        }
        if let up = clock?.upcoming {
            return out("O dia começa com \(up.stop.label) às \(r.timeString(up.stop.start)); saia às \(r.timeString(up.leaveAt)).", up.stop.placeId)
        }
        if clock == nil, let next = s.nextStop {
            return out("Próxima do dia: \(next.place.name) às \(r.timeString(next.at)).", next.place.id)
        }
        // 2) Sem dia (ou acabou): o que está aberto perto.
        let (places, confirmed) = AssistantEngine.openNow(s)
        if let top = places.first {
            let names = places.prefix(3).map(\.name).joined(separator: ", ")
            let text = confirmed ? "Aberto agora perto de \(s.areaName): \(names)." : "Perto de \(s.areaName): \(names) — \(PlaceTrust.hoursUnconfirmed)."
            return out(text, top.id)
        }
        return out("Sem dia montado e nada do board num raio de 1,5 km de \(s.areaName).")
    }

    static func unknown() -> QuestionAnswer {
        QuestionAnswer(kind: .unknown, recognized: false, text: "Respondo aqui: dá tempo de um lugar, quanto custa, que horas abre ou fecha, como chegar, se vale a pena e o que fazer agora. Pra outra coisa, use Continuar no Assistente.")
    }

    private static func needsPlace(_ kind: QuestionKind, _ what: String) -> QuestionAnswer {
        QuestionAnswer(kind: kind, text: "Não achei esse lugar no board desta viagem, então não invento \(what). Diga o nome como está no board, ou continue no Assistente.",
                       placeId: nil, recognized: false)
    }

    static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
}

private extension QuestionAnswer {
    init(kind: QuestionKind, recognized: Bool, text: String) {
        self.init(kind: kind, text: text, placeId: nil, recognized: recognized)
    }
}

private extension SolverPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}
