import CoreLocation
import Foundation
import Observation
import SwiftData

/// Dados vivos em segundo plano: tempo, horários das paradas de hoje, fotos das listas,
/// e a sincronização do Places (Ajustes). Nunca bloqueia a UI; erro vira o chip "sem dados ao vivo".
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case idle, syncing, ok(Date), offline, failed(String)

        var isProblem: Bool {
            switch self {
            case .offline, .failed: true
            default: false
            }
        }
    }

    private(set) var status: Status = .idle
    /// Previsão por coordenada de cidade ("lat,lng").
    private(set) var forecasts: [String: Forecast] = [:]
    /// Sincronização do Places: (feitos, total).
    private(set) var placesProgress: (done: Int, total: Int)?
    private(set) var placesSummary: String?

    @ObservationIgnored private let places: any PlacesProviding
    @ObservationIgnored private let weather: any WeatherProviding
    @ObservationIgnored private let photos: any PhotoProviding
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private var detailsInFlight: Set<String> = []
    /// Resolução sob demanda em voo (Lugar aberto): quem chega depois espera a mesma busca.
    @ObservationIgnored private var resolveTasks: [String: Task<Void, Never>] = [:]
    /// Lugares que o Places não achou nesta sessão: não repete a busca.
    @ObservationIgnored private var notFoundThisSession: Set<String> = []

    static let interval: TimeInterval = 6 * 3600
    /// Máximo de lugares resolvidos por sincronização (cada um = busca + detalhes).
    static let placesBatch = 50

    init(places: any PlacesProviding, weather: any WeatherProviding, photos: any PhotoProviding) {
        self.places = places
        self.weather = weather
        self.photos = photos
    }

    // MARK: Tempo

    private static func key(_ lat: Double, _ lng: Double) -> String { String(format: "%.2f,%.2f", lat, lng) }

    /// Previsão do dia na cidade daquele dia.
    func weather(on date: Date, region: Region, trip: TripInfo?) -> DayWeather? {
        let city = trip?.city(on: date, calendar: region.calendar)
        let lat = city?.lat ?? region.defaultCenter.latitude, lng = city?.lng ?? region.defaultCenter.longitude
        guard var day = forecasts[Self.key(lat, lng)]?.day(date, calendar: region.calendar) else { return nil }
        // Menu escondido: nuvens simuladas (frase do golden, solver de photo).
        if let cloud = DevOverrides.simulatedCloud {
            for i in day.hours.indices { day.hours[i].cloud = cloud }
        }
        return day
    }

    /// Quando a previsão da cidade do dia foi baixada ("atualizado 15:10").
    func weatherFetchedAt(on date: Date, region: Region, trip: TripInfo?) -> Date? {
        let city = trip?.city(on: date, calendar: region.calendar)
        let lat = city?.lat ?? region.defaultCenter.latitude, lng = city?.lng ?? region.defaultCenter.longitude
        return forecasts[Self.key(lat, lng)]?.fetchedAt
    }

    func now(region: Region, trip: TripInfo?) -> Forecast.Now? {
        let city = trip?.city(on: AppClock.now, calendar: region.calendar)
        let lat = city?.lat ?? region.defaultCenter.latitude, lng = city?.lng ?? region.defaultCenter.longitude
        return forecasts[Self.key(lat, lng)]?.now
    }

    /// Previsão de uma cidade pro pré-download do dia (prompt 18 · A.5): usa o cache do Weather (sem rede se ele
    /// tiver) e guarda pra Hoje. Não mexe no horário de sincronização.
    func prefetchForecast(at c: CLLocationCoordinate2D, region: Region) async throws {
        forecasts[Self.key(c.latitude, c.longitude)] = try await weather.forecast(at: c, region: region)
    }

    // MARK: Ciclo

    /// Na abertura e ao voltar pro app: sincroniza se passou de 6 h (ou nunca).
    func syncIfNeeded(context: ModelContext, region: Region) async {
        if let lastSync, Date().timeIntervalSince(lastSync) < Self.interval, !forecasts.isEmpty { return }
        await sync(context: context, region: region)
    }

    func sync(context: ModelContext, region: Region) async {
        // Trocar de região no meio (GPS, Ajustes) solta o container antigo: segura até terminar.
        let container = context.container
        defer { withExtendedLifetime(container) {} }
        guard status != .syncing else { return }
        // Sem dados ao vivo ou sem rede: usa o que está salvo, sem esperar o timeout (prompt 18 · A.4).
        guard DevOverrides.liveData, Connectivity.current != .offline else {
            status = .offline
            await loadCachedWeather(context: context, region: region)
            return
        }
        status = .syncing
        var problems: [String] = []

        // 1. Tempo de cada cidade da viagem (ou da casa).
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        var coords = (trip?.cities ?? []).map { ($0.lat, $0.lng) }
        if coords.isEmpty { coords = [(region.defaultCenter.latitude, region.defaultCenter.longitude)] }
        var seen: Set<String> = []
        for (lat, lng) in coords where seen.insert(Self.key(lat, lng)).inserted {
            do {
                forecasts[Self.key(lat, lng)] = try await weather.forecast(at: CLLocationCoordinate2D(latitude: lat, longitude: lng), region: region)
            } catch {
                problems.append("tempo: \(error.localizedDescription)")
            }
        }

        // 2. Horários das paradas de hoje (só os vencidos).
        let start = region.calendar.startOfDay(for: AppClock.now)
        if places.isConfigured, let today = try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start })).first {
            for place in today.stops.compactMap(\.place) where place.placeId != nil && (place.hours?.isStale ?? true) {
                do { try await refresh(place, region: region) } catch { problems.append("places: \(error.localizedDescription)") }
            }
        }

        // 3. Foto das listas que não têm.
        let settings = context.settings(for: region)
        if photos.isConfigured, settings.flickrPhotos {
            let cityName = trip?.city(on: AppClock.now, calendar: region.calendar)?.name ?? region.displayName
            for list in (try? context.fetch(FetchDescriptor<MustList>())) ?? [] where list.photo == nil {
                do {
                    // Tipos novos: termo que acha foto boa no Commons (rua, museu, parque), não a palavra "photo".
                    let term = switch list.kind {
                    case .photo: "street"
                    case .art: "art museum"
                    case .sport: "park running"
                    case .experience: "tour"
                    case .place: list.name
                    }
                    var photo = try await photos.search(text: "\(term) \(cityName)").first
                    if photo == nil { photo = try await photos.search(text: "\(list.name)").first }
                    if let photo { list.photo = photo.listPhoto }
                } catch {
                    problems.append("fotos: \(error.localizedDescription)")
                    break
                }
            }
        }
        try? context.save()

        lastSync = Date()
        status = problems.isEmpty ? .ok(Date()) : .failed(problems.joined(separator: " · "))
        if !problems.isEmpty { Log.network.error("sync: \(problems.joined(separator: " | "), privacy: .public)") }
    }

    /// Sem dados ao vivo: usa a última previsão salva.
    private func loadCachedWeather(context: ModelContext, region: Region) async {
        let container = context.container
        defer { withExtendedLifetime(container) {} }
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        for city in trip?.cities ?? [] {
            if let f = try? await weather.forecast(at: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng), region: region) {
                forecasts[Self.key(city.lat, city.lng)] = f
            }
        }
    }

    // MARK: Places

    /// Detalhes (horário + preço) ao abrir o Lugar, se o cache tiver mais de 7 dias.
    func refreshIfStale(_ place: Place, region: Region) {
        guard places.isConfigured, DevOverrides.liveData, place.placeId != nil, place.hours?.isStale ?? true,
              !detailsInFlight.contains(place.id) else { return }
        detailsInFlight.insert(place.id)
        let container = place.modelContext?.container
        Task {
            defer { detailsInFlight.remove(place.id); withExtendedLifetime(container) {} }
            do { try await refresh(place, region: region) } catch {
                Log.network.error("detalhes \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Board com lugar ainda não resolvido no Places (seed com coordenada chute): resolve no Wi-Fi, uma vez por sessão,
    /// pelo mesmo `syncPlaces` do Ajustes (lote de 50, cota do `ApiBudget`). Sem isso nenhuma miniatura, capa de lista
    /// ou foto da capa tem de onde vir — o Google só manda foto de lugar com `placeId` (05/11/2026: "as imagens
    /// deveriam carregar"). No celular e no Modo de Pouco Dados não roda; o Lugar aberto resolve só ele.
    @ObservationIgnored private var boardResolvedThisSession: Set<Region> = []

    func resolveBoardIfNeeded(context: ModelContext, region: Region, network: PrefetchPolicy.Network) async {
        guard PrefetchPolicy.allows(network), places.isConfigured, DevOverrides.liveData,
              !boardResolvedThisSession.contains(region) else { return }
        let unresolved = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).contains { $0.placeId == nil || $0.approx }
        guard unresolved else { boardResolvedThisSession.insert(region); return }
        boardResolvedThisSession.insert(region)
        Log.network.info("resolvendo o board no Places (Wi-Fi)")
        await syncPlaces(context: context, region: region)
    }

    /// Lugar aberto sem `placeId` (seed com coordenada chute, nunca sincronizado): resolve só ele, uma vez, antes da
    /// foto e das Dicas de quem foi — sem isso o Google não tem avaliação nem foto pra devolver. Uma Text Search e um
    /// Details; nada se o lugar já está resolvido, sem rede, sem chave ou com dados ao vivo desligados.
    func ensureResolved(_ place: Place, region: Region, cityName: String?) async {
        guard place.placeId == nil || place.approx else { return }
        guard places.isConfigured, DevOverrides.liveData, Connectivity.current != .offline,
              !notFoundThisSession.contains(place.id) else { return }
        if let running = resolveTasks[place.id] { await running.value; return }
        let container = place.modelContext?.container
        let task = Task { [places] in
            defer { withExtendedLifetime(container) {} }
            do {
                let target = place.kind == .art ? (place.nameLocal ?? place.name) : place.name
                let query = [target, place.area, cityName].compactMap { $0 }.joined(separator: " ")
                let results = try await places.searchText(query, near: place.coordinate, radius: 30_000, languageCode: "pt-BR")
                // Nome parecido primeiro; um resultado só também vale (a busca já é restrita à cidade).
                guard let best = Self.bestMatch(results, for: target, allowAny: results.count == 1) else {
                    notFoundThisSession.insert(place.id)
                    Log.network.info("resolver \(place.id, privacy: .public): não achei no Places")
                    return
                }
                place.placeId = best.id
                place.lat = best.lat
                place.lng = best.lng
                place.approx = false
                try await refresh(place, region: region)
                try? place.modelContext?.save()
            } catch {
                Log.network.error("resolver \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        resolveTasks[place.id] = task
        await task.value
        resolveTasks[place.id] = nil
    }

    private func refresh(_ place: Place, region: Region) async throws {
        guard let id = place.placeId else { return }
        apply(try await places.details(id, languageCode: "pt-BR"), to: place, region: region)
    }

    private func apply(_ details: PlaceDetails, to place: Place, region: Region) {
        if let hours = details.hours { place.hours = hours }
        if let level = details.priceLevel { place.priceLevel = level }
        // Fotos vêm no mesmo Details (prompt 19): o que chegou substitui o que estava guardado.
        place.photoRefs = details.photos
        // Preço do board vale mais; só preenche se faltar e a moeda bater.
        if place.price == nil, let from = details.priceFrom, details.priceCurrency == region.currency { place.price = from }
    }

    var isSyncingPlaces: Bool { placesProgress != nil }

    /// Ajustes → Sincronizar: resolve os lugares sem placeId ou com coordenada chutada (até 50).
    func syncPlaces(context: ModelContext, region: Region) async {
        let container = context.container
        defer { withExtendedLifetime(container) {} }
        guard placesProgress == nil else { return }
        guard places.isConfigured else { placesSummary = "Falta GOOGLE_PLACES_KEY no Secrets.plist."; return }
        guard DevOverrides.liveData else { placesSummary = "Dados ao vivo estão desligados."; return }
        var all = (try? context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.id)]))) ?? []
        #if DEBUG
        // `-debugSyncOnly j01,j05` (QA do prompt 19): sincroniza só esses lugares, pra gastar a cota com juízo.
        if let only = DebugFlags.string("debugSyncOnly") {
            let ids = Set(only.split(separator: ",").map(String.init))
            all = all.filter { ids.contains($0.id) }
        }
        #endif
        // Pedidos do Board (Resolver no Places) primeiro; depois o que falta resolver.
        let queued = all.filter(\.resolveQueued)
        let missing = all.filter { !$0.resolveQueued && ($0.placeId == nil || $0.approx || $0.hours == nil) }
        let pending = Array((queued + missing).prefix(Self.placesBatch))
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        placesProgress = (0, pending.count)
        var resolved = 0, notFound: [String] = [], failed = 0
        for (i, place) in pending.enumerated() {
            place.resolveQueued = false
            do {
                if place.placeId == nil || place.approx {
                    let city = trip?.city(id: place.cityId)
                    let center = CLLocationCoordinate2D(latitude: city?.lat ?? place.lat, longitude: city?.lng ?? place.lng)
                    let query = [place.name, place.area, city?.name].compactMap { $0 }.joined(separator: " ")
                    let results = try await places.searchText(query, near: center, radius: 30_000, languageCode: "pt-BR")
                    guard let best = Self.bestMatch(results, for: place.name) else {
                        notFound.append(place.name)
                        placesProgress = (i + 1, pending.count)
                        continue
                    }
                    place.placeId = best.id
                    place.lat = best.lat
                    place.lng = best.lng
                    place.approx = false
                }
                try await refresh(place, region: region)
                resolved += 1
            } catch {
                failed += 1
                Log.network.error("sync places \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            placesProgress = (i + 1, pending.count)
            if i % 5 == 4 { try? context.save() }
        }
        try? context.save()
        placesProgress = nil
        var parts = ["\(resolved) resolvidos"]
        if !notFound.isEmpty { parts.append("não achei: \(notFound.prefix(3).joined(separator: ", "))") }
        if failed > 0 { parts.append("\(failed) com erro") }
        if pending.isEmpty { parts = ["tudo já resolvido"] }
        placesSummary = parts.joined(separator: " · ")
    }

    /// Nome igual (sem acento/pontuação) > parecido > o primeiro (se `allowAny`).
    nonisolated static func bestMatch(_ results: [PlaceCandidate], for name: String, allowAny: Bool = true) -> PlaceCandidate? {
        let key = PlaceMatcher.normalize(name)
        return results.first { PlaceMatcher.normalize($0.name) == key }
            ?? results.first { PlaceMatcher.similar($0.name, name) }
            ?? (allowAny ? results.first : nil)
    }

    /// Busca de lugares pro Adicionar (Places Text Search restrito à cidade).
    func search(_ query: String, near: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        try await places.searchText(query, near: near, radius: 20_000, languageCode: "pt-BR")
    }

    /// Completa um lugar novo (placeId + coordenada exata + horário) em segundo plano.
    func resolveNew(_ place: Place, candidate: PlaceCandidate?, region: Region, context: ModelContext) {
        guard places.isConfigured, DevOverrides.liveData else { return }
        let container = context.container
        Task {
            defer { withExtendedLifetime(container) {} }
            do {
                var chosen = candidate
                if chosen == nil {
                    // Exposição/show: quem está no Places é o museu (guardado em `nameLocal`), não o título.
                    let target = place.kind == .art ? (place.nameLocal ?? place.name) : place.name
                    let results = try await places.searchText([target, place.area].compactMap { $0 }.joined(separator: " "),
                                                              near: place.coordinate, radius: 20_000, languageCode: "pt-BR")
                    chosen = Self.bestMatch(results, for: target, allowAny: false)
                }
                guard let chosen else { return }
                place.placeId = chosen.id
                place.lat = chosen.lat
                place.lng = chosen.lng
                place.approx = false
                try await refresh(place, region: region)
                try? context.save()
            } catch {
                Log.network.error("resolver \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

}
