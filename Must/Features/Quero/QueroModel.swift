import CoreLocation
import Foundation
import Observation
import SwiftData

/// O que o Quero… lê do aparelho antes de buscar (no main, rápido, sem rede).
struct QueroEnv: Sendable {
    var region: Region
    var now: Date
    /// Dia aceito de hoje (`nil` = nada montado: o encaixe sai daqui, agora).
    var plan: DayPlan?
    /// Centro da busca: bairro de hoje, senão o GPS, senão o centro da cidade.
    var center: CLLocationCoordinate2D
    /// De onde se sai agora (GPS, senão o centro): os minutos da lista e o encaixe sem dia.
    var origin: CLLocationCoordinate2D
    /// "Shinjuku", "Savassi": a ficha técnica do topo.
    var areaName: String
    var cityGroup: String
    var cityId: String
    var online: Bool
    var board: [WantBoardPlace]
    var useModel: Bool
    var walkMaxKm: Double = 1.5
    /// O corte (prompt 30): o board da cidade entra a qualquer distância.
    var boardAnyDistance = false
    /// Próximos dias aceitos e os bairros de cada um: "sáb · Ginza" quando hoje não cabe.
    var upcoming: [(date: Date, areaIds: Set<String>)] = []
    /// De onde a busca saiu (GPS, bairro, cidade de hoje, primeira cidade).
    var originBasis: WantOrigin.Basis = .gps
    /// Raio pedido ("ampliar pra 5 km"). `nil` = o de sempre (2 km perto, 6 km no Google).
    var radiusMeters: Double?
    /// Em cartaz hoje (pra "ouvir" e "noite"): lido do aparelho, sem rede.
    var shows: [ShowEvent] = []
    /// Presentes pendentes com loja (prompt 31), do mais perto de `origin`, a qualquer distância; nomes das pessoas da lista.
    var giftRows: [GiftNearby] = []
    var giftPeople: [String] = []
}

extension QueroEnv {
    /// O board da cidade (com coordenada), sem SwiftData: o Quero… e a busca do mapa (prompt 27 §2.c) leem o mesmo.
    @MainActor
    static func board(_ places: [Place], cityGroup: String, now: Date, timeZone: TimeZone) -> [WantBoardPlace] {
        places.compactMap { p -> WantBoardPlace? in
            guard AreaCatalog.cityGroup(forCityId: p.cityId) == cityGroup, p.lat != 0 || p.lng != 0 else { return nil }
            let until = p.hours?.closesAt(now, timeZone: timeZone).map(ListGrouping.hourLabel)
            return WantBoardPlace(id: p.id, name: p.name, lat: p.lat, lng: p.lng, listId: p.list?.id, sub: p.sub, notes: p.notes,
                                  placeId: p.placeId, area: p.area, until: until, done: p.isDone, photoRefs: p.photoRefs)
        }
    }
}

/// Uma linha da lista do Quero….
struct QueroRow: Identifiable, Hashable, Sendable {
    var result: WantResult
    /// Minutos daqui até lá (estimativa do solver, sem rede).
    var minutes: Int
    var slot: DayFit.Slot?
    var meta: String
    /// Segunda linha da direita quando não cabe hoje ("sáb · Ginza", "Ginza", "amanhã").
    var otherDay: String?
    var areaId: String?

    var id: String { result.id }
}

@MainActor
@Observable
final class QueroModel {
    enum Phase: Equatable { case idle, searching, done }

    var text: String
    /// Chip escolhido à mão (vale sobre o que o parser entendeu).
    var verbOverride: WantVerb?
    /// O corte pede "agora" quando a pessoa não disse quando (a faixa de fora é o que está aberto perto).
    @ObservationIgnored var defaultWhen: WantWhen?
    /// Quantas linhas guardar (a tela do Quero… mostra 8; o corte mostra o board inteiro).
    @ObservationIgnored var rowLimit = 8
    private(set) var intent: WantIntent?
    private(set) var rows: [QueroRow] = []
    private(set) var phase: Phase = .idle
    private(set) var offline = false
    private(set) var notice: String?
    /// Quantos o filtro tirou (site, loja só online, sem coordenada): o rodapé "fora: …" só aparece com algo.
    private(set) var dropped = 0
    /// "presente", "comprar presente" ou o nome de uma pessoa: os presentes pendentes com a loja mais perto (faixa laranja de cima).
    private(set) var giftRows: [GiftNearby] = []
    /// Por que a busca de fora ficou só no board ("sem internet", "sem chave do Google"…).
    private(set) var outsideNote: String?
    var selectedId: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    @ObservationIgnored let provider: (any WantPlacesSearching)?
    /// Fontes além do Google (Wikipedia pro "ver"). Os prints com Places falso e os testes não saem pra rede.
    @ObservationIgnored let extras: WantExtras?

    init(text: String = "", provider: (any WantPlacesSearching)?, extras: WantExtras? = nil) {
        self.text = text
        self.provider = provider
        self.extras = extras
    }

    var verb: WantVerb? { verbOverride ?? intent?.verb }
    var selected: QueroRow? { rows.first { $0.id == selectedId } ?? rows.first }
    var category: WantCategory? { intent.flatMap(WantCategory.of) }

    /// Busca a vontade. Uma de cada vez: a nova cancela a anterior (nunca duas chamadas pro mesmo texto).
    func submit(_ env: QueroEnv) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        searchTask?.cancel()
        giftRows = GiftLogic.isGiftWant(typed, people: env.giftPeople) ? env.giftRows : []
        phase = .searching
        searchTask = Task { [weak self] in
            guard let self else { return }
            guard var intent = await WantParser.parse(typed, useModel: env.useModel) else {
                self.phase = self.giftRows.isEmpty ? .idle : .done
                return
            }
            if let forced = self.verbOverride, forced != intent.verb {
                intent.verb = forced
                // Categoria genérica do verbo antigo não vale pro novo ("comer" → "ver").
                if let c = intent.category, WantVerb(rawValue: c) != nil { intent.category = forced.rawValue }
            }
            guard !Task.isCancelled else { return }
            if intent.when == nil, let when = self.defaultWhen { intent.when = when }
            self.intent = intent
            let output = await WantSearch.run(Self.input(intent, env), provider: self.provider, extras: self.extras)
            guard !Task.isCancelled else { return }
            self.apply(output, intent: intent, env: env)
        }
    }

    func choose(_ verb: WantVerb, env: QueroEnv) {
        verbOverride = verb
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { submit(env) }
    }

    static func input(_ intent: WantIntent, _ env: QueroEnv) -> WantSearchInput {
        WantSearchInput(intent: intent, region: env.region, center: env.center, cityGroup: env.cityGroup, online: env.online,
                        board: env.board, now: env.now, boardAnyDistance: env.boardAnyDistance, radiusMeters: env.radiusMeters,
                        shows: env.shows)
    }

    private func apply(_ output: WantSearchOutput, intent: WantIntent, env: QueroEnv) {
        rows = Self.rows(output.results, intent: intent, env: env, limit: rowLimit)
        offline = output.offline
        notice = output.notice
        dropped = output.dropped
        outsideNote = output.outsideNote
        selectedId = rows.first?.id
        phase = .done
    }

    // MARK: Linhas (puro, testado)

    /// Cabe hoje primeiro (pelo tempo até lá), depois o resto (pelo tempo). No máximo `limit` (8).
    static func rows(_ results: [WantResult], intent: WantIntent, env: QueroEnv, limit: Int = 8) -> [QueroRow] {
        let areas = AreaCatalog.areas(for: env.region)
        let assigner = AreaAssigner(areas: areas)
        let rows = results.map { r -> QueroRow in
            let minutes = DaySolver.leg(env.origin, r.coordinate, walkMax: env.walkMaxKm).minutes
            let closes = r.until.flatMap { closing($0, on: env.now, region: env.region) }
            let slot = intent.when == .amanha ? nil
                : DayFit.slot(at: r.coordinate, plan: env.plan, now: env.now, region: env.region, origin: env.origin,
                              walkMaxKm: env.walkMaxKm, closesAt: closes)
            let areaId = assigner.areaId(name: r.area, cityId: env.cityId, lat: r.lat, lng: r.lng)
            return QueroRow(result: r, minutes: max(1, minutes), slot: slot, meta: meta(r, intent: intent),
                            otherDay: otherDay(r, areaId: areaId, intent: intent, env: env), areaId: areaId)
        }
        let fits = rows.filter { $0.slot != nil }.sorted { ($0.minutes, $0.id) < ($1.minutes, $1.id) }
        let rest = rows.filter { $0.slot == nil }.sorted { ($0.minutes, $0.id) < ($1.minutes, $1.id) }
        return Array((fits + rest).prefix(limit))
    }

    /// "relógios · tax-free · até 22h · 300 m" / "loja da marca · Grand Seiko… · até 19h".
    static func meta(_ r: WantResult, intent: WantIntent) -> String {
        var parts: [String] = []
        if let note = r.note { parts.append(note) } else if let label = typeLabel(r) { parts.append(label) }
        if r.taxFree, r.note?.contains("tax-free") != true { parts.append("tax-free") }
        if let until = r.until { parts.append("até \(until)") }
        parts.append(Walk.distanceText(r.distance))
        return parts.joined(separator: " · ")
    }

    /// Tipos de loja que o `NearbyRanker` chama só de "loja".
    static let storeLabels: [String: String] = [
        "electronics_store": "eletrônicos", "department_store": "loja de departamento", "jewelry_store": "joalheria",
        "watch_store": "relojoaria", "clothing_store": "roupas", "shoe_store": "calçados", "liquor_store": "bebidas",
        "toy_store": "brinquedos", "sporting_goods_store": "esportes", "cell_phone_store": "celulares", "grocery_store": "mercado",
        "supermarket": "supermercado", "convenience_store": "conveniência", "gift_shop": "presentes", "ice_cream_shop": "sorveteria",
        "dessert_shop": "doceria", "confectionery": "doceria", "snack_bar": "lanchonete", "observation_deck": "mirante",
    ]

    static func typeLabel(_ r: WantResult) -> String? {
        let types = ([r.primaryType].compactMap { $0 } + r.types)
        if let hit = types.lazy.compactMap({ storeLabels[$0] }).first { return hit }
        return types.lazy.compactMap { NearbyRanker.categoryLabel(NearbyPlace(name: "", lat: 0, lng: 0, sources: [.google], category: $0)) }.first
    }

    /// Quando não cabe hoje: o próximo dia aceito no mesmo bairro ("sáb · Ginza"), senão o bairro, senão nada.
    static func otherDay(_ r: WantResult, areaId: String?, intent: WantIntent, env: QueroEnv) -> String? {
        let area = r.area ?? areaId.flatMap { id in AreaCatalog.areas(for: env.region).first { $0.id == id }?.name }
        if let areaId, let day = env.upcoming.first(where: { $0.areaIds.contains(areaId) }) {
            return [weekday(day.date, region: env.region), area].compactMap { $0 }.joined(separator: " · ")
        }
        if intent.when == .amanha { return ["amanhã", area].compactMap { $0 }.joined(separator: " · ") }
        return area
    }

    static func weekday(_ date: Date, region: Region) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = region.timeZone
        return date.formatted(style.locale(region.locale)).replacingOccurrences(of: ".", with: "").lowercased()
    }

    /// "19h" / "19h30" / "22:00" → hoje, no fuso da região. Madrugada ("02h") = dia seguinte.
    static func closing(_ label: String, on now: Date, region: Region) -> Date? {
        let digits = label.replacingOccurrences(of: "h", with: ":").split(separator: ":").compactMap { Int($0) }
        guard let hour = digits.first, (0...23).contains(hour) else { return nil }
        let minute = digits.count > 1 ? digits[1] : 0
        let cal = region.calendar
        let day = cal.startOfDay(for: now)
        guard let at = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        return hour < 5 ? cal.date(byAdding: .day, value: 1, to: at) : at
    }

    // MARK: Textos

    /// "relógio Seiko" + "loja física perto de hoje".
    var understood: (object: String, rest: String)? {
        guard let intent else { return nil }
        let kind = category?.kind ?? "lugar físico"
        let when = switch intent.when {
        case .amanha: "pra amanhã"
        case .hoje: "aberto agora"
        default: "perto de hoje"
        }
        return (intent.display, "\(kind) \(when)")
    }

    /// Rodapé: o que ficou de fora por construção.
    func footer(region: Region) -> String {
        let site = intent?.brand.map { "\(WantCategory.fold($0).replacingOccurrences(of: " ", with: "")).\(region.profile.day?.storeTLD ?? "com")" }
        let online = [site, "lojas online"].compactMap { $0 }.joined(separator: " e ")
        let home = region.profile.day?.deliveryNote ?? "entrega no Airbnb não é opção"
        return verb == .comprar || verb == nil ? "fora: \(online) · \(home)" : "fora: sites, delivery e lugares fechados de vez"
    }
}

// MARK: - Gravar (Encaixar hoje / Só guardar)

@MainActor
enum QueroSave {
    /// Lista certa pra vontade: a da categoria, senão a do verbo, senão Shop, senão a primeira.
    static func list(for intent: WantIntent?, lists: [MustList]) -> MustList? {
        let category = intent.flatMap(WantCategory.of)
        let ids = [category?.listId].compactMap { $0 } + (intent?.verb.listIds ?? []) + ["shop"]
        for id in ids { if let list = lists.first(where: { $0.id == id }) { return list } }
        return lists.first
    }

    /// O lugar do board pra linha: o que já existe (mesmo placeId ou o próprio do board) ou um novo na lista da vontade,
    /// com a fonte "quero" e o texto original. Resolve horário/fotos depois (Details, uma chamada, pelo `SyncCoordinator`).
    static func place(for row: QueroRow, intent: WantIntent?, text: String, lists: [MustList], cityId: String, region: Region,
                      sync: SyncCoordinator?, context: ModelContext) -> Place? {
        let all = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let r = row.result
        if let id = r.boardPlaceId, let existing = all.first(where: { $0.id == id }) { return existing }
        if let gid = r.googlePlaceId, let existing = all.first(where: { $0.placeId == gid }) { return existing }
        guard let list = list(for: intent, lists: lists) else { return nil }
        let place = Place(id: "q-\(UUID().uuidString.prefix(8).lowercased())", name: r.name, cityId: cityId, lat: r.lat, lng: r.lng)
        place.list = list
        place.order = (list.places.map(\.order).max() ?? 0) + 1
        place.placeId = r.googlePlaceId
        place.area = r.area
        place.approx = r.origin == .brand && (BrandStores.all.first { "brand:\($0.id)" == r.id }?.approx ?? false)
        place.notes = r.note ?? ""
        if !r.photos.isEmpty { place.photoRefs = r.photos }
        place.source = source(text: text, region: region)
        context.insert(place)
        try? context.save()
        if let gid = r.googlePlaceId {
            sync?.resolveNew(place, candidate: PlaceCandidate(id: gid, name: r.name, address: r.address, lat: r.lat, lng: r.lng,
                                                               primaryType: r.primaryType), region: region, context: context)
        }
        return place
    }

    /// Fonte do lugar salvo pelo Quero…: o texto original na legenda, "Quero…" como autor.
    /// TODO(p25:1): `SourceKind.quero` (prompt 25 · A.4 pede `source.kind = "quero"`) mexe no modelo e no `board.schema.json`;
    /// até lá, `.manual` + `author == "Quero…"` identifica a origem.
    static func source(text: String, region: Region) -> Source {
        Source(kind: .manual, url: nil, savedAt: BoardDates(timeZone: region.timeZone).dayString(AppClock.now),
               caption: text.trimmingCharacters(in: .whitespacesAndNewlines), author: marker)
    }

    static let marker = "Quero…"

    /// Encaixar hoje: a parada de 25 min no buraco do `DayFit`, gravada como dia aceito (as outras não se movem),
    /// e os avisos do guia reagendados (o "saia às" da parada nova).
    static func encaixar(_ row: QueroRow, place: Place, env: QueroEnv, context: ModelContext) throws -> DayPlan? {
        guard let slot = row.slot else { return nil }
        let stop = DayFit.stop(placeId: place.id, name: place.name, note: "quero · 25 min · \(row.meta)", slot: slot, area: row.areaId,
                               at: row.result.coordinate)
        let plan = DayFit.inserting(stop, into: env.plan, date: env.now, region: env.region, walkMaxKm: env.walkMaxKm)
        try DayEngineV8.save(plan, region: env.region, context: context)
        if !DebugFlags.isTestHost {
            let origin = env.origin
            Task { await GuideNudgeScheduler.refresh(context: context, region: env.region, origin: origin, askPermission: false) }
        }
        return plan
    }
}

// MARK: - Ambiente (o Quero… e o corte da capa leem do mesmo jeito)

extension QueroEnv {
    /// Monta o ambiente da busca com o que já está no aparelho (sem rede): bairro de hoje, origem (GPS na cidade, senão o
    /// bairro do dia ou o centro), board da cidade e os próximos dias aceitos.
    @MainActor
    static func make(region: Region, now: Date, places: [Place], trip: TripInfo?, settings: Settings?, plan: DayPlan?,
                     gps: CLLocationCoordinate2D?, online: Bool, upcoming: [(date: Date, areaIds: Set<String>)],
                     areaHint: Area? = nil, shows: [ShowEvent] = [], gifts: [Gift] = []) -> QueroEnv {
        let areas = AreaCatalog.areas(for: region)
        let city = trip?.city(on: now, calendar: region.calendar)
        // Viagem futura: `city(on:)` já devolve a primeira cidade; sem coordenada ainda, o centro da região.
        let cityCenter = city.flatMap { $0.hasCoordinate ? CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) : nil }
            ?? trip?.cities.first(where: \.hasCoordinate).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            ?? region.defaultCenter
        let planArea = plan?.area.flatMap { id in areas.first { $0.id == id } }
        let resolved = WantOrigin.resolve(gps: gps, cityCenter: cityCenter, hasCurrentCity: Self.tripStarted(trip, now: now, calendar: region.calendar),
                                          areaHint: areaHint, planArea: planArea)
        let origin = resolved.origin
        let center = resolved.basis == .gps ? (planArea?.centroid.clCoordinate ?? origin) : origin
        let cityId = city?.id ?? trip?.cities.first?.id ?? region.rawValue
        let group = AreaCatalog.cityGroup(forCityId: cityId)
        var gpsArea: Area?
        if resolved.basis == .gps, let gps {
            let id = AreaAssigner(areas: areas).areaId(name: nil, cityId: cityId, lat: gps.latitude, lng: gps.longitude)
            gpsArea = id.flatMap { id in areas.first { $0.id == id } }
        }
        let name = (resolved.basis == .gps ? planArea?.name ?? gpsArea?.name : resolved.area?.name) ?? city?.name ?? region.displayName
        let board = QueroEnv.board(places, cityGroup: group, now: now, timeZone: region.timeZone)
        var env = QueroEnv(region: region, now: now, plan: plan, center: center, origin: origin, areaName: name, cityGroup: group,
                           cityId: cityId, online: online, board: board, useModel: settings?.onDeviceAI ?? true,
                           walkMaxKm: settings?.walkMaxKm ?? 1.5, upcoming: upcoming)
        env.shows = shows
        env.giftPeople = GiftLogic.people(gifts)
        env.giftRows = GiftLogic.nearby(gifts: gifts, places: places, here: origin, now: now, timeZone: region.timeZone, maxMinutes: .max)
        env.originBasis = resolved.basis
        return env
    }

    /// A viagem já começou (e não acabou): a cidade de hoje existe de verdade. Antes disso, vale a primeira cidade.
    @MainActor
    static func tripStarted(_ trip: TripInfo?, now: Date, calendar: Calendar) -> Bool {
        guard let start = trip?.start, let end = trip?.end else { return false }
        return calendar.startOfDay(for: start) <= now && now < (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end)
    }

    /// Próximos 14 dias aceitos e os bairros das paradas (pro "sáb · Ginza").
    @MainActor
    static func upcomingDays(context: ModelContext, areas: [Area], today: Date) -> [(date: Date, areaIds: Set<String>)] {
        let start = today.addingTimeInterval(86_400)
        let end = today.addingTimeInterval(15 * 86_400)
        let days = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date >= start && $0.date < end && $0.accepted },
                                                                     sortBy: [SortDescriptor(\.date)]))) ?? []
        let assigner = AreaAssigner(areas: areas)
        return days.map { day in
            let ids = day.stops.compactMap { stop -> String? in
                guard let p = stop.place else { return nil }
                return assigner.areaId(name: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng)
            }
            return (day.date, Set(ids))
        }
    }
}
