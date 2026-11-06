import Foundation
import FoundationModels
import SwiftData

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
    /// Teto do modelo por bloco e no texto todo (rodada 23 · G): 5.000 caracteres colados deixavam o "Lendo o texto…"
    /// mais de 30 s na tela (sem fim no simulador). Passou do teto, o bloco cai nas palavras-chave — nunca espera pra sempre.
    static let blockTimeout: Duration = .seconds(12)
    static let totalTimeout: Duration = .seconds(20)

    static func analyze(_ text: String, onDevice: Bool, knownAreas: [String],
                        blockTimeout: Duration = blockTimeout, totalTimeout: Duration = totalTimeout,
                        model: @escaping @Sendable (String) async throws -> ParsedTravelText = { try await respond($0) }) async -> TravelTextDraft {
        var parts: [TravelTextDraft] = []
        var usedModel = false
        let clock = ContinuousClock()
        let started = clock.now
        for block in blocks(text) {
            let left = totalTimeout - (clock.now - started)
            if onDevice, OnDeviceAI.isAvailable, left > .zero,
               let parsed = await withDeadline(min(blockTimeout, left), { try await model(block) }) {
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

    /// O resultado de `work`, ou nil se passar de `limit` (a tarefa é cancelada) ou falhar.
    static func withDeadline<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Reforço na nuvem só quando o aparelho acha menos de dois lugares (rodada 21 · fatia 3).
    static let cloudThreshold = 2

    static func needsCloud(_ draft: TravelTextDraft) -> Bool {
        draft.places.count < cloudThreshold
    }

    /// Resposta crua do Haiku → draft do mesmo formato do aparelho (os nomes que não estão no texto caem, como no aparelho).
    static func draft(fromCloud data: Data, text: String, knownAreas: [String]) throws -> TravelTextDraft {
        let parsed = try CloudBoost.parseText(data)
        var out = map(parsed, text: String(text.prefix(CloudBoost.textMaxLength)), knownAreas: knownAreas)
        out.via = "reforço na nuvem"
        return out
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

/// Fila do reforço na nuvem do texto colado (rodada 21 · fatia 3): sem rede, o pedido espera no `Outbox`
/// (`OutboxKind.cloudText`, uma por texto). Quando a fila termina, a resposta crua fica no item e o Colar texto a usa.
@MainActor
enum TravelTextCloud {
    /// Resposta já feita pela fila pra este texto (nil = ainda não, ou não lê mais).
    static func done(for key: String, context: ModelContext) -> Data? {
        let done = (try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.done }))) ?? []
        guard let item = done.last(where: { $0.ref == key && $0.outboxKind == .cloudText }), let data = item.result,
              (try? CloudBoost.parseText(data)) != nil else { return nil }
        return data
    }

    /// Põe o texto na fila (uma por texto: pedir de novo não duplica).
    static func enqueue(_ text: String, key: String, context: ModelContext) {
        let item = Outbox.enqueue(.cloudText, ref: key, context: context)
        guard item.result == nil else { return }
        item.result = Data(text.utf8)
        try? context.save()
    }

    /// Tira da fila o que já foi usado (o texto foi salvo).
    static func forget(_ key: String, context: ModelContext) {
        let done = (try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.done }))) ?? []
        for item in done where item.ref == key && item.outboxKind == .cloudText {
            context.delete(item)
        }
    }
}
