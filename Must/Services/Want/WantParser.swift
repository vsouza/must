import Foundation
import FoundationModels

// Quero… (prompt 25 · A.1): uma vontade em linguagem natural ("quero comprar um Seiko") vira um pedido de lugar físico.
// Não confundir com o `IntentParser` (pedido do dia → parâmetros do solver).

/// O que a pessoa quer fazer com a vontade. Manda nos tipos de lugar e na lista onde ela é guardada.
enum WantVerb: String, CaseIterable, Codable, Hashable, Sendable {
    case comprar, comer, ver, fazer, beber

    var label: String { rawValue }

    /// Lista do board onde "Só guardar" põe o lugar (ids dos seeds; `do` só existe em Roma).
    var listIds: [String] {
        switch self {
        case .comprar: ["shop"]
        case .comer: ["eat"]
        case .beber: ["drink", "eat"]
        case .ver: ["see", "photo", "art"]
        case .fazer: ["do", "see", "sport"]
        }
    }
}

/// Quando: muda o `openNow` (só hoje) e a frase "perto de hoje / pra amanhã".
enum WantWhen: String, CaseIterable, Codable, Hashable, Sendable {
    case hoje, amanha, qualquer
}

/// A vontade entendida: `{verb, object, brand?, category?, when?}`.
struct WantIntent: Hashable, Sendable, Codable {
    var verb: WantVerb
    /// O que buscar, sem artigo ("relógio Seiko", "tonkatsu", "Fuji").
    var object: String
    var brand: String?
    /// Categoria em pt da tabela `WantCategory` ("relógio", "cachaça", "pão de queijo").
    var category: String?
    var when: WantWhen?
    /// Disse "perto", "aqui", "por perto": raio menor.
    var near: Bool = false
    /// Disse "bom", "boa", "melhor": a lista mostra a nota primeiro (o Places já ordena por distância).
    var good: Bool = false
    /// O regex achou o verbo escrito (não o padrão "comprar"): o modelo não troca.
    var verbWasExplicit: Bool = false

    /// "relógio Seiko" · "tonkatsu" · "pão de queijo".
    var display: String {
        if let brand, let category, !object.localizedCaseInsensitiveContains(category) { return "\(category) \(brand)" }
        return object
    }
}

/// Saída estruturada do modelo no aparelho.
@Generable
struct GeneratedWant {
    @Guide(description: "O verbo da vontade", .anyOf(["comprar", "comer", "ver", "fazer", "beber"]))
    var verb: String
    @Guide(description: "O que a pessoa quer, sem artigo e sem 'perto/hoje/bom'. Ex.: relógio Seiko, tonkatsu, monte Fuji, pão de queijo")
    var object: String
    @Guide(description: "Marca, se a pessoa disse uma (Seiko, Uniqlo, Apple); senão vazio")
    var brand: String
    @Guide(description: "Categoria do produto ou da comida em português (relógio, roupa, cachaça, ramen, museu); senão vazio")
    var category: String
    @Guide(description: "Quando", .anyOf(["hoje", "amanha", "qualquer"]))
    var when: String
}

/// Texto/voz → `WantIntent`. Foundation Models quando disponível (sem rede); senão regex de verbos e o resto vira objeto.
enum WantParser {
    static let instructions = """
    Você entende vontades curtas em português de quem está viajando ("quero comprar um Seiko", "comer um tonkatsu bom perto").
    Devolva o verbo, o objeto sem artigo, a marca se houver, a categoria e quando. Não invente marcas nem lugares.
    """

    /// O modelo manda no objeto/categoria; o regex no verbo explícito, no "quando" e nas marcas conhecidas.
    static func parse(_ text: String, useModel: Bool) async -> WantIntent? {
        guard let local = parseLocal(text) else { return nil }
        guard useModel, OnDeviceAI.isAvailable else { return local }
        // O modelo tem 2,5 s (o primeiro uso pode carregar devagar): passou disso, vale o regex — a tela nunca espera.
        return await withTaskGroup(of: WantIntent?.self) { group in
            group.addTask { await model(text, local: local) }
            group.addTask {
                try? await Task.sleep(for: modelTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? local
        }
    }

    static let modelTimeout: Duration = .milliseconds(2500)

    private static func model(_ text: String, local: WantIntent) async -> WantIntent? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text, generating: GeneratedWant.self)
            return merge(response.content, local)
        } catch {
            Log.intelligence.error("quero: \(error.localizedDescription, privacy: .public) — usando regex")
            return local
        }
    }

    static func merge(_ g: GeneratedWant, _ local: WantIntent) -> WantIntent {
        var out = local
        if !local.verbWasExplicit, let verb = WantVerb(rawValue: g.verb) { out.verb = verb }
        let object = clean(g.object)
        if !object.isEmpty, local.brand == nil || object.localizedCaseInsensitiveContains(local.brand ?? "") { out.object = object }
        if out.brand == nil, !g.brand.isEmpty, text(g.brand, appearsIn: local.object) { out.brand = g.brand }
        if out.category == nil, !g.category.isEmpty { out.category = WantCategory.match(g.category)?.label ?? g.category.lowercased() }
        if local.when == nil, let when = WantWhen(rawValue: g.when), when != .qualquer { out.when = when }
        return out
    }

    private static func text(_ brand: String, appearsIn object: String) -> Bool {
        object.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .contains(brand.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    // MARK: Regex (sem modelo)

    /// Verbos e sinônimos, na ordem de tentativa (o primeiro que aparece no texto ganha).
    static let verbs: [(WantVerb, [String])] = [
        (.comprar, ["comprar", "compra", "comprando", "achar", "procurar", "procuro", "garimpar"]),
        (.comer, ["comer", "almoçar", "almocar", "jantar", "lanchar", "provar", "degustar"]),
        (.beber, ["beber", "tomar", "brindar"]),
        (.ver, ["ver", "visitar", "conhecer", "olhar", "fotografar", "subir"]),
        (.fazer, ["fazer", "ir", "andar", "passear", "experimentar"]),
    ]

    static let lead = ["eu quero", "quero", "queria", "eu queria", "preciso", "tô a fim de", "to a fim de", "a fim de",
                       "vontade de", "bora", "vamos", "quero muito"]
    static let articles: Set<String> = ["um", "uma", "uns", "umas", "o", "a", "os", "as", "de", "do", "da", "dos", "das", "no", "na",
                                        "algum", "alguma", "algo", "pra", "para"]
    static let trailingWords: Set<String> = ["bom", "boa", "bons", "boas", "melhor", "gostoso", "gostosa", "perto", "aqui", "hoje",
                                             "agora", "amanhã", "amanha", "depois", "já", "ja", "logo", "barato", "barata",
                                             "legal", "por", "daqui", "mais", "tarde", "cedo", "de", "noite", "manhã"]

    static func parseLocal(_ raw: String) -> WantIntent? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        var words = lower.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        // "eu quero", "quero", "tô a fim de" no começo.
        for phrase in lead.sorted(by: { $0.count > $1.count }) {
            let parts = phrase.split(separator: " ").map(String.init)
            if words.starts(with: parts) { words.removeFirst(parts.count); break }
        }
        var verb: WantVerb = .comprar
        var explicit = false
        if let first = words.first {
            for (v, forms) in verbs where forms.contains(where: { $0.split(separator: " ").first.map(String.init) == first }) {
                verb = v
                explicit = true
                words.removeFirst()
                break
            }
        }
        let folded = " " + lower.folding(options: .diacriticInsensitive, locale: nil) + " "
        let when: WantWhen? = folded.contains(" amanha ") ? .amanha
            : (folded.contains(" hoje ") || folded.contains(" agora ") || folded.contains(" ja ")) ? .hoje : nil
        let near = folded.contains(" perto ") || folded.contains(" aqui ")
        let good = folded.contains(" bom ") || folded.contains(" boa ") || folded.contains(" melhor ")
        // Objeto: sem artigos no começo e sem "bom/perto/hoje" no fim.
        while let first = words.first, articles.contains(first) { words.removeFirst() }
        while let last = words.last, trailingWords.contains(last) || articles.contains(last) { words.removeLast() }
        // "um tonkatsu bom perto de casa": tira o que vem depois de "perto".
        if let cut = words.firstIndex(where: { $0 == "perto" || $0 == "hoje" || $0 == "amanhã" || $0 == "amanha" }) {
            words = Array(words[..<cut])
            while let last = words.last, trailingWords.contains(last) || articles.contains(last) { words.removeLast() }
        }
        let objectLower = words.joined(separator: " ")
        guard !objectLower.isEmpty else { return nil }
        // Volta pra caixa original ("Seiko", "Fuji").
        let object = original(objectLower, in: text)
        let brand = WantBrand.find(in: object)
        let category = WantCategory.match(object)?.label ?? brand.flatMap { WantCategory.match($0.category)?.label }
        // "quero um pão de queijo": sem verbo escrito, vale o da categoria.
        if !explicit, let c = WantCategory.match(object) ?? brand.flatMap({ WantCategory.match($0.category) }) { verb = c.verb }
        return WantIntent(verb: verb, object: object, brand: brand?.name, category: category, when: when, near: near, good: good,
                          verbWasExplicit: explicit)
    }

    /// Tira artigos e "bom/perto" de um objeto vindo do modelo.
    static func clean(_ object: String) -> String {
        var words = object.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(separator: " ").map(String.init)
        while let first = words.first, articles.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, trailingWords.contains(last.lowercased()) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// O trecho de `text` que corresponde a `lower` (mantém maiúsculas do que a pessoa escreveu).
    static func original(_ lower: String, in text: String) -> String {
        guard let range = text.range(of: lower, options: [.caseInsensitive]) else { return lower }
        return String(text[range])
    }
}
