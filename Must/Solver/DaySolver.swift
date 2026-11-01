import CoreLocation
import Foundation

/// Monta o dia a partir do board. Determinístico: mesmo pedido + mesma semente → mesmo dia.
/// Regras (ver `prompts/05-dia.md`): âncoras → cidade → fica pro fim → janelas/uma refeição →
/// horários → orçamento → tipo de dia → andar → tempo → explicação.
enum DaySolver {
    // MARK: Janelas

    /// Minutos desde a meia-noite [início, fim).
    static func range(_ window: DayWindow, startEarly: Bool = false) -> Range<Int> {
        switch window {
        case .morning: (startEarly ? 8 * 60 + 30 : 9 * 60 + 30)..<(11 * 60 + 30)
        case .lunch: (11 * 60 + 30)..<(14 * 60 + 30)
        case .afternoon: (14 * 60 + 30)..<(18 * 60)
        case .dinner: (18 * 60)..<(21 * 60)
        case .night: (21 * 60)..<(24 * 60 + 30)
        }
    }

    static func window(at minute: Int) -> DayWindow {
        DayWindow.allCases.first { range($0, startEarly: true).contains(minute) } ?? (minute < 9 * 60 ? .morning : .night)
    }

    // MARK: Deslocamento

    /// km de rua (linha reta × 1,25).
    static func streetKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000 * 1.25
    }

    /// A pé até `walkMaxKm` (80 m/min); acima, metrô (2,5 min/km + 6 min).
    static func leg(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, walkMax walkMaxKm: Double) -> Leg {
        let km = streetKm(a, b)
        if km <= walkMaxKm { return Leg(km: km, mode: .walk, minutes: Int((km * 1000 / Walk.metersPerMinute).rounded(.up))) }
        // Acima de 25 km é trem/ônibus regional (Fuji, Inhotim): ~65 km/h + 20 min de espera.
        if km > 25 { return Leg(km: km, mode: .metro, minutes: Int((km * 0.9 + 20).rounded(.up))) }
        return Leg(km: km, mode: .metro, minutes: Int((km * 2.5 + 6).rounded(.up)))
    }

    static func walkLimitKm(_ walk: WalkLevel) -> Double {
        switch walk {
        case .low: 2
        case .normal: 4.5
        case .high: .infinity
        }
    }

    static func effectiveWalkMax(_ request: DayRequest, walk: WalkLevel) -> Double {
        switch walk {
        case .low: min(request.walkMaxKm, 0.8)
        case .normal: request.walkMaxKm
        case .high: request.walkMaxKm * 1.5
        }
    }

    // MARK: Plano por tipo de dia

    struct Slot {
        var window: DayWindow
        /// Papéis aceitos, em ordem de preferência.
        var roles: [StopRole]
        var optional = false
        /// Horário pela luz (golden, azul, sol alto) ou pela janela boa de esporte, em vez da janela fixa.
        var timing: Timing? = nil
    }

    struct Plan {
        var slots: [Slot]
        var required: [StopRole]
        var maxStops: Int
        var startMinute: Int?
        var excluded: Set<StopRole> = []

        var roles: Set<StopRole> { Set(slots.flatMap(\.roles)) }
    }

    static func plan(for kind: DayKind) -> Plan {
        switch kind {
        case .free:
            Plan(slots: [Slot(window: .morning, roles: [.sport], optional: true, timing: .sport),
                         Slot(window: .morning, roles: [.see, .drink, .shop]), Slot(window: .lunch, roles: [.eat]),
                         Slot(window: .afternoon, roles: [.see, .drink, .photo]),
                         Slot(window: .night, roles: [.listen, .drink], optional: true),
                         Slot(window: .dinner, roles: [.eat], optional: true)],
                 required: [.see, .eat, .drink], maxStops: 4)
        case .shopping:
            Plan(slots: [Slot(window: .morning, roles: [.shop, .drink], optional: true), Slot(window: .lunch, roles: [.eat]),
                         Slot(window: .afternoon, roles: [.shop]), Slot(window: .afternoon, roles: [.drink, .shop], optional: true),
                         Slot(window: .dinner, roles: [.eat], optional: true)],
                 required: [.shop, .eat], maxStops: 5, excluded: [.listen])
        case .night:
            Plan(slots: [Slot(window: .lunch, roles: [.eat]), Slot(window: .afternoon, roles: [.see, .drink], optional: true),
                         Slot(window: .dinner, roles: [.eat]), Slot(window: .night, roles: [.listen, .drink]),
                         Slot(window: .night, roles: [.drink, .listen], optional: true)],
                 required: [.eat, .listen], maxStops: 5, startMinute: 12 * 60)
        case .photo:
            // Golden da manhã → sol alto no museu → almoço → golden da tarde → hora azul.
            Plan(slots: [Slot(window: .morning, roles: [.photo, .see], timing: .goldenAM),
                         Slot(window: .lunch, roles: [.see], optional: true, timing: .sunHigh),
                         Slot(window: .lunch, roles: [.eat]),
                         Slot(window: .afternoon, roles: [.photo, .see], timing: .goldenPM),
                         Slot(window: .night, roles: [.photo], optional: true, timing: .blue),
                         Slot(window: .dinner, roles: [.eat], optional: true)],
                 required: [.photo, .eat], maxStops: 6)
        case .temples:
            Plan(slots: [Slot(window: .morning, roles: [.see]), Slot(window: .lunch, roles: [.eat]),
                         Slot(window: .afternoon, roles: [.see, .drink]), Slot(window: .afternoon, roles: [.drink], optional: true)],
                 required: [.see, .eat], maxStops: 4)
        case .rest:
            Plan(slots: [Slot(window: .lunch, roles: [.eat]), Slot(window: .afternoon, roles: [.drink]),
                         Slot(window: .afternoon, roles: [.see, .drink], optional: true)],
                 required: [.eat], maxStops: 3, startMinute: 11 * 60)
        }
    }

    // MARK: Elegibilidade

    struct Context {
        var request: DayRequest
        var kind: DayKind
        var budget: Double
        var walk: WalkLevel
        var startEarly: Bool
        var plan: Plan
        var mustInclude: Set<String>
        var mustExclude: Set<String>
        /// Luz do dia na cidade (sem rede).
        var sun: SunDay

        init(_ request: DayRequest, catalog: [SolverPlace]) {
            self.request = request
            sun = SunService.day(request.date.addingTimeInterval(12 * 3600), request.cityCenter ?? request.origin, timeZone: request.timeZone)
            let intent = request.intent
            kind = intent.kind ?? request.kind
            budget = intent.budget ?? request.budget
            walk = kind == .rest ? .low : (intent.walk ?? request.walk)
            startEarly = intent.startEarly ?? (kind == .temples || kind == .photo)
            plan = DaySolver.plan(for: kind)
            func ids(_ names: [String]) -> Set<String> {
                Set(catalog.filter { p in names.contains { PlaceMatcher.similar($0, p.name) || p.name.localizedCaseInsensitiveContains($0) } }.map(\.id))
            }
            mustInclude = ids(intent.mustInclude)
            mustExclude = ids(intent.mustExclude)
        }

        func mode(_ p: SolverPlace) -> ListMode {
            let m = request.lists[p.listId] ?? .auto
            if m == .auto, let fromText = request.intent.roles[p.role] { return fromText }
            return m
        }

        func minute(_ date: Date) -> Int {
            Int(date.timeIntervalSince(request.date) / 60)
        }

        func date(_ minute: Int) -> Date { request.date.addingTimeInterval(TimeInterval(minute * 60)) }
    }

    /// Motivo pra não entrar (nil = elegível). `silent` = não vale citar na explicação.
    static func ineligibility(_ p: SolverPlace, _ ctx: Context) -> (reason: String, silent: Bool)? {
        let req = ctx.request
        let forced = ctx.mustInclude.contains(p.id)
        if p.done { return ("já feito", true) }
        if ctx.mustExclude.contains(p.id) { return ("você pediu pra tirar", false) }
        if p.cityId != req.cityId { return ("outra cidade", true) }
        let mode = ctx.mode(p)
        let rare = p.rules.isRareToday(weekday: req.weekday)
        if mode == .off && !forced { return ("lista desligada", true) }
        if ctx.plan.excluded.contains(p.role) && mode != .on && !forced { return ("dia de \(ctx.kind.label)", true) }
        if mode == .auto && !ctx.plan.roles.contains(p.role) && !rare && !forced { return ("não é desse tipo de dia", true) }
        if p.saveForEnd && !forced {
            if let left = req.daysLeftInCity {
                if left > 1 { return ("fica pro fim — entra nos últimos dias da cidade", false) }
            } else if req.lists[p.listId] != .on {
                return ("fica pro fim — ligue a lista pra entrar", false)
            }
        }
        if p.rules.fullDay && !forced { return ("dia inteiro — peça pra ir", false) }
        if let blocked = p.rules.blocks(weekday: req.weekday) { return (blocked, false) }
        if p.rules.crowdedDays.contains(req.weekday) && !forced {
            return ("\(NotesRules.fullNames[req.weekday]) lota", false)
        }
        if p.rules.weatherDependent {
            guard let weather = req.weather else { return ("só com céu limpo · sem previsão ainda", false) }
            if !weather.isClear { return ("só com céu limpo", false) }
        }
        if p.rules.outdoor, req.weather?.isHeavyRain == true { return ("chuva forte", false) }
        if let art = p.extra?.art, !art.isRunning(on: req.date, calendar: req.calendar) {
            if let until = art.runsUntil, ArtEvent.localDay(until, calendar: req.calendar) < req.date { return ("temporada acabou", false) }
            return ("temporada ainda não começou", false)
        }
        if p.role == .sport {
            if p.extra?.sport?.activity == .watch { return ("jogo: só com ingresso comprado", true) }
            if (req.weather?.hours ?? []).isEmpty && !forced { return ("sem previsão hora a hora", true) }
        }
        if let hours = p.hours, hours.hasPeriods {
            let opensToday = (hours.periods ?? []).contains { $0.open.day == req.weekday }
            let openFromYesterday = (hours.periods ?? []).contains { $0.open.day == (req.weekday + 6) % 7 && ($0.close?.day ?? -1) == req.weekday }
            if !opensToday && !openFromYesterday { return ("fecha \(NotesRules.fullNames[req.weekday])", false) }
        }
        return nil
    }

    // MARK: Solver

    static func solve(_ request: DayRequest, catalog: [SolverPlace]) -> DayProposal {
        let ctx = Context(request, catalog: catalog)
        let req = request
        var leftOut: [LeftOut] = []
        var rejection: [String: String] = [:]

        // 1. Âncoras: reservas do dia, na cidade do dia.
        var anchors: [ProposedStop] = []
        var spend = 0.0
        var exceptionSpend = 0.0
        var hasException = false
        for p in catalog where !p.done {
            guard let r = p.reservation, req.calendar.isDate(r.at, inSameDayAs: req.date) else { continue }
            guard p.cityId == req.cityId else { leftOut.append(LeftOut(place: p, reason: "outra cidade")); continue }
            if ctx.mustExclude.contains(p.id) { continue }
            let minute = ctx.minute(r.at)
            let duration = p.role == .eat ? 105 : p.role.duration
            var exception = false
            if spend + p.cost > ctx.budget, p.allowBudgetException, !hasException {
                exception = true
                hasException = true
                exceptionSpend += p.cost
            } else {
                spend += p.cost
            }
            anchors.append(ProposedStop(place: p, at: r.at, end: ctx.date(minute + duration), window: window(at: minute),
                                        reason: "reserva", isAnchor: true, isException: exception, legFromPrevious: nil))
        }
        anchors += ticketAnchors(catalog, ctx: ctx).filter { t in !anchors.contains { $0.place.id == t.place.id } }
        anchors.sort { $0.at < $1.at }

        // 2–9. Candidatos elegíveis.
        var candidates: [SolverPlace] = []
        let anchorIds = Set(anchors.map(\.place.id))
        for p in catalog where !anchorIds.contains(p.id) {
            if let blocked = ineligibility(p, ctx) {
                if !blocked.silent { leftOut.append(LeftOut(place: p, reason: blocked.reason)) }
            } else {
                candidates.append(p)
            }
        }

        // Necessidades do tipo de dia (as âncoras já contam).
        var needed = ctx.plan.required
        for a in anchors { if let i = needed.firstIndex(of: a.place.role) { needed.remove(at: i) } }
        var mealUsed: Set<DayWindow> = Set(anchors.filter { $0.place.role == .eat }.map(\.window).filter(\.isMeal))

        var departure = ctx.minute(req.startAt)
        if req.intent.startEarly == true { departure = min(departure, 8 * 60) }
        // Dia de fotografia começa no golden da manhã (salvo "sem acordar cedo").
        if ctx.kind == .photo, req.intent.startEarly != false, let golden = range(.goldenAM, sun: ctx.sun, ctx: ctx) {
            departure = min(departure, golden.lowerBound - 30)
        }
        let startMinute = max(departure, ctx.plan.startMinute ?? 0)
        let walkMax = effectiveWalkMax(req, walk: ctx.walk)
        var chosen: [ProposedStop] = []
        var cursorMinute = startMinute
        var cursorLocation = req.origin
        var anchorIndex = 0

        func passAnchors(before minute: Int) {
            while anchorIndex < anchors.count, ctx.minute(anchors[anchorIndex].at) <= minute {
                let a = anchors[anchorIndex]
                cursorMinute = max(cursorMinute, ctx.minute(a.end))
                cursorLocation = CLLocationCoordinate2D(latitude: a.place.lat, longitude: a.place.lng)
                anchorIndex += 1
            }
        }

        var slots = ctx.plan.slots
        // Duas refeições no mesmo almoço quando pedido ("sushi e ramen").
        if req.intent.mealsException { slots.insert(Slot(window: .lunch, roles: [.eat]), at: slots.firstIndex { $0.window == .lunch }.map { $0 + 1 } ?? 0) }
        // Lugar raro de hoje (Feira Hippie no domingo) ganha uma vaga na janela dele.
        for p in candidates where p.rules.isRareToday(weekday: req.weekday) {
            let w = p.rules.onlyWindows?.first ?? p.windows.first ?? .morning
            if !slots.contains(where: { $0.window == w && $0.roles.contains(p.role) }) {
                slots.append(Slot(window: w, roles: [p.role]))
            }
        }
        func slotStart(_ slot: Slot) -> Int {
            if let t = slot.timing { return range(t, sun: ctx.sun, ctx: ctx)?.lowerBound ?? range(slot.window).lowerBound }
            return range(slot.window).lowerBound
        }
        slots = slots.enumerated().sorted { a, b in
            let ra = slotStart(a.element), rb = slotStart(b.element)
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
        var usedLights: Set<LightKind> = Set(anchors.compactMap { lightAt($0, ctx: ctx) })
        let hourly = req.weather?.hours ?? []

        let totalLimit = ctx.plan.maxStops + (req.intent.mealsException ? 1 : 0)
            + candidates.filter { $0.rules.isRareToday(weekday: req.weekday) }.count

        for slot in slots {
            // Esporte é extra: não ocupa vaga do dia.
            let count = chosen.filter { $0.place.role != .sport }.count + anchors.count
            if slot.optional && count >= ctx.plan.maxStops { continue }
            if count >= totalLimit { break }
            if slot.window.isMeal && mealUsed.contains(slot.window) && req.oneMealPerWindow
                && !(req.intent.mealsException && slot.window == .lunch && chosen.filter({ $0.window == .lunch && $0.place.role == .eat }).count < 2) {
                continue
            }
            let w: Range<Int>
            if let timing = slot.timing {
                guard let r = range(timing, sun: ctx.sun, ctx: ctx) else { continue }
                if let light = timing.light, light != .hard, usedLights.contains(light) { continue }
                w = r
            } else {
                w = range(slot.window, startEarly: ctx.startEarly)
            }
            if w.upperBound <= startMinute { continue }

            // Tenta antes e depois da próxima âncora.
            var best: (stop: ProposedStop, score: Double)?
            for phase in 0..<2 {
                if phase == 1 {
                    guard anchorIndex < anchors.count, ctx.minute(anchors[anchorIndex].at) < w.upperBound else { break }
                    passAnchors(before: ctx.minute(anchors[anchorIndex].at))
                }
                let nextAnchor = anchorIndex < anchors.count ? anchors[anchorIndex] : nil
                for p in candidates where !chosen.contains(where: { $0.place.id == p.id }) && slot.roles.contains(p.role) {
                    if slot.timing == nil {
                        if !p.windows.isEmpty && !p.windows.contains(slot.window) { continue }
                        if let only = p.rules.onlyWindows, !only.contains(slot.window) { continue }
                    } else if p.role == .see && slot.timing != .sunHigh && !isOutdoorSee(p) {
                        continue
                    }
                    let here = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
                    let legIn = leg(cursorLocation, here, walkMax: walkMax)
                    var start = max(w.lowerBound, cursorMinute + legIn.minutes, startMinute)
                    var length = duration(p) + (p.queueMinutes ?? 0)
                    var light: LightKind?

                    // photo: só na luz que o spot pede; uma vez por faixa; nuvens > 60% derrubam o golden.
                    if p.role == .photo {
                        let wants = p.extra?.photo?.bestLight ?? []
                        let options: [(LightKind, Range<Int>)]
                        if let timing = slot.timing, let l = timing.light, let r = range(timing, sun: ctx.sun, ctx: ctx) {
                            let ok = wants.isEmpty || wants.contains(l) || (l == .blue && wants.contains(.night))
                            options = ok ? [(l, r)] : []
                        } else {
                            let pool: [LightKind] = wants.isEmpty ? [.goldenPM, .goldenAM, .blue] : wants
                            options = pool.compactMap { l in
                                let t: Timing? = switch l { case .goldenAM: .goldenAM; case .goldenPM: .goldenPM; case .blue, .night: .blue; case .hard: nil }
                                guard let t, let r = range(t, sun: ctx.sun, ctx: ctx), w.overlaps(r) else { return nil }
                                return (l == .night ? .blue : l, r)
                            }
                        }
                        let cursorStart = max(cursorMinute + legIn.minutes, startMinute)
                        guard let pick = options.first(where: { !usedLights.contains($0.0) && max($0.1.lowerBound, cursorStart) <= $0.1.upperBound - 15 }) else {
                            rejection[p.id] = rejection[p.id] ?? "fora da luz boa"
                            continue
                        }
                        if pick.0 == .goldenPM || pick.0 == .goldenAM,
                           let cloud = req.weather?.hour(at: ctx.date(pick.1.lowerBound))?.cloud, cloud > 60 {
                            rejection[p.id] = "nublado no golden (\(cloud)%)"
                            continue
                        }
                        light = pick.0
                        start = max(pick.1.lowerBound, cursorStart)
                        length = max(15, min(45, pick.1.upperBound - start))
                    }

                    // sport: só em horas verdes (temperatura, UV, chuva, ar).
                    if p.role == .sport, let spot = p.extra?.sport {
                        var found: Int?
                        var m = start
                        while m + length <= max(w.upperBound, start + length) && m < w.upperBound {
                            let a = req.weather?.hour(at: ctx.date(m)), b = req.weather?.hour(at: ctx.date(m + length))
                            if let a, SportScore.isGood(a, spot: spot), b.map({ SportScore.isGood($0, spot: spot) }) ?? true { found = m; break }
                            m += 15
                        }
                        guard let found else {
                            rejection[p.id] = sportRejection(spot, at: ctx.date(start), hourly: hourly) ?? "fora da janela boa"
                            continue
                        }
                        start = found
                    }

                    guard start < w.upperBound else { rejection[p.id] = rejection[p.id] ?? "não cabe no horário"; continue }
                    if let open = p.hours?.isOpen(at: ctx.date(start), timeZone: req.timeZone), !open {
                        rejection[p.id] = "fechado às \(String(format: "%02d:%02d", (start / 60) % 24, start % 60))"
                        continue
                    }
                    // art: última entrada e duração antes de fechar.
                    if p.kind == .art, let close = closingMinute(p, ctx: ctx) {
                        let lastEntry = close - (p.extra?.art?.lastEntryMinutes ?? 0)
                        if start > lastEntry || start + min(length, 45) > close {
                            rejection[p.id] = "última entrada \(String(format: "%02d:%02d", (lastEntry / 60) % 24, lastEntry % 60))"
                            continue
                        }
                        length = min(length, close - start)
                    }
                    let end = start + length
                    if let a = nextAnchor {
                        let toAnchor = leg(here, CLLocationCoordinate2D(latitude: a.place.lat, longitude: a.place.lng), walkMax: walkMax)
                        if end + toAnchor.minutes + 10 > ctx.minute(a.at) && start < ctx.minute(a.end) {
                            rejection[p.id] = rejection[p.id] ?? "não dá tempo antes da reserva"
                            continue
                        }
                    }
                    // Orçamento
                    var exception = false
                    if spend + p.cost > ctx.budget {
                        let splurgeHere = req.intent.splurge && (req.intent.splurgeWindow == nil || req.intent.splurgeWindow == slot.window)
                        let asked = splurgeHere || ctx.mustInclude.contains(p.id) || (ctx.kind == .shopping && p.role == .shop)
                        if p.allowBudgetException && !hasException && asked {
                            exception = true
                        } else {
                            rejection[p.id] = "fora do orçamento"
                            continue
                        }
                    }
                    var score = Double(legIn.minutes) + Double(p.queueMinutes ?? 0) * 0.3
                    if ctx.mustInclude.contains(p.id) { score -= 500 }
                    if p.rules.isRareToday(weekday: req.weekday) { score -= 120 }
                    if let sub = p.sub, req.intent.preferSubs.contains(sub) { score -= 60 }
                    if let i = slot.roles.firstIndex(of: p.role) { score += Double(i) * 25 }
                    if needed.contains(p.role) { score -= 40 }
                    if ctx.kind == .temples, p.sub == "Templos" || p.listColor == .temple { score -= 50 }
                    if ctx.kind == .photo, p.sub == "Mirante" || p.sub == "Arquitetura" || p.rules.outdoor { score -= 40 }
                    if light != nil { score -= 30 }
                    if slot.timing == .sunHigh, p.kind == .art { score -= 40 }
                    if let left = daysLeft(p, ctx: ctx), left <= 7 { score -= 80 - Double(left) * 5 }
                    score += tieBreak(p.id, seed: req.seed)
                    if best == nil || score < best!.score {
                        best = (ProposedStop(place: p, at: ctx.date(start), end: ctx.date(end), window: slot.window,
                                             reason: "", isAnchor: false, isException: exception, legFromPrevious: legIn), score)
                    }
                }
                if best != nil { break }
            }
            guard var pick = best?.stop else { continue }
            pick.reason = reason(for: pick, ctx: ctx)
            if pick.isException {
                hasException = true
                exceptionSpend += pick.place.cost
            } else {
                spend += pick.place.cost
            }
            chosen.append(pick)
            if let l = lightAt(pick, ctx: ctx) { usedLights.insert(l) }
            if let i = needed.firstIndex(of: pick.place.role) { needed.remove(at: i) }
            if pick.place.role == .eat, pick.window.isMeal { mealUsed.insert(pick.window) }
            cursorMinute = ctx.minute(pick.end)
            cursorLocation = CLLocationCoordinate2D(latitude: pick.place.lat, longitude: pick.place.lng)
        }

        // Quem foi avaliado e ficou de fora.
        let chosenIds = Set(chosen.map(\.place.id))
        for p in candidates where !chosenIds.contains(p.id) {
            if let r = rejection[p.id] { leftOut.append(LeftOut(place: p, reason: r)) }
        }

        let proposal = finalize(stops: anchors + chosen, request: req, ctx: ctx, leftOut: leftOut)
        return proposal
    }

    /// Ordena, calcula pernas, km a pé, metrô e gasto; escreve a explicação.
    static func finalize(stops raw: [ProposedStop], request: DayRequest, ctx: Context? = nil, leftOut: [LeftOut]) -> DayProposal {
        let ctx = ctx ?? Context(request, catalog: raw.map(\.place))
        let walkMax = effectiveWalkMax(request, walk: ctx.walk)
        var stops = raw.sorted { $0.at < $1.at }
        var previous = request.origin
        for i in stops.indices {
            let here = CLLocationCoordinate2D(latitude: stops[i].place.lat, longitude: stops[i].place.lng)
            stops[i].legFromPrevious = leg(previous, here, walkMax: walkMax)
            previous = here
        }
        // Teto de caminhada: as pernas a pé mais longas viram metrô.
        let limit = walkLimitKm(ctx.walk)
        var walkKm = stops.compactMap(\.legFromPrevious).filter { $0.mode == .walk }.reduce(0) { $0 + $1.km }
        while walkKm > limit {
            guard let i = stops.indices.filter({ stops[$0].legFromPrevious?.mode == .walk && (stops[$0].legFromPrevious?.km ?? 0) > 0.5 })
                .max(by: { stops[$0].legFromPrevious!.km < stops[$1].legFromPrevious!.km }) else { break }
            let km = stops[i].legFromPrevious!.km
            stops[i].legFromPrevious = Leg(km: km, mode: .metro, minutes: Int((km * 2.5 + 6).rounded(.up)))
            walkKm -= km
        }
        let legs = stops.compactMap(\.legFromPrevious)
        let spend = stops.filter { !$0.isException }.reduce(0) { $0 + $1.place.cost }
        let exception = stops.filter(\.isException).reduce(0) { $0 + $1.place.cost }
        let chosenIds = Set(stops.map(\.place.id))
        let left = dedupe(leftOut.filter { !chosenIds.contains($0.place.id) })
        return DayProposal(request: request, stops: stops, predictedSpend: spend, exceptionSpend: exception,
                           walkKm: legs.filter { $0.mode == .walk }.reduce(0) { $0 + $1.km },
                           transitLegs: legs.filter { $0.mode == .metro }.count,
                           leftOut: left, explanation: explanation(stops: stops, leftOut: left, request: request))
    }

    private static func dedupe(_ items: [LeftOut]) -> [LeftOut] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.place.id).inserted }
    }

    private static func tieBreak(_ id: String, seed: Int) -> Double {
        var hash: UInt64 = 1469598103934665603 &+ UInt64(bitPattern: Int64(seed &* 7919))
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Double(hash % 1000) / 1000 * (seed == 0 ? 2 : 14)
    }

    private static func reason(for stop: ProposedStop, ctx: Context) -> String {
        let p = stop.place
        let notes = p.notes.lowercased()
        if stop.isException { return "fora da meta do dia" }
        if p.role == .photo, let l = lightAt(stop, ctx: ctx) {
            return l == .blue ? "hora azul" : (l == .goldenAM ? "golden da manhã" : "golden")
        }
        if let left = daysLeft(p, ctx: ctx), left <= 7 { return endsText(left) }
        if p.kind == .art, ctx.kind == .photo, let r = range(.sunHigh, sun: ctx.sun, ctx: ctx), r.contains(ctx.minute(stop.at)) {
            return "hora do sol alto = museu"
        }
        if p.role == .sport, let h = ctx.request.weather?.hour(at: stop.at) { return "janela boa · \(Int(h.temp.rounded()))°" }
        if p.rules.isRareToday(weekday: ctx.request.weekday) { return "só hoje" }
        if ctx.mustInclude.contains(p.id) { return "você pediu" }
        if stop.window == .morning, notes.contains("antes da multidão") || notes.contains("cedo") { return "antes da multidão" }
        if let q = p.queueMinutes, q > 0 { return "fila ~\(q) min" }
        if p.hours == nil { return "horário não confirmado" }
        return stop.window.label
    }

    // MARK: Explicação

    /// Uma frase sobre o que ficou de fora (template, não LLM).
    static func explanation(stops: [ProposedStop], leftOut: [LeftOut], request: DayRequest) -> String {
        let priority = ["lota", "só ", "fecha", "não dá tempo", "fora do orçamento", "chuva", "céu limpo", "dia inteiro",
                        "fica pro fim", "fechado", "não cabe", "você pediu"]
        func rank(_ reason: String) -> Int { priority.firstIndex { reason.contains($0) } ?? priority.count }
        var parts: [String] = []
        if let top = leftOut.filter({ $0.reason != "outra cidade" }).min(by: { rank($0.reason) < rank($1.reason) }) {
            let others = leftOut.filter { $0.reason == top.reason && $0.place.id != top.place.id }.count
            let extra = others > 0 ? " (e mais \(others))" : ""
            parts.append("Deixei \(top.place.name)\(extra) de fora: \(top.reason).")
        }
        if let exception = stops.first(where: \.isException) {
            parts.append("\(exception.place.name) fica fora da meta do dia.")
        }
        // Temporada acabando (art): "quase âncora".
        let cal = request.calendar
        for stop in stops {
            if let left = stop.place.extra?.art?.daysLeft(from: request.date, calendar: cal), (0...7).contains(left) {
                parts.append("\(stop.place.name) \(endsText(left)) — entrou no dia.")
                break
            }
        }
        if let urgent = leftOut.first(where: { ($0.place.extra?.art?.daysLeft(from: request.date, calendar: cal)).map { (0...7).contains($0) } ?? false }),
           let left = urgent.place.extra?.art?.daysLeft(from: request.date, calendar: cal) {
            parts.append("\(urgent.place.name) \(endsText(left)) e não coube hoje (\(urgent.reason)).")
        }
        if parts.isEmpty {
            parts.append(stops.isEmpty ? "Não achei nada aberto que coubesse hoje — tenta outro tipo de dia." : "Tudo que fazia sentido hoje coube no dia.")
        }
        return parts.joined(separator: " ")
    }

    /// Faixa de luz em que a parada cai (só pra photo e âncoras).
    static func lightAt(_ stop: ProposedStop, ctx: Context) -> LightKind? {
        guard stop.place.role == .photo else { return nil }
        let m = ctx.minute(stop.at)
        for (l, t) in [(LightKind.goldenAM, Timing.goldenAM), (.goldenPM, .goldenPM), (.blue, .blue)] {
            if let r = range(t, sun: ctx.sun, ctx: ctx), (r.lowerBound - 5)..<r.upperBound ~= m { return l }
        }
        return nil
    }

    /// "see" que funciona com luz baixa: templo, mirante, arquitetura, parque, ao ar livre.
    static func isOutdoorSee(_ p: SolverPlace) -> Bool {
        if p.kind == .art { return false }
        if p.listColor == .temple { return true }
        if let sub = p.sub, ["Templos", "Mirante", "Arquitetura", "Parque"].contains(sub) { return true }
        return p.rules.outdoor
    }

    /// "quente · 31°", "UV 9", "chuva 60%", "ar ruim · AQI 140".
    static func sportRejection(_ spot: SportSpot, at date: Date, hourly: [HourWeather]) -> String? {
        guard let h = hourly.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }) else { return nil }
        let temp = h.apparent.map { max($0, h.temp) } ?? h.temp
        if temp > Double(spot.tempMax) { return "quente · \(Int(h.temp.rounded()))°" }
        if let uv = h.uv, uv > Double(spot.uvMax) { return "UV \(Int(uv.rounded())) alto" }
        if let rain = h.precipProb, rain >= 30 { return "chuva \(rain)%" }
        if let aqi = h.aqi, aqi >= 100 { return "ar ruim · AQI \(aqi)" }
        return nil
    }

    // MARK: Trocar

    /// Até 3 alternativas elegíveis na mesma janela, perto do trajeto.
    static func alternatives(for stopId: String, in proposal: DayProposal, catalog: [SolverPlace], filter: SwapFilter) -> [SwapAlternative] {
        guard let index = proposal.stops.firstIndex(where: { $0.id == stopId }) else { return [] }
        let stop = proposal.stops[index]
        let req = proposal.request
        let ctx = Context(req, catalog: catalog)
        let walkMax = effectiveWalkMax(req, walk: ctx.walk)
        let prev = index > 0 ? proposal.stops[index - 1].place : nil
        let next = index + 1 < proposal.stops.count ? proposal.stops[index + 1].place : nil
        let prevLoc = prev.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? req.origin
        let inDay = Set(proposal.stops.map(\.place.id))

        func cost(_ p: SolverPlace) -> Int {
            let c = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
            var m = leg(prevLoc, c, walkMax: walkMax).minutes
            if let next { m += leg(c, CLLocationCoordinate2D(latitude: next.lat, longitude: next.lng), walkMax: walkMax).minutes }
            return m
        }
        let base = cost(stop.place)

        let options = catalog.filter { p in
            guard !inDay.contains(p.id), p.role == stop.place.role else { return false }
            // Relaxa a regra de lista/tipo de dia (o usuário está escolhendo), mas não as regras duras.
            var relaxed = ctx
            relaxed.mustInclude.insert(p.id)
            if let blocked = ineligibility(p, relaxed), blocked.reason != "lista desligada" { return false }
            if !p.windows.isEmpty && !p.windows.contains(stop.window) { return false }
            if let open = p.hours?.isOpen(at: stop.at, timeZone: req.timeZone), !open { return false }
            switch filter {
            case .sameSub: return p.listId == stop.place.listId && (stop.place.sub == nil || p.sub == stop.place.sub)
            case .sameRole: return true
            case .cheaper: return p.cost < stop.place.cost
            case .noQueue: return (p.queueMinutes ?? 0) == 0
            }
        }
        return options
            .map { p -> SwapAlternative in
                let detour = cost(p) - base
                var notes: [String] = []
                if let area = p.area { notes.append(area) }
                notes.append((p.queueMinutes ?? 0) > 0 ? "fila ~\(p.queueMinutes!) min" : "sem fila")
                if let prev { notes.append("\(leg(CLLocationCoordinate2D(latitude: prev.lat, longitude: prev.lng), CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng), walkMax: walkMax).minutes) min do \(prev.name)") }
                return SwapAlternative(place: p, priceDelta: p.cost - stop.place.cost, detourMinutes: detour, note: notes.joined(separator: " · "))
            }
            .sorted { ($0.detourMinutes, $0.priceDelta) < ($1.detourMinutes, $1.priceDelta) }
            .prefix(3)
            .map { $0 }
    }

    /// Troca uma parada (não muda as outras), recalcula pernas e gasto.
    static func swap(_ stopId: String, with place: SolverPlace, in proposal: DayProposal) -> DayProposal {
        var stops = proposal.stops
        guard let i = stops.firstIndex(where: { $0.id == stopId }), !stops[i].isAnchor else { return proposal }
        let old = stops[i]
        let duration = place.role.duration + (place.queueMinutes ?? 0)
        let ctx = Context(proposal.request, catalog: [place])
        let overBudget = proposal.predictedSpend - (old.isException ? 0 : old.place.cost) + place.cost > ctx.budget
        let exception = overBudget && place.allowBudgetException && !stops.contains { $0.isException && $0.id != old.id }
        stops[i] = ProposedStop(place: place, at: old.at, end: old.at.addingTimeInterval(TimeInterval(duration * 60)), window: old.window,
                                reason: "trocado", isAnchor: false, isException: exception, legFromPrevious: nil)
        var left = proposal.leftOut.filter { $0.place.id != place.id }
        left.append(LeftOut(place: old.place, reason: "você trocou"))
        return finalize(stops: stops, request: proposal.request, leftOut: left)
    }

    /// Tira uma parada do roteiro ("Pular o almoço").
    static func skip(_ stopId: String, in proposal: DayProposal) -> DayProposal {
        var stops = proposal.stops
        guard let i = stops.firstIndex(where: { $0.id == stopId }), !stops[i].isAnchor else { return proposal }
        let old = stops.remove(at: i)
        var left = proposal.leftOut
        left.append(LeftOut(place: old.place, reason: "você pulou"))
        return finalize(stops: stops, request: proposal.request, leftOut: left)
    }
}
