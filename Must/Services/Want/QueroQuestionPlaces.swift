import CoreLocation
import Foundation

// Quero (prompt 32 §6): a pergunta também termina num lugar no mapa. "que drink monto no 7-Eleven?" → 2–3 receitas do
// `guia-konbini.json` + o konbini aberto mais perto; "tem algo rolando hoje?" → os eventos de hoje com coordenada.
// Offline: só as receitas (e o aviso). Places só pelo caminho de sempre (cache por consulta, `ApiBudget` no `GoogleAPI`).

/// Uma combinação de `data/guia-konbini.json`.
struct KonbiniRecipe: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// "drink" ou "snack".
    var kind: String
    var title: String
    var ingredients: [String]
    var step: String
    var when: String
}

enum KonbiniGuide {
    private struct File: Decodable { var recipes: [KonbiniRecipe] }

    /// Lido uma vez por processo (arquivo pequeno, nunca no `body`).
    static let all: [KonbiniRecipe] = load()

    static func load(bundle: Bundle? = nil) -> [KonbiniRecipe] {
        for candidate in [bundle ?? .main, Bundle(for: Anchor.self)] {
            if let url = candidate.url(forResource: "guia-konbini", withExtension: "json"),
               let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) {
                return file.recipes
            }
        }
        Log.data.error("guia-konbini.json ausente")
        return []
    }

    private final class Anchor {}

    /// 2–3 receitas pro pedido: bebida quando fala de drink/beber, lanche quando fala de comer, senão as primeiras.
    static func pick(for question: String, from recipes: [KonbiniRecipe] = all, limit: Int = 3) -> [KonbiniRecipe] {
        let t = QueroQuestion.normalize(question)
        let wantsDrink = ["drink", "beber", "bebida", "highball", "chuhai", "cerveja"].contains { t.contains($0) }
        let wantsSnack = ["comer", "lanche", "comida", "almoco", "jantar", "cafe da manha", "sanduiche", "onigiri"].contains { t.contains($0) }
        let kind = wantsDrink ? "drink" : (wantsSnack ? "snack" : nil)
        let matching = recipes.filter { kind == nil || $0.kind == kind }
        return Array((matching.isEmpty ? recipes : matching).prefix(limit))
    }
}

/// O que a pergunta traz além da resposta curta: receitas, lugares (com coordenada) e um aviso.
struct QueroQuestionExtras: Equatable, Sendable {
    var answer: String?
    var recipes: [KonbiniRecipe] = []
    var places: [WantResult] = []
    var note: String?
    /// Título do botão "Ver no mapa" ("konbini aberto mais perto", "hoje").
    var mapTitle: String?
}

enum QueroQuestionPlaces {
    enum Kind: Equatable { case konbini(brand: String?), events }

    static func kind(of text: String) -> Kind? {
        let t = QueroQuestion.normalize(text)
        let brands: [(String, String)] = [("7 eleven", "7-Eleven"), ("7eleven", "7-Eleven"), ("seven eleven", "7-Eleven"),
                                          ("lawson", "Lawson"), ("family mart", "FamilyMart"), ("familymart", "FamilyMart")]
        if let hit = brands.first(where: { t.contains($0.0) }) { return .konbini(brand: hit.1) }
        if ["konbini", "conbini", "loja de conveniencia", "conveniencia"].contains(where: { t.contains($0) }) { return .konbini(brand: nil) }
        if ["rolando", "acontecendo", "evento", "eventos", "em cartaz", "show hoje", "shows hoje"].contains(where: { t.contains($0) }) { return .events }
        return nil
    }

    static func resolve(_ text: String, env: QueroEnv, provider: (any WantPlacesSearching)?,
                        cache: WantSearchCache = .shared) async -> QueroQuestionExtras? {
        switch kind(of: text) {
        case nil: return nil
        case .events?: return events(env)
        case .konbini(let brand)?: return await konbini(text, brand: brand, env: env, provider: provider, cache: cache)
        }
    }

    // MARK: Eventos de hoje

    static func events(_ env: QueroEnv) -> QueroQuestionExtras {
        let intent = WantIntent(verb: .ver, object: "evento", category: nil)
        let input = WantSearchInput(intent: intent, region: env.region, center: env.center, cityGroup: env.cityGroup, online: env.online,
                                    board: [], now: env.now, radiusMeters: 15_000, shows: env.shows)
        let found = WantSearch.showResults(input).sorted { ($0.distance, $0.id) < ($1.distance, $1.id) }.prefix(3)
        guard !found.isEmpty else {
            return QueroQuestionExtras(answer: "Não tenho nada em cartaz hoje perto de \(env.areaName) no aparelho.",
                                       note: env.online ? nil : "sem internet · só o que já estava no aparelho")
        }
        let n = found.count
        return QueroQuestionExtras(answer: n == 1 ? "Tem 1 coisa rolando hoje perto de \(env.areaName)." : "Tem \(n) coisas rolando hoje perto de \(env.areaName).",
                                   places: Array(found), mapTitle: "em cartaz hoje")
    }

    // MARK: Konbini

    static func konbini(_ text: String, brand: String?, env: QueroEnv, provider: (any WantPlacesSearching)?,
                        cache: WantSearchCache) async -> QueroQuestionExtras {
        let recipes = KonbiniGuide.pick(for: text)
        let name = brand ?? "konbini"
        var extras = QueroQuestionExtras(answer: recipes.isEmpty ? nil : "Dá pra montar sem cozinhar: \(recipes.map(\.title).joined(separator: ", ")).",
                                         recipes: recipes)
        let query = PlacesTextQuery(text: brand ?? "convenience store", lat: env.center.latitude, lng: env.center.longitude, radius: 2_000,
                                    includedType: "convenience_store", openNow: true, rankByDistance: true)
        var hits: [PlaceHit] = []
        if let cached = await cache.cached(query, now: env.now) {
            hits = cached
        } else if !env.online {
            extras.note = "sem internet · só as receitas; o \(name) aberto mais perto volta com a rede"
            return extras
        } else if let provider, provider.isConfigured {
            do {
                hits = try await cache.fetch(query, now: env.now) { try await provider.searchPlaces(query) }
            } catch ServiceError.budget(let message) {
                extras.note = message
                return extras
            } catch {
                extras.note = WantSearch.isOffline(error) ? "sem internet · só as receitas" : "o Google não respondeu · só as receitas"
                return extras
            }
        } else {
            extras.note = provider == nil ? "dados ao vivo desligados · só as receitas" : "sem chave do Google · só as receitas"
            return extras
        }
        let (kept, _) = WantSearch.filter(hits, category: nil)
        let input = WantSearchInput(intent: WantIntent(verb: .comprar, object: name, category: nil), region: env.region, center: env.center,
                                    cityGroup: env.cityGroup, online: env.online)
        let areas = AreaCatalog.areas(for: env.region)
        var results = kept.compactMap { WantSearch.result($0, input: input, areas: areas) }
        if let brand {
            let want = WantCategory.fold(brand).replacingOccurrences(of: "-", with: "")
            let same = results.filter { WantCategory.fold($0.name).replacingOccurrences(of: "-", with: "").contains(want) }
            if !same.isEmpty { results = same }
        }
        results.sort { ($0.distance, $0.id) < ($1.distance, $1.id) }
        if let nearest = results.first {
            extras.places = [nearest]
            extras.mapTitle = "\(name) aberto mais perto"
        } else {
            extras.note = "não achei \(name) aberto perto agora · só as receitas"
        }
        return extras
    }
}
