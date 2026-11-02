import Foundation
import FoundationModels

@Generable
struct GeneratedPlace {
    @Guide(description: "Nome do lugar como aparece (ex.: Menya Kaijin)")
    var name: String
    @Guide(description: "Nome em japonês se aparecer, ou vazio")
    var nameLocal: String
    @Guide(description: "Bairro se aparecer, ou vazio")
    var area: String
    @Guide(description: "Categoria (photo = spot de foto/mirante de rua, art = exposição/galeria/show, sport = corrida/trilha/jogo)",
           .anyOf(["eat", "drink", "coffee", "see", "temple", "listen", "shop", "night", "photo", "art", "sport", "none"]))
    var category: String
    @Guide(description: "Frase curta do porquê/o que a legenda diz (até 8 palavras)")
    var hint: String
}

@Generable
struct GeneratedPlaces {
    @Guide(description: "Lugares citados (restaurantes, bares, lojas, templos…). Vazio se não houver.", .maximumCount(5))
    var places: [GeneratedPlace]
}

/// Extrator de lugares de um link: Foundation Models → (opcional) Claude Haiku → regex.
enum AIPlaceExtractor {
    static let instructions = """
    Você lê a legenda de um vídeo ou post e lista os lugares físicos citados (restaurantes, cafés, bares, lojas, \
    templos, museus). Não invente: só nomes que estão no texto. Ignore hashtags genéricas, cidades e países.
    """

    struct Options: Sendable {
        var onDevice: Bool
        var cloudBoost: Bool
        var knownAreas: [String]
        /// Fuso das sessões de evento ("19:00" de Tóquio).
        var timeZone: TimeZone = .current
    }

    /// Legendas longas (> 1.200 caracteres) vão pro reforço na nuvem quando ligado.
    static let longCaption = 1200

    static func extract(from caption: Caption, options: Options) async -> (places: [ExtractedPlace], via: String) {
        // Link do Maps já traz o nome.
        if caption.placeName != nil { return (PlaceExtractor.extract(from: caption, knownAreas: options.knownAreas), "link do Maps") }
        let text = String(caption.text.prefix(CaptionFetcher.maxLength))

        // Página de museu/galeria/show ou link de ingresso: vira Must art com temporada e preço.
        if EventExtractor.looksLikeEvent(text, url: caption.url) {
            if options.onDevice, OnDeviceAI.isAvailable,
               let event = try? await EventExtractor.onDevice(text, url: caption.url, timeZone: options.timeZone) {
                return ([event], "evento · no aparelho")
            }
            var places = PlaceExtractor.extract(text: text, knownAreas: options.knownAreas)
            if !places.isEmpty {
                places[0].art = EventExtractor.parse(text, url: caption.url, timeZone: options.timeZone)
                places[0].category = .art
                return (places, "evento · palavras-chave")
            }
        }

        if options.onDevice, OnDeviceAI.isAvailable, text.count <= longCaption || !options.cloudBoost {
            if let places = try? await onDevice(text, knownAreas: options.knownAreas), !places.isEmpty {
                return (places, "no aparelho")
            }
        }
        if options.cloudBoost, CloudBoost.isConfigured {
            do {
                let places = try await CloudBoost.extract(text, knownAreas: options.knownAreas)
                if !places.isEmpty { return (places, "reforço na nuvem") }
            } catch {
                Log.intelligence.error("reforço na nuvem: \(error.localizedDescription, privacy: .public)")
            }
        }
        return (PlaceExtractor.extract(text: text, knownAreas: options.knownAreas), "palavras-chave")
    }

    static func onDevice(_ text: String, knownAreas: [String]) async throws -> [ExtractedPlace] {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Legenda:\n\(text)", generating: GeneratedPlaces.self)
        return map(response.content.places, text: text, knownAreas: knownAreas)
    }

    static func map(_ places: [GeneratedPlace], text: String, knownAreas: [String]) -> [ExtractedPlace] {
        places.compactMap { g in
            let name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Nunca aceita nome que não está no texto (o modelo não inventa lugar).
            guard !name.isEmpty, text.localizedCaseInsensitiveContains(name.split(separator: " ").first.map(String.init) ?? name) else { return nil }
            // Categoria e sub do próprio lugar; o modelo só entra com a categoria, e a legenda inteira não manda no sub.
            let near = PlaceExtractor.window(around: name, in: text)
            return ExtractedPlace(name: name, nameLocal: g.nameLocal.isEmpty ? nil : g.nameLocal,
                                  area: g.area.isEmpty ? PlaceExtractor.area(in: text, known: knownAreas) : g.area,
                                  category: MustColor(rawValue: g.category) ?? PlaceExtractor.category(in: name)
                                      ?? PlaceExtractor.category(in: near),
                                  sub: PlaceExtractor.sub(in: name) ?? PlaceExtractor.sub(in: near),
                                  hint: g.hint.isEmpty ? "citado na legenda" : g.hint)
        }
    }
}

/// Reforço opcional com Claude Haiku (desligado por padrão). Só manda o texto da legenda —
/// nunca localização nem o board. Chave em `Secrets.plist` (ANTHROPIC_KEY).
///
/// REGRA (pedido do Vinicius, crítico): só o modelo mais barato (Haiku) e o effort mais baixo (`low`).
/// Nada de Sonnet/Opus, thinking ou effort maior. `CloudBoostTests` quebra se isso mudar.
enum CloudBoost {
    static let model = "claude-haiku-5-5"
    static let effort = "low"
    /// Até 5 lugares em JSON cabem com folga.
    static let maxTokens = 1024
    static var isConfigured: Bool { Secrets.anthropicKey != nil }

    /// Mesmo esquema do extrator no aparelho.
    static var schema: [String: Any] { [
        "type": "object",
        "additionalProperties": false,
        "required": ["places"],
        "properties": [
            "places": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "nameLocal", "area", "category", "hint"],
                    "properties": [
                        "name": ["type": "string"],
                        "nameLocal": ["type": "string"],
                        "area": ["type": "string"],
                        "category": ["type": "string", "enum": ["eat", "drink", "coffee", "see", "temple", "listen", "shop", "night",
                                                                "photo", "art", "sport", "none"]],
                        "hint": ["type": "string"],
                    ],
                ],
            ],
        ],
    ] }

    static func extract(_ text: String, knownAreas: [String], http: HTTP = HTTP()) async throws -> [ExtractedPlace] {
        guard let key = Secrets.anthropicKey else { throw ServiceError.missingKey("ANTHROPIC_KEY") }
        let data = try await http.post(URL(string: "https://api.anthropic.com/v1/messages")!, json: requestBody(text),
                                       headers: ["x-api-key": key, "anthropic-version": "2026-10-21"], service: "anthropic")
        return try parse(data, text: text, knownAreas: knownAreas)
    }

    /// Corpo da chamada: Haiku, effort `low`, saída estruturada, sem thinking.
    static func requestBody(_ text: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": maxTokens,
            "system": AIPlaceExtractor.instructions + " Responda em pt-BR. Use string vazia quando não souber.",
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": "Legenda:\n\(text)"]],
        ]
    }

    /// Lê a resposta da Messages API (checa `stop_reason` antes do conteúdo).
    static func parse(_ data: Data, text: String, knownAreas: [String]) throws -> [ExtractedPlace] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("anthropic") }
        let stop = json["stop_reason"] as? String
        guard stop != "refusal", stop != "max_tokens" else { throw ServiceError.decoding("stop_reason \(stop ?? "")") }
        let content = json["content"] as? [[String: Any]] ?? []
        guard let textBlock = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payload = try JSONSerialization.jsonObject(with: Data(textBlock.utf8)) as? [String: Any] else {
            throw ServiceError.decoding("sem bloco de texto")
        }
        let items = payload["places"] as? [[String: Any]] ?? []
        let generated = items.map { i in
            GeneratedPlace(name: i["name"] as? String ?? "", nameLocal: i["nameLocal"] as? String ?? "", area: i["area"] as? String ?? "",
                           category: i["category"] as? String ?? "none", hint: i["hint"] as? String ?? "")
        }
        return AIPlaceExtractor.map(generated, text: text, knownAreas: knownAreas)
    }
}
