import CoreLocation
import Foundation
import SwiftData

/// Retrato imutável (Sendable) do que o assistente pode consultar: board, dia de hoje, gastos, tempo.
/// O modelo nunca recebe chave de API nem acessa rede — só isto.
struct AssistantSnapshot: Sendable {
    struct StopInfo: Sendable, Hashable, Identifiable {
        var id: String
        var place: SolverPlace
        var at: Date
        var done: Bool
        var isAnchor: Bool
        var isException: Bool
    }

    var region: Region
    var now: Date
    var here: CLLocationCoordinate2D?
    var areaName: String
    var cityId: String?
    var cityName: String?
    /// Outros trechos da mesma cidade (Tóquio 1 e 2).
    var sameCityIds: Set<String> = []
    var catalog: [SolverPlace]
    var listNames: [String: String]
    var stops: [StopInfo]
    var dayKind: DayKind?
    var budget: Double
    var spentDay: Double
    var spentException: Double
    var weatherToday: DayWeather?
    var weatherTomorrow: DayWeather?
    var lastTrain: LastTrain?
    var fxRate: Double
    var walkMaxKm: Double

    var nextStop: StopInfo? { stops.first { !$0.done } }
    var totalSpent: Double { spentDay + spentException }

    func listName(_ p: SolverPlace) -> String { listNames[p.listId] ?? "Must \(p.listId)" }

    @MainActor
    static func make(context: ModelContext, region: Region, services: Services) -> AssistantSnapshot {
        let now = AppClock.now
        let cal = region.calendar
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        let settings = context.settings(for: region)
        let start = cal.startOfDay(for: now)
        let day = try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start && $0.accepted })).first
        let range = region.dayRange(now)
        let expenses = ((try? context.fetch(FetchDescriptor<Expense>())) ?? []).filter { range.contains($0.at) }
        let exceptionIds = Set(day?.stops.filter(\.isException).compactMap { $0.place?.id } ?? [])
        let spentException = expenses.filter { $0.place.map { exceptionIds.contains($0.id) } ?? false }.reduce(0) { $0 + $1.amount }
        let here = services.location.current?.coordinate
        let city = trip?.city(on: now, calendar: cal)

        var area = city?.name ?? region.displayName
        if let here {
            let loc = CLLocation(latitude: here.latitude, longitude: here.longitude)
            if let nearest = places.filter({ $0.area != nil }).min(by: { $0.location.distance(from: loc) < $1.location.distance(from: loc) }),
               nearest.location.distance(from: loc) < 2500, let a = nearest.area { area = a }
        }
        let stops = (day?.orderedStops ?? []).compactMap { s -> StopInfo? in
            guard let p = s.place else { return nil }
            return StopInfo(id: s.id.uuidString, place: SolverPlace(p), at: s.at, done: s.done, isAnchor: s.isAnchor, isException: s.isException)
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        return AssistantSnapshot(
            region: region, now: now, here: here, areaName: area, cityId: city?.id, cityName: city?.name,
            sameCityIds: Set((trip?.cities ?? []).filter { $0.name == city?.name && $0.id != city?.id }.map(\.id)),
            catalog: places.solverCatalog, listNames: Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.displayName) }),
            stops: stops, dayKind: day?.kind, budget: day?.budget ?? settings.perDayBudget,
            spentDay: expenses.reduce(0) { $0 + $1.amount } - spentException, spentException: spentException,
            weatherToday: services.sync.weather(on: now, region: region, trip: trip),
            weatherTomorrow: services.sync.weather(on: tomorrow, region: region, trip: trip),
            lastTrain: LastTrains.home(region: region, near: stops.last?.place.location.coordinate ?? here, transit: TransitLoader.load(region)),
            fxRate: settings.fxRate, walkMaxKm: settings.walkMaxKm
        )
    }
}

/// Ação proposta pelo assistente (o app executa quando o usuário toca).
struct AssistantAction: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        /// Troca a parada `stopId` pelo lugar.
        case swap(stopId: String, replacing: String)
        /// Abre o caminho no Apple Maps.
        case go
        /// Registrar gasto e marcar 済.
        case markDone
    }

    var kind: Kind
    var place: SolverPlace
    var meta: String
    var highlighted: Bool

    var id: String {
        switch kind {
        case .swap(let stop, _): "swap-\(stop)-\(place.id)"
        case .go: "go-\(place.id)"
        case .markDone: "done-\(place.id)"
        }
    }

    var buttonTitle: String {
        switch kind {
        case .swap: "Trocar"
        case .go: "Ir"
        case .markDone: "Marcar 済"
        }
    }
}

/// Respostas determinísticas sobre o retrato (as ferramentas e o modo sem modelo usam as mesmas).
enum AssistantEngine {
    /// O que o assistente precisa saber dos tipos novos: "golden 15:56", "termina em 4 dias · ¥1.400",
    /// "bom agora · 23°" / "quente · 31°" (pra não sugerir corrida no sol do meio-dia).
    static func kindNote(_ p: SolverPlace, _ s: AssistantSnapshot) -> String? {
        let r = s.region
        switch p.kind {
        case .photo:
            let sun = SunService.day(s.now, CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng), timeZone: r.timeZone)
            guard let g = sun.goldenPM else { return nil }
            let light = p.extra?.photo?.bestLight.map(\.label).joined(separator: "/") ?? ""
            return (s.now <= g.end ? "golden hoje \(r.timeString(g.start))–\(r.timeString(g.end))" : "golden já passou hoje")
                + (light.isEmpty ? "" : " · melhor: \(light)")
        case .art:
            guard let art = p.extra?.art else { return nil }
            var parts: [String] = []
            if let left = art.daysLeft(from: s.now, calendar: r.calendar) { parts.append(left < 0 ? "temporada acabou" : DaySolver.endsText(left)) }
            if let price = art.priceAdult { parts.append(price == 0 ? "grátis" : r.money(price)) }
            if let next = art.sessions.filter({ $0.at > s.now && !$0.soldOut }).min(by: { $0.at < $1.at }) {
                parts.append("sessão \(r.shortDayTime(next.at)) \(next.title)\(next.bought ? " (ingresso comprado)" : "")")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .sport:
            guard let spot = p.extra?.sport, spot.activity != .watch, let h = s.weatherToday?.hour(at: s.now) else { return nil }
            if SportScore.isGood(h, spot: spot) {
                let until = SportScore.goodUntil(s.weatherToday?.hours ?? [], from: s.now, spot: spot)
                return "bom agora · \(Int(h.temp.rounded()))°" + (until.map { " até \(r.timeString($0))" } ?? "")
            }
            let why = DaySolver.sportRejection(spot, at: s.now, hourly: s.weatherToday?.hours ?? []) ?? "fora da janela boa"
            let next = SportScore.nextGood(s.weatherToday?.hours ?? [], after: s.now, spot: spot).map { " · melhor às \(r.timeString($0))" } ?? ""
            return "evitar agora (\(why))\(next)"
        case .place:
            return nil
        }
    }

    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }

    static func sameCity(_ p: SolverPlace, _ s: AssistantSnapshot) -> Bool {
        s.cityId == nil || p.cityId == s.cityId || s.sameCityIds.contains(p.cityId)
    }

    /// Abertos agora perto (ou, sem horário no cache, os mais perto marcados "sem horário").
    static func openNow(_ s: AssistantSnapshot, radiusKm: Double = 1.5, role: StopRole? = nil) -> (places: [SolverPlace], confirmed: Bool) {
        let origin = s.here ?? s.nextStop.map { CLLocationCoordinate2D(latitude: $0.place.lat, longitude: $0.place.lng) }
        guard let origin else { return ([], false) }
        let inDay = Set(s.stops.map(\.place.id))
        let nearby = s.catalog.filter { p in
            !p.done && !inDay.contains(p.id) && sameCity(p, s) && (role == nil || p.role == role)
                && distanceKm(origin, CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)) <= radiusKm
        }.sorted { distanceKm(origin, .init(latitude: $0.lat, longitude: $0.lng)) < distanceKm(origin, .init(latitude: $1.lat, longitude: $1.lng)) }
        let open = nearby.filter { $0.hours?.isOpen(at: s.now, timeZone: s.region.timeZone) == true }
        if !open.isEmpty { return (open, true) }
        return (nearby.filter { $0.hours == nil }, false)
    }

    private static let searchStopwords: Set<String> = [
        "um", "uma", "o", "a", "de", "do", "da", "em", "no", "na", "pra", "para", "por", "lugar", "lugares", "algum", "alguma",
        "barato", "barata", "caro", "bom", "boa", "perto", "comer", "beber", "tomar", "ir", "tem", "quero", "me", "sugere",
        "toquio", "tokyo", "kyoto", "japao", "bh", "belo", "horizonte",
    ]

    /// Busca por palavra (qualquer uma bate), ordenada por quantas bateram; "barato" ordena por preço.
    static func search(_ s: AssistantSnapshot, query: String, role: StopRole? = nil) -> [SolverPlace] {
        let fold = { (t: String) in t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        let q = fold(query)
        let tokens = q.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !searchStopwords.contains($0) }
        let cheap = q.contains("barat") || q.contains("economic")
        let scored = s.catalog.compactMap { p -> (SolverPlace, Int)? in
            guard role == nil || p.role == role else { return nil }
            let hay = fold([p.name, p.nameLocal ?? "", p.area ?? "", p.sub ?? "", s.listName(p), p.notes].joined(separator: " "))
            let hits = tokens.filter { hay.contains($0) }.count
            return tokens.isEmpty || hits > 0 ? (p, hits) : nil
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return cheap ? a.0.cost < b.0.cost : a.0.name < b.0.name
        }.map(\.0)
    }

    static func spentText(_ s: AssistantSnapshot) -> String {
        let r = s.region
        var text = "Hoje foram \(r.money(s.spentDay)) no dia"
        if s.spentException > 0 {
            let name = s.stops.first(where: \.isException)?.place.name ?? "a exceção"
            text += " e \(r.money(s.spentException)) de \(name) — \(r.money(s.totalSpent)) no total"
        }
        let left = s.budget - s.spentDay
        text += left >= 0 ? ". Sobram \(r.money(left)) da meta de \(r.money(s.budget))." : ". Passou \(r.money(-left)) da meta de \(r.money(s.budget))."
        if s.region == .jp, s.totalSpent > 0 { text += " (≈ \((s.totalSpent * s.fxRate).formatted(.money("BRL"))))" }
        return text
    }

    static func planText(_ s: AssistantSnapshot) -> String {
        guard !s.stops.isEmpty else { return "Ainda não tem dia montado hoje. Monta pelo Hoje → Montar o dia." }
        let r = s.region
        let lines = s.stops.map { stop in
            "\(r.timeString(stop.at)) \(stop.place.name)\(stop.done ? " 済" : "")\(stop.isAnchor ? " (reserva)" : "")"
        }
        let done = s.stops.filter(\.done).count
        return "Hoje: \(lines.joined(separator: ", ")). \(done) de \(s.stops.count) feitos."
    }

    static func lastTrainText(_ s: AssistantSnapshot) -> String {
        guard let t = s.lastTrain else { return "Não tenho o último trem pra essa região ainda — confere no Maps." }
        return "\(t.label): \(t.time)."
    }

    static func weatherText(_ s: AssistantSnapshot, tomorrow: Bool = false) -> String {
        guard let w = tomorrow ? s.weatherTomorrow : s.weatherToday else { return "Sem previsão no cache agora." }
        let when = tomorrow ? "Amanhã" : "Hoje"
        return "\(when): \(Int(w.tempMin.rounded()))–\(Int(w.tempMax.rounded()))° e \(w.label), \(w.precipProb)% de chance de chuva."
    }

    /// Qual parada o pedido quer trocar ("o bar", "o almoço", "o jantar", "o café"), senão a próxima.
    static func targetStop(_ s: AssistantSnapshot, text: String) -> AssistantSnapshot.StopInfo? {
        let t = text.lowercased()
        let pending = s.stops.filter { !$0.done && !$0.isAnchor }
        func first(_ match: (AssistantSnapshot.StopInfo) -> Bool) -> AssistantSnapshot.StopInfo? { pending.first(where: match) }
        if t.contains("bar") || t.contains("drink") { if let x = first({ $0.place.role == .drink && $0.place.sub != "Café" }) { return x } }
        if t.contains("café") || t.contains("cafe") { if let x = first({ $0.place.sub == "Café" }) { return x } }
        if t.contains("almoço") || t.contains("almoco") { if let x = first({ $0.place.role == .eat && DaySolver.window(at: minute($0.at, s)) == .lunch }) { return x } }
        if t.contains("jantar") { if let x = first({ $0.place.role == .eat && DaySolver.window(at: minute($0.at, s)) == .dinner }) { return x } }
        if t.contains("museu") || t.contains("templo") { if let x = first({ $0.place.role == .see }) { return x } }
        if t.contains("música") || t.contains("musica") || t.contains("show") { if let x = first({ $0.place.role == .listen }) { return x } }
        for stop in pending where t.contains(stop.place.name.lowercased()) { return stop }
        return pending.first
    }

    static func minute(_ date: Date, _ s: AssistantSnapshot) -> Int {
        Int(date.timeIntervalSince(s.region.calendar.startOfDay(for: date)) / 60)
    }

    /// Bar e listening bar se trocam entre si (café não entra à noite); o resto, mesmo papel.
    static func compatible(_ p: SolverPlace, with original: SolverPlace, night: Bool) -> Bool {
        let nightlife: Set<StopRole> = [.drink, .listen]
        if nightlife.contains(original.role), original.sub != "Café" || night {
            return nightlife.contains(p.role) && !(night && p.sub == "Café")
        }
        return p.role == original.role
    }

    /// Até `limit` lugares pra trocar uma parada: mesmo papel, mesma cidade, abertos no horário (ou sem horário),
    /// perto da referência (a próxima âncora — "perto do jantar" — ou a própria parada).
    static func swapCandidates(_ s: AssistantSnapshot, stop: AssistantSnapshot.StopInfo, cheaper: Bool = false,
                               nearAnchor: Bool = false, limit: Int = 2) -> [(place: SolverPlace, note: String)] {
        let inDay = Set(s.stops.map(\.place.id))
        let anchor = nearAnchor ? s.stops.first { $0.isAnchor } : nil
        let ref = (anchor ?? stop).place
        let refCoord = CLLocationCoordinate2D(latitude: ref.lat, longitude: ref.lng)
        let night = minute(stop.at, s) >= 18 * 60
        let options = s.catalog.filter { p in
            compatible(p, with: stop.place, night: night) && !inDay.contains(p.id) && !p.done && sameCity(p, s)
                && (p.hours?.isOpen(at: stop.at, timeZone: s.region.timeZone) ?? true)
                && (!cheaper || p.cost < stop.place.cost)
                && !(p.saveForEnd && (s.cityId == nil))
                && !p.rules.fullDay
        }
        return options
            .map { p -> (SolverPlace, Double) in (p, distanceKm(refCoord, CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { p, km in
                let walk = Walk.minutes(km * 1000 * 1.25)
                var bits = [p.area, p.sub?.lowercased()].compactMap { $0 }
                if let until = p.hours?.closesAt(stop.at, timeZone: s.region.timeZone) { bits.append("abre até \(until)") }
                bits.append(km < 2 ? "\(walk) min a pé do \(ref.name)" : "\(Walk.distanceText(km * 1000)) do \(ref.name)")
                if cheaper { bits.append(s.region.money(p.cost)) }
                return (p, bits.joined(separator: " · "))
            }
    }
}
