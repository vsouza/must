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

/// "o melhor" / "barato" / nada dito (prompt 27 §2.c): manda no ranking da busca do mapa.
enum WantQuality: String, CaseIterable, Codable, Hashable, Sendable {
    case melhor, barato, qualquer
}

/// A vontade entendida: `{verb, object, brand?, category?, when?, qualidade, raio}`.
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
    /// "o melhor", "mais bem avaliado" → `.melhor`; "barato", "em conta" → `.barato` (prompt 27 §2.c).
    var quality: WantQuality = .qualquer
    /// Raio pedido em km ("até 2 km", "a 500 m"). `nil` = o padrão de quem busca (mapa: 1,5 km a pé).
    var radiusKm: Double? = nil

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
        var verbWord: String?
        if let first = words.first {
            for (v, forms) in verbs where forms.contains(where: { $0.split(separator: " ").first.map(String.init) == first }) {
                verb = v
                // "procurar um lámen", "achar um Seiko": buscar não diz o quê (vale o verbo da categoria).
                explicit = !searchVerbs.contains(first)
                verbWord = first
                words.removeFirst()
                break
            }
        }
        // Só o verbo ("comer", "ver", "fazer", "fotografar"): a vontade é o próprio verbo, não nada (era o "comer em Nakano não achou").
        if words.isEmpty, let verbWord, !searchVerbs.contains(verbWord), WantCategory.match(verbWord) != nil { words = [verbWord] }
        let raw = " " + lower.folding(options: .diacriticInsensitive, locale: nil) + " "
        // Pontuação vira espaço ("agora, o melhor"); o raio lê o texto cru ("1,5 km").
        let folded = String(raw.map { ",.;!?".contains($0) ? " " : $0 })
        let when: WantWhen? = folded.contains(" amanha ") ? .amanha
            : (folded.contains(" hoje ") || folded.contains(" agora ") || folded.contains(" ja ")) ? .hoje : nil
        let near = folded.contains(" perto ") || folded.contains(" aqui ")
        let good = folded.contains(" bom ") || folded.contains(" boa ") || folded.contains(" melhor ")
        let quality = quality(folded)
        let radius = radiusKm(raw)
        // Raio dito ("até 2 km", "a 500 m") sai do objeto antes de tudo.
        words = removingRadius(words)
        // Objeto: sem artigos nem "o melhor/mais barato" no começo e sem "bom/perto/hoje" no fim.
        while let first = words.first, articles.contains(first) || leadingQualifiers.contains(first) { words.removeFirst() }
        // "noite" sozinha é uma vontade; "jantar de noite" perde o "noite".
        while words.count > 1 || WantCategory.match(words.first ?? "") == nil,
              let last = words.last, trailingWords.contains(last) || articles.contains(last) { words.removeLast() }
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
                          verbWasExplicit: explicit, quality: quality, radiusKm: radius)
    }

    /// Verbos de busca: tiram a palavra, mas o verbo da vontade vem da categoria ("procurar um lámen" = comer).
    static let searchVerbs: Set<String> = ["procurar", "procuro", "achar"]
    /// Qualificadores que podem vir antes do objeto ("o melhor lámen", "um bom café", "o mais barato").
    static let leadingQualifiers: Set<String> = ["melhor", "melhores", "mais", "bem", "avaliado", "avaliada", "bom", "boa", "barato",
                                                 "barata", "baratinho", "top"]

    /// "o melhor", "mais bem avaliado", "top" → melhor; "barato", "em conta" → barato. `folded` vem com espaços nas
    /// pontas e sem acento.
    static func quality(_ folded: String) -> WantQuality {
        let barato = [" barato ", " barata ", " baratinho ", " baratinha ", " em conta ", " economico ", " economica "]
        if barato.contains(where: folded.contains) { return .barato }
        let melhor = [" melhor ", " melhores ", " bem avaliado ", " bem avaliada ", " mais avaliado ", " top "]
        if melhor.contains(where: folded.contains) { return .melhor }
        return .qualquer
    }

    /// "até 2 km", "a 500 m", "num raio de 1,5 km", "800m" → km (0,2…10). `nil` = não disse.
    static func radiusKm(_ folded: String) -> Double? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s?(km|quilometros?|metros?|m)(?=[\s,.;!?]|$)"#
        guard let range = folded.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(folded[range])
        let digits = String(match.prefix { $0.isNumber || $0 == "," || $0 == "." })
        guard let value = Double(digits.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        let unit = match.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        let km = unit.hasPrefix("k") || unit.hasPrefix("q") ? value : value / 1000
        return min(10, max(0.2, km))
    }

    /// Tira "até 2 km", "a 500 m", "num raio de 1 km" das palavras (o número, a unidade e a preposição antes).
    static func removingRadius(_ words: [String]) -> [String] {
        let units: Set<String> = ["km", "m", "metro", "metros", "quilometro", "quilometros", "quilômetro", "quilômetros"]
        let lead: Set<String> = ["até", "ate", "a", "num", "raio", "de", "no", "máximo", "maximo"]
        var out: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            let isNumber = Double(w.replacingOccurrences(of: ",", with: ".")) != nil
            let joined = w.range(of: #"^\d+(?:[.,]\d+)?(km|m)$"#, options: .regularExpression) != nil
            if joined || (isNumber && i + 1 < words.count && units.contains(words[i + 1])) {
                // "1,5 km" chega partido na vírgula ("1", "5", "km"): a parte inteira sai junto.
                if let last = out.last, Int(last) != nil { out.removeLast() }
                while let last = out.last, lead.contains(last) { out.removeLast() }
                i += joined ? 1 : 2
                continue
            }
            out.append(w)
            i += 1
        }
        return out
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
