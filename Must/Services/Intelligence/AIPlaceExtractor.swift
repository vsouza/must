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
    @Guide(description: "Categoria", .anyOf(["eat", "drink", "coffee", "see", "temple", "listen", "shop", "night", "none"]))
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
    }

    /// Legendas longas (> 1.200 caracteres) vão pro reforço na nuvem quando ligado.
    static let longCaption = 1200

    static func extract(from caption: Caption, options: Options) async -> (places: [ExtractedPlace], via: String) {
        // Link do Maps já traz o nome.
        if caption.placeName != nil { return (PlaceExtractor.extract(from: caption, knownAreas: options.knownAreas), "link do Maps") }
        let text = String(caption.text.prefix(CaptionFetcher.maxLength))

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
            return ExtractedPlace(name: name, nameLocal: g.nameLocal.isEmpty ? nil : g.nameLocal,
                                  area: g.area.isEmpty ? PlaceExtractor.area(in: text, known: knownAreas) : g.area,
                                  category: MustColor(rawValue: g.category), sub: PlaceExtractor.sub(in: "\(name) \(text)"),
                                  hint: g.hint.isEmpty ? "citado na legenda" : g.hint)
        }
    }
}

/// Reforço opcional com Claude Haiku (desligado por padrão). Só manda o texto da legenda —
/// nunca localização nem o board. Chave em `Secrets.plist` (ANTHROPIC_KEY).
enum CloudBoost {
    static let model = "claude-haiku-5-5"
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
                        "category": ["type": "string", "enum": ["eat", "drink", "coffee", "see", "temple", "listen", "shop", "night", "none"]],
                        "hint": ["type": "string"],
                    ],
                ],
            ],
        ],
    ] }

    static func extract(_ text: String, knownAreas: [String], http: HTTP = HTTP()) async throws -> [ExtractedPlace] {
        guard let key = Secrets.anthropicKey else { throw ServiceError.missingKey("ANTHROPIC_KEY") }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": AIPlaceExtractor.instructions + " Responda em pt-BR. Use string vazia quando não souber.",
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": "Legenda:\n\(text)"]],
        ]
        let data = try await http.post(URL(string: "https://api.anthropic.com/v1/messages")!, json: body,
                                       headers: ["x-api-key": key, "anthropic-version": "2026-10-21"], service: "anthropic")
        return try parse(data, text: text, knownAreas: knownAreas)
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
