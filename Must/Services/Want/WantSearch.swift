import CoreLocation
import CryptoKit
import Foundation

// Quero… (prompt 25 · A.2): a vontade vira busca **só de lugar físico** perto de hoje. Uma chamada ao Places por vontade
// (cache por consulta, dedupe em voo, `ApiBudget` no `GoogleAPI`), mais as lojas de marca do `brand-stores.json` e o que
// já está no board — essas duas entram mesmo offline.

/// Quem faz o Text Search com tipo (o `PlacesService` real; o fake dos prints).
protocol WantPlacesSearching: Sendable {
    var isConfigured: Bool { get }
    func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit]
}

extension PlacesService: WantPlacesSearching {}

/// Um lugar da lista do Quero….
struct WantResult: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable, Hashable { case places, brand, board }

    var id: String
    var name: String
    var lat: Double
    var lng: Double
    var origin: Origin
    var address: String? = nil
    /// Bairro em letras latinas ("Ginza"), da tabela de bairros ou da loja de marca.
    var area: String? = nil
    var types: [String] = []
    var primaryType: String? = nil
    var googlePlaceId: String? = nil
    var boardPlaceId: String? = nil
    /// Linha curta da loja de marca ("loja da marca · Grand Seiko e edições do Japão").
    var note: String? = nil
    /// "19h": fechamento mais comum (loja de marca) ou do horário em cache (board).
    var until: String? = nil
    var taxFree = false
    var photos: [PlacePhotoRef] = []
    /// Metros do centro da busca.
    var distance: Double = 0

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// O que o `WantSearch` precisa do aparelho (lido no main, antes de sair do main).
struct WantSearchInput: Sendable {
    var intent: WantIntent
    var region: Region
    /// Centro do círculo de 6 km: bairro de hoje, senão o GPS, senão o centro da cidade.
    var center: CLLocationCoordinate2D
    /// Grupo de cidade do dia (`tokyo`, `kyoto`, `bh`, `roma`): lojas de marca de outra cidade ficam fora.
    var cityGroup: String
    var online: Bool
    /// Lugares do board da cidade (já com coordenada): o que casa com a vontade entra na lista.
    var board: [WantBoardPlace] = []
    var now: Date = AppClock.now
    /// O corte (prompt 30): os Musts do board da cidade entram a qualquer distância (o raio só vale pro que vem de fora).
    var boardAnyDistance = false
}

/// Um lugar do board, sem SwiftData (pra rodar fora do main).
struct WantBoardPlace: Sendable, Hashable {
    var id: String
    var name: String
    var lat: Double
    var lng: Double
    var listId: String?
    var sub: String?
    var notes: String = ""
    var placeId: String?
    var area: String?
    var until: String?
    var done = false
}

struct WantSearchOutput: Sendable, Hashable {
    var results: [WantResult]
    /// Sem rede (ou o Places falhou por rede): a lista é só marca + board e a tela diz que a busca volta.
    var offline = false
    /// Cota do dia acabou, sem chave, erro do Google: frase curta pra tela.
    var notice: String? = nil
    /// Quantos o filtro tirou (sem coordenada, só online, fechado de vez).
    var dropped = 0
}

enum WantSearch {
    /// Raio do `locationBias` (prompt 25 · A.2): 6 km; "perto" fica em 2 km.
    static let radius: Double = 6_000
    static let nearRadius: Double = 2_000
    /// Dois resultados com o nome parecido a menos disso são o mesmo lugar.
    static let sameMeters: Double = 120

    // MARK: Pedido

    /// "relógio Seiko" (marca com a palavra da categoria), "tonkatsu", "pão de queijo", "Fuji".
    static func text(for intent: WantIntent, category: WantCategory?) -> String {
        if let brand = intent.brand, let word = category?.queryWord, !intent.object.localizedCaseInsensitiveContains(word) {
            return "\(word) \(brand)"
        }
        return intent.object
    }

    static func query(for input: WantSearchInput) -> PlacesTextQuery {
        let category = WantCategory.of(input.intent)
        return PlacesTextQuery(text: text(for: input.intent, category: category), lat: input.center.latitude, lng: input.center.longitude,
                               radius: input.intent.near ? nearRadius : radius, includedType: category?.includedType,
                               openNow: input.intent.when == .hoje, rankByDistance: true)
    }

    // MARK: Filtro (só lugar físico)

    /// Tipos que sozinhos não fazem um lugar físico (o resto do `types` diz o que é).
    static let genericTypes: Set<String> = ["point_of_interest", "establishment", "store", "premise", "subpremise"]

    /// Loja só online / site: tipos de "online" ou "website", ou só tipos genéricos e sem endereço.
    static func isOnlineOnly(_ hit: PlaceHit) -> Bool {
        if hit.types.contains(where: { $0.contains("online") || $0.contains("website") || $0 == "internet" }) { return true }
        let specific = hit.types.filter { !genericTypes.contains($0) }
        return specific.isEmpty && (hit.address ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Nunca devolve item sem coordenada, só online ou fechado de vez. Com categoria, fica o que tem um tipo dela
    /// (se nenhum tiver, ficam os físicos: melhor uma loja de departamento do que nada).
    static func filter(_ hits: [PlaceHit], category: WantCategory?) -> (kept: [PlaceHit], dropped: Int) {
        let physical = hits.filter { hit in
            guard let lat = hit.lat, let lng = hit.lng, lat != 0 || lng != 0 else { return false }
            if hit.businessStatus == "CLOSED_PERMANENTLY" { return false }
            return !isOnlineOnly(hit)
        }
        guard let types = category?.types, !types.isEmpty else { return (physical, hits.count - physical.count) }
        let allowed = Set(types)
        let typed = physical.filter { hit in hit.types.contains(where: allowed.contains) || hit.primaryType.map(allowed.contains) == true }
        let kept = typed.isEmpty ? physical : typed
        return (kept, hits.count - kept.count)
    }

    // MARK: Lojas de marca e board

    static func brandResults(_ input: WantSearchInput, category: WantCategory?, stores: [BrandStore] = BrandStores.all) -> [WantResult] {
        let brand = input.intent.brand.map(WantCategory.fold)
        return stores.filter { s in
            guard s.region == input.region.rawValue, AreaCatalog.cityGroup(forCityId: s.city) == input.cityGroup else { return false }
            if let brand { return s.brand.map(WantCategory.fold) == brand }
            // Sem marca: a loja de referência da categoria (Mercado Central pra cachaça).
            guard let label = category?.label else { return false }
            return s.brand == nil && s.categories.contains(label)
        }
        .map { s in
            WantResult(id: "brand:\(s.id)", name: s.name, lat: s.lat, lng: s.lng, origin: .brand, area: s.area, note: s.note,
                       until: s.until, taxFree: s.taxFree ?? false, distance: meters(input.center, s.lat, s.lng))
        }
    }

    /// O board que casa com a vontade: nome, sub-lista ou nota com a palavra (ex.: "pão de queijo" na nota), não feito.
    static func boardResults(_ input: WantSearchInput, category: WantCategory?) -> [WantResult] {
        let words = keywords(input.intent, category: category)
        guard !words.isEmpty else { return [] }
        return input.board.filter { p in
            guard !p.done, p.lat != 0 || p.lng != 0 else { return false }
            let hay = " " + WantCategory.fold("\(p.name) \(p.sub ?? "") \(p.notes)") + " "
            return words.contains { hay.contains(" \($0)") }
        }
        .map { p in
            WantResult(id: "board:\(p.id)", name: p.name, lat: p.lat, lng: p.lng, origin: .board, area: p.area, googlePlaceId: p.placeId,
                       boardPlaceId: p.id, note: "no seu board", until: p.until, distance: meters(input.center, p.lat, p.lng))
        }
        .filter { input.boardAnyDistance || $0.distance <= (input.intent.near ? nearRadius : radius) * 1.5 }
    }

    /// Palavras do objeto (sem as curtas) e da marca.
    static func keywords(_ intent: WantIntent, category: WantCategory?) -> [String] {
        let object = WantCategory.fold(intent.object)
        var words = [object]
        if let brand = intent.brand { words.append(WantCategory.fold(brand)) }
        return Array(Set(words.filter { $0.count >= 3 }))
    }

    // MARK: Juntar

    /// Board primeiro (já é seu), depois o Places e as lojas de marca por distância; o mesmo lugar aparece uma vez só.
    static func merge(board: [WantResult], places: [WantResult], brand: [WantResult]) -> [WantResult] {
        var out: [WantResult] = []
        for item in board + (places + brand).sorted(by: { ($0.distance, $0.id) < ($1.distance, $1.id) }) {
            if let i = out.firstIndex(where: { same($0, item) }) {
                // Fica o primeiro (board > places > marca), com o que faltar do outro.
                out[i].googlePlaceId = out[i].googlePlaceId ?? item.googlePlaceId
                out[i].note = out[i].note ?? item.note
                out[i].until = out[i].until ?? item.until
                out[i].taxFree = out[i].taxFree || item.taxFree
                if out[i].photos.isEmpty { out[i].photos = item.photos }
                if out[i].types.isEmpty { out[i].types = item.types }
                continue
            }
            out.append(item)
        }
        return out
    }

    static func same(_ a: WantResult, _ b: WantResult) -> Bool {
        if let x = a.googlePlaceId, x == b.googlePlaceId { return true }
        let d = CLLocation(latitude: a.lat, longitude: a.lng).distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
        guard d < sameMeters else { return false }
        if PlaceMatcher.similar(a.name, b.name) { return true }
        // "Mercado Central (queijo e cachaça)" no board × "Mercado Central de BH" da tabela: mesmas duas primeiras palavras.
        func head(_ s: String) -> [String] { Array(WantCategory.fold(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2).map(String.init)) }
        let x = head(a.name)
        return x.count == 2 && x == head(b.name)
    }

    static func result(_ hit: PlaceHit, input: WantSearchInput, areas: [Area]) -> WantResult? {
        guard let lat = hit.lat, let lng = hit.lng else { return nil }
        let assigner = AreaAssigner(areas: areas)
        let area = assigner.areaId(name: nil, cityId: input.cityGroup, lat: lat, lng: lng).flatMap { id in areas.first { $0.id == id }?.name }
        return WantResult(id: "g:\(hit.id)", name: hit.name, lat: lat, lng: lng, origin: .places, address: hit.address, area: area,
                          types: hit.types, primaryType: hit.primaryType, googlePlaceId: hit.id, photos: hit.photos,
                          distance: meters(input.center, lat, lng))
    }

    /// Falha de rede (sem internet, caiu, demorou, disjuntor aberto): a tela diz "a busca volta quando a rede voltar".
    static func isOffline(_ error: Error) -> Bool {
        if let e = error as? ServiceError {
            switch e {
            case .offline, .circuitOpen: return true
            default: return false
            }
        }
        let codes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                                         .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff]
        return (error as? URLError).map { codes.contains($0.code) } ?? false
    }

    static func meters(_ c: CLLocationCoordinate2D, _ lat: Double, _ lng: Double) -> Double {
        CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    // MARK: Rodar

    /// Marca + board sempre; Places só online e com chave (cache primeiro). Sem rede: `offline` e nada de espera.
    static func run(_ input: WantSearchInput, provider: (any WantPlacesSearching)?, cache: WantSearchCache = .shared) async -> WantSearchOutput {
        let category = WantCategory.of(input.intent)
        let brand = brandResults(input, category: category)
        let board = boardResults(input, category: category)
        let query = query(for: input)
        var hits: [PlaceHit] = []
        var offline = false
        var notice: String?
        if let cached = await cache.cached(query, now: input.now) {
            hits = cached
        } else if !input.online {
            offline = true
        } else if let provider, provider.isConfigured {
            do {
                hits = try await cache.fetch(query, now: input.now) { try await provider.searchPlaces(query) }
            } catch ServiceError.budget(let message) {
                notice = message
            } catch ServiceError.missingKey {
                notice = nil
            } catch {
                if isOffline(error) { offline = true } else { notice = "o Google não respondeu · mostrando o que já está no aparelho" }
            }
        }
        let (kept, dropped) = filter(hits, category: category)
        let areas = AreaCatalog.areas(for: input.region)
        let places = kept.compactMap { result($0, input: input, areas: areas) }
        return WantSearchOutput(results: merge(board: board, places: places, brand: brand), offline: offline, notice: notice, dropped: dropped)
    }
}

// MARK: - Cache por consulta

/// Uma resposta por consulta (texto, tipo, "aberto agora", célula de ~1 km): na memória e em Caches/ por 24 h
/// ("aberto agora": 30 min). Duas telas pedindo a mesma consulta ao mesmo tempo esperam a mesma chamada.
actor WantSearchCache {
    static let shared = WantSearchCache()

    private let directory: URL
    private var memory: [String: (at: Date, hits: [PlaceHit])] = [:]
    private var inFlight: [String: Task<[PlaceHit], Error>] = [:]

    init(directory: URL = URL.cachesDirectory.appending(path: "must-want", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    static func key(_ q: PlacesTextQuery) -> String {
        let cell = "\(Int((q.lat * 100).rounded())),\(Int((q.lng * 100).rounded()))"
        return [WantCategory.fold(q.text), q.includedType ?? "-", q.openNow ? "open" : "any", cell, "\(Int(q.radius))"].joined(separator: "|")
    }

    static func maxAge(_ q: PlacesTextQuery) -> TimeInterval { q.openNow ? 30 * 60 : 24 * 3600 }

    func cached(_ q: PlacesTextQuery, now: Date) -> [PlaceHit]? {
        let key = Self.key(q)
        if let hit = memory[key], now.timeIntervalSince(hit.at) < Self.maxAge(q) { return hit.hits }
        guard let data = try? Data(contentsOf: file(key)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              now.timeIntervalSince(stored.at) < Self.maxAge(q) else { return nil }
        memory[key] = (stored.at, stored.hits)
        return stored.hits
    }

    func fetch(_ q: PlacesTextQuery, now: Date, _ body: @escaping @Sendable () async throws -> [PlaceHit]) async throws -> [PlaceHit] {
        let key = Self.key(q)
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await body() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let hits = try await task.value
        memory[key] = (now, hits)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Stored(at: now, hits: hits)) { try? data.write(to: file(key), options: .atomic) }
        return hits
    }

    private struct Stored: Codable { var at: Date; var hits: [PlaceHit] }

    // MARK: Com nota (Enterprise, atrás do `PlacesEnterpriseFlag`)

    private var ratedMemory: [String: (at: Date, hits: [RatedHit])] = [:]
    private var ratedInFlight: [String: Task<[RatedHit], Error>] = [:]

    static func ratedKey(_ q: PlacesTextQuery) -> String { key(q) + "|rated" }

    func cachedRated(_ q: PlacesTextQuery, now: Date) -> [RatedHit]? {
        let key = Self.ratedKey(q)
        if let hit = ratedMemory[key], now.timeIntervalSince(hit.at) < Self.maxAge(q) { return hit.hits }
        guard let data = try? Data(contentsOf: file(key)),
              let stored = try? JSONDecoder().decode(StoredRated.self, from: data),
              now.timeIntervalSince(stored.at) < Self.maxAge(q) else { return nil }
        ratedMemory[key] = (stored.at, stored.hits)
        return stored.hits
    }

    func fetchRated(_ q: PlacesTextQuery, now: Date, _ body: @escaping @Sendable () async throws -> [RatedHit]) async throws -> [RatedHit] {
        let key = Self.ratedKey(q)
        if let running = ratedInFlight[key] { return try await running.value }
        let task = Task { try await body() }
        ratedInFlight[key] = task
        defer { ratedInFlight[key] = nil }
        let hits = try await task.value
        ratedMemory[key] = (now, hits)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(StoredRated(at: now, hits: hits)) { try? data.write(to: file(key), options: .atomic) }
        return hits
    }

    private struct StoredRated: Codable { var at: Date; var hits: [RatedHit] }

    private func file(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        return directory.appending(path: "\(digest).json")
    }
}

// MARK: - Lojas de marca

/// Uma loja de `data/brand-stores.json`.
struct BrandStore: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var brand: String?
    var region: String
    var city: String
    var lat: Double
    var lng: Double
    var approx: Bool?
    var area: String?
    var note: String?
    var until: String?
    var taxFree: Bool?
    var categories: [String]
}

enum BrandStores {
    private final class BundleAnchor {}
    private struct File: Decodable { var stores: [BrandStore] }

    /// Lido uma vez por processo (arquivo pequeno, nunca no `body`).
    static let all: [BrandStore] = load()

    static func load(bundle: Bundle? = nil) -> [BrandStore] {
        for candidate in [bundle ?? .main, Bundle(for: BundleAnchor.self)] {
            if let url = candidate.url(forResource: "brand-stores", withExtension: "json"),
               let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) {
                return file.stores
            }
        }
        Log.data.error("brand-stores.json ausente")
        return []
    }
}

// MARK: - Fake (prints e simulador)

#if DEBUG
/// `-debugPlaces fake`: respostas do Quero… sem cota. Inclui de propósito um site (sem coordenada) e uma loja só online,
/// que o filtro tem que tirar.
struct FakeWantPlaces: WantPlacesSearching {
    var isConfigured = true

    func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit] {
        let t = WantCategory.fold(query.text)
        let junk = [
            PlaceHit(id: "fake-site", name: "\(query.text) · loja oficial online", address: nil, lat: nil, lng: nil, types: ["store"]),
            PlaceHit(id: "fake-online", name: "\(query.text) Online Store", address: nil, lat: query.lat, lng: query.lng,
                     types: ["point_of_interest", "establishment"]),
        ]
        if t.contains("seiko") || t.contains("relogio") {
            return junk + [
                PlaceHit(id: "fake-bic-shinjuku", name: "Bic Camera Shinjuku Higashi-guchi", address: "3-29-1 Shinjuku, Tóquio",
                         lat: 35.69185, lng: 139.70280, types: ["electronics_store", "store", "point_of_interest"], primaryType: "electronics_store",
                         businessStatus: "OPERATIONAL"),
                PlaceHit(id: "fake-yodobashi-akiba", name: "Yodobashi Akiba", address: "1-1 Kanda Hanaokacho, Tóquio",
                         lat: 35.69890, lng: 139.77450, types: ["electronics_store", "department_store", "store"], primaryType: "electronics_store",
                         businessStatus: "OPERATIONAL"),
                PlaceHit(id: "fake-wako", name: "Wako Ginza", address: "4-5-11 Ginza, Tóquio", lat: 35.67180, lng: 139.76500,
                         types: ["department_store", "jewelry_store", "store"], primaryType: "department_store", businessStatus: "OPERATIONAL"),
            ]
        }
        if t.contains("pao de queijo") {
            return junk + [
                PlaceHit(id: "fake-pq-savassi", name: "Pão de Queijo da Savassi", address: "R. Pernambuco, Savassi, Belo Horizonte",
                         lat: -19.93800, lng: -43.93500, types: ["bakery", "cafe", "store"], primaryType: "bakery", businessStatus: "OPERATIONAL"),
                PlaceHit(id: "fake-pq-lourdes", name: "Casa do Pão de Queijo · Lourdes", address: "R. Curitiba, Lourdes, Belo Horizonte",
                         lat: -19.93300, lng: -43.94200, types: ["cafe", "coffee_shop"], primaryType: "cafe", businessStatus: "OPERATIONAL"),
                PlaceHit(id: "fake-pq-fechado", name: "Padaria que fechou", address: "Funcionários, Belo Horizonte", lat: -19.93500,
                         lng: -43.93000, types: ["bakery"], primaryType: "bakery", businessStatus: "CLOSED_PERMANENTLY"),
            ]
        }
        if t.contains("cachaca") {
            return junk + [
                PlaceHit(id: "fake-cachacaria", name: "Empório da Cachaça", address: "Av. Getúlio Vargas, Savassi, Belo Horizonte",
                         lat: -19.93650, lng: -43.93450, types: ["liquor_store", "store"], primaryType: "liquor_store", businessStatus: "OPERATIONAL"),
            ]
        }
        if t.contains("carbonara") {
            return junk + [
                PlaceHit(id: "fake-roscioli", name: "Roscioli Salumeria", address: "Via dei Giubbonari, Roma", lat: 41.89390, lng: 12.47270,
                         types: ["italian_restaurant", "restaurant"], primaryType: "italian_restaurant", businessStatus: "OPERATIONAL"),
                PlaceHit(id: "fake-dar-poeta", name: "Da Enzo al 29", address: "Via dei Vascellari, Trastevere, Roma", lat: 41.88850,
                         lng: 12.47750, types: ["restaurant"], primaryType: "restaurant", businessStatus: "OPERATIONAL"),
            ]
        }
        return junk
    }
}
#endif
