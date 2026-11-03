import Foundation
import FoundationModels

// Saída estruturada do texto colado (prompt 18 · E.21). Os nomes ficam com o prefixo "Text" pra não colidir com
// `ExtractedPlace` (o modelo da conferência) e com `Tip` (as Dicas do Lugar).

@Generable
struct ParsedTravelText {
    @Guide(description: "Dias sugeridos no texto (Dia 1, Dia 2, ou um roteiro por bairro). Vazio se não houver.", .maximumCount(12))
    var days: [SuggestedDay]
    @Guide(description: "Lugares físicos citados (restaurantes, bares, cafés, lojas, templos, museus, mirantes). Nunca invente nome.",
           .maximumCount(40))
    var places: [TextPlace]
    @Guide(description: "Dicas práticas do texto: reservar, comprar ingresso ou passe, chegar cedo, horário.", .maximumCount(12))
    var tips: [TextTipDraft]
}

@Generable
struct SuggestedDay {
    @Guide(description: "Título do dia como aparece no texto")
    var title: String
    @Guide(description: "Bairro ou tema do dia (ex.: Asakusa e Ueno), ou vazio")
    var area: String
    @Guide(description: "Nomes dos lugares do dia, na ordem do texto", .maximumCount(20))
    var items: [String]
}

@Generable
struct TextPlace {
    @Guide(description: "Nome do lugar como aparece no texto")
    var name: String
    @Guide(description: "Nome em japonês ou no idioma local, se aparecer, senão vazio")
    var nameLocal: String
    @Guide(description: "Bairro se aparecer, senão vazio")
    var area: String
    @Guide(description: "Categoria do lugar",
           .anyOf(["eat", "drink", "coffee", "see", "temple", "listen", "shop", "night", "photo", "art", "sport", "none"]))
    var category: String
    @Guide(description: "Tipo ou especialidade (ex.: Ramen, Sushi, Café, Templos, Arte, Bar), senão vazio")
    var sub: String
    @Guide(description: "Por que o texto cita (até 8 palavras)")
    var why: String
}

@Generable
struct TextTipDraft {
    @Guide(description: "A dica em uma frase curta")
    var text: String
    @Guide(description: "Pra onde vai: place (nota de um lugar), wallet (ingresso, passe, cartão, eSIM, seguro), general",
           .anyOf(["place", "wallet", "general"]))
    var kind: String
    @Guide(description: "Nome do lugar, se kind for place; senão vazio")
    var placeName: String
}

/// Texto colado → dias, lugares, dicas e links. No aparelho (Foundation Models) em blocos de ~3.000 caracteres;
/// sem modelo, ou se um bloco falhar, o `TravelTextParser` (regex) cobre aquele bloco (prompt 18 · E.21).
enum TravelTextExtractor {
    static let blockSize = 3_000

    static let instructions = """
    Você lê um texto colado de uma resposta de IA, de uma lista ou de uma mensagem, sobre um roteiro de viagem. \
    Separe os dias sugeridos, os lugares físicos citados e as dicas práticas. Não invente lugar: só nomes que \
    estão no texto. Ignore links, hashtags e cidades ou países como lugar.
    """

    /// Pedaços de até `size` caracteres, cortados entre linhas (uma linha maior que o limite é cortada no meio).
    static func blocks(_ text: String, size: Int = blockSize) -> [String] {
        var out: [String] = []
        var current = ""
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var piece = String(line)
            while piece.count > size {
                if !current.isEmpty { out.append(current); current = "" }
                out.append(String(piece.prefix(size)))
                piece = String(piece.dropFirst(size))
            }
            if current.count + piece.count + 1 > size, !current.isEmpty {
                out.append(current)
                current = ""
            }
            current += current.isEmpty ? piece : "\n" + piece
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Analisa o texto inteiro: por bloco, Foundation Models (se `onDevice` e disponível) ou regex. Links vêm do texto todo.
    static func analyze(_ text: String, onDevice: Bool, knownAreas: [String]) async -> TravelTextDraft {
        var parts: [TravelTextDraft] = []
        var usedModel = false
        for block in blocks(text) {
            if onDevice, OnDeviceAI.isAvailable, let parsed = try? await respond(block) {
                parts.append(map(parsed, text: block, knownAreas: knownAreas))
                usedModel = true
            } else {
                parts.append(TravelTextParser.parse(block, knownAreas: knownAreas))
            }
        }
        var draft = TravelTextDraft.merge(parts)
        draft.links = TravelTextParser.links(in: text)
        draft.via = usedModel ? "no aparelho" : "palavras-chave"
        return draft
    }

    /// Aquece o modelo só quando a tela de texto abre (não no arranque): a primeira resposta sai mais rápido.
    static func prewarm() {
        guard OnDeviceAI.isAvailable else { return }
        Task.detached(priority: .utility) {
            LanguageModelSession(instructions: instructions).prewarm()
        }
    }

    static func respond(_ block: String) async throws -> ParsedTravelText {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: "Texto:\n\(block)", generating: ParsedTravelText.self).content
    }

    /// Saída do modelo → draft. Nome que não aparece no bloco é descartado (o modelo não inventa lugar).
    static func map(_ parsed: ParsedTravelText, text: String, knownAreas: [String]) -> TravelTextDraft {
        let areas = knownAreas + TravelTextParser.builtinAreas
        var places: [ExtractedPlace] = []
        for g in parsed.places {
            let name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, TravelTextParser.acceptable(name, areas: areas),
                  text.localizedCaseInsensitiveContains(name.split(separator: " ").first.map(String.init) ?? name) else { continue }
            let dayIndex = parsed.days.firstIndex { day in day.items.contains { PlaceMatcher.normalize($0) == PlaceMatcher.normalize(name) } }
            places.append(ExtractedPlace(name: name, nameLocal: g.nameLocal.isEmpty ? nil : g.nameLocal,
                                         area: g.area.isEmpty ? TravelTextParser.area(in: text, areas: areas) : g.area,
                                         category: MustColor(rawValue: g.category) ?? TravelCategory.color(name: name, context: text),
                                         sub: g.sub.isEmpty ? PlaceExtractor.sub(in: name) : g.sub,
                                         hint: g.why.isEmpty ? "citado no texto" : g.why, dayIndex: dayIndex))
        }
        let days = parsed.days.map { day in
            TravelDay(number: day.title.firstMatch(of: /(\d{1,2})/).flatMap { Int($0.1) }, title: day.title,
                      area: day.area.isEmpty ? nil : day.area, items: day.items)
        }
        let tips = parsed.tips.compactMap { tip -> TravelTip? in
            let text = tip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch tip.kind {
            case "place" where !tip.placeName.isEmpty: return TravelTip(text: text, target: .place(tip.placeName))
            case "wallet": return TravelTip(text: text, target: .wallet)
            default: return TravelTip(text: text, target: .general)
            }
        }
        return TravelTextDraft(days: days, places: places, tips: tips, links: [], via: "no aparelho")
    }
}
