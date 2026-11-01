import Foundation
import FoundationModels
import Observation

// MARK: - Resumo no aparelho

@Generable
struct GeneratedTipsSummary {
    @Guide(description: "Resumo em português do Brasil, no máximo 60 palavras, prático (o que pedir, quando ir, como pagar, reserva). Coloque em **negrito** os 3 a 5 substantivos-chave.")
    var summary: String
    @Guide(description: "Até 6 temas que se repetem nas dicas", .maximumCount(6))
    var themes: [GeneratedTheme]
}

@Generable
struct GeneratedTheme {
    @Guide(description: "Uma ou duas palavras em português, minúsculas (ex.: uni, balcão, dinheiro, fila, caro)")
    var word: String
    @Guide(description: "Em quantas dicas aparece")
    var count: Int
    @Guide(description: "Tom das dicas sobre o tema", .anyOf(["positive", "negative", "neutral"]))
    var sentiment: String
}

struct TipsSummary: Equatable, Sendable {
    struct Theme: Equatable, Sendable, Identifiable {
        enum Sentiment: String, Sendable { case positive, negative, neutral }
        var word: String
        var count: Int
        var sentiment: Sentiment
        var id: String { word }
    }

    var summary: String
    var themes: [Theme]
}

@Generable
struct GeneratedTranslation {
    @Guide(description: "Tradução fiel para português do Brasil, curta e natural")
    var text: String
}

enum TipsAI {
    static let maxCharacters = 3500

    /// Resumir e traduzir texto de terceiros é transformação de conteúdo: guardrail permissivo
    /// (o padrão barrava dicas comuns, ex. "fígado com jiló").
    static var model: SystemLanguageModel { SystemLanguageModel(guardrails: .permissiveContentTransformations) }

    /// Corta as dicas em 3.500 caracteres, das mais úteis/recentes pras outras.
    static func digest(_ tips: [Tip]) -> String {
        var out = ""
        for tip in TipsModel.sorted(tips, by: .useful) {
            let line = "- [\(tip.source.chip)\(tip.rating.map { " \(Int($0))★" } ?? "")] \(tip.translation ?? tip.text)\n"
            if out.count + line.count > maxCharacters { break }
            out += line
        }
        return out
    }

    static func summarize(_ tips: [Tip], place: String) async -> TipsSummary? {
        guard OnDeviceAI.isAvailable, !tips.isEmpty else { return nil }
        let digest = digest(tips)
        let instructions = """
        Você resume dicas de pessoas que foram a um lugar (\(place)). Use só o que está nas dicas, sem inventar.
        Escreva em português do Brasil.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let g = try await session.respond(to: digest, generating: GeneratedTipsSummary.self).content
            return TipsSummary(summary: g.summary, themes: g.themes.prefix(6).map {
                .init(word: $0.word.lowercased(), count: max(1, $0.count), sentiment: .init(rawValue: $0.sentiment) ?? .neutral)
            })
        } catch {
            Log.intelligence.error("resumo das dicas (estruturado): \(String(describing: error).prefix(200), privacy: .public)")
        }
        // O guardrail permissivo só vale pra texto livre: pede num formato fixo e lê.
        do {
            let session = LanguageModelSession(model: model, instructions: instructions + """

            Responda exatamente em duas linhas:
            RESUMO: <até 60 palavras, com **negrito** nos 3 a 5 substantivos-chave>
            TEMAS: <palavra>|<quantas dicas>|<positive, negative ou neutral>; <palavra>|<n>|<tom>; …
            """)
            let text = try await session.respond(to: digest).content
            return parse(text)
        } catch {
            Log.intelligence.error("resumo das dicas (texto): \(String(describing: error).prefix(200), privacy: .public)")
            return nil
        }
    }

    /// Lê "RESUMO: …" / "TEMAS: a|3|positive; b|1|negative".
    static func parse(_ text: String) -> TipsSummary? {
        var summary = ""
        var themes: [TipsSummary.Theme] = []
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.uppercased().hasPrefix("RESUMO:") {
                summary = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("TEMAS:") {
                for item in line.dropFirst(6).split(separator: ";") {
                    let parts = item.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard let word = parts.first, !word.isEmpty else { continue }
                    let count = parts.count > 1 ? Int(parts[1].filter(\.isNumber)) ?? 1 : 1
                    let tone = parts.count > 2 ? TipsSummary.Theme.Sentiment(rawValue: parts[2].lowercased()) ?? .neutral : .neutral
                    themes.append(.init(word: word.lowercased(), count: max(1, count), sentiment: tone))
                }
            } else if summary.isEmpty {
                summary = line
            }
        }
        guard !summary.isEmpty else { return nil }
        return TipsSummary(summary: summary, themes: Array(themes.prefix(6)))
    }

    static func translate(_ text: String) async -> String? {
        guard OnDeviceAI.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(model: model, instructions: "Traduza do japonês (ou inglês) para português do Brasil. Responda só a tradução.")
            return try await session.respond(to: text, generating: GeneratedTranslation.self).content.text
        } catch {
            Log.intelligence.error("tradução: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

// MARK: - Modelo da seção

/// Junta as fontes, traduz o que está em japonês e resume — tudo depois que a seção aparece na tela.
@MainActor
@Observable
final class TipsModel {
    enum Phase: Equatable { case idle, loading, loaded, off }
    nonisolated enum Filter: String, CaseIterable, Identifiable, Sendable {
        case useful, recent, japanese, critical
        var id: String { rawValue }
        var label: String {
            switch self {
            case .useful: "Mais úteis"
            case .recent: "Recentes"
            case .japanese: "Em japonês"
            case .critical: "Críticas"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var tips: [Tip] = []
    private(set) var rating: Double?
    private(set) var ratingCount: Int?
    private(set) var sources: Set<TipSource> = []
    private(set) var summary: TipsSummary?
    private(set) var summarizing = false
    var filter: Filter = .useful

    /// Avisado quando o Foursquare acha o `fsq_place_id` (salvar no `Place`).
    @ObservationIgnored var onFoursquareMatch: (String) -> Void = { _ in }

    func load(_ query: TipsQuery, providers: [any TipsProviding], enabled: Bool) async {
        guard phase == .idle else { return }
        guard enabled else {
            // Desligado: só a legenda de origem (não sai do aparelho).
            phase = .off
            tips = (try? await SourceCaptionTips().tips(for: query).tips) ?? []
            return
        }
        phase = .loading
        await TipsCache.shared.purge()
        let active = providers.filter(\.isConfigured)
        var batches: [(TipSource, TipsBatch)] = []
        await withTaskGroup(of: (TipSource, TipsBatch?).self) { group in
            for provider in active {
                group.addTask {
                    let source = provider.source
                    // Amostras (prints) não passam pelo cache; resposta vazia não é guardada (ex.: sem placeId ainda).
                    let cacheable = source.isThirdParty && !(provider is FakeTipsProvider)
                    if cacheable, let cached = await TipsCache.shared.batch(query, source) { return (source, cached) }
                    do {
                        let batch = try await provider.tips(for: query)
                        if cacheable, !batch.tips.isEmpty { await TipsCache.shared.store(batch, query, source) }
                        return (source, batch)
                    } catch {
                        Log.network.error("dicas \(source.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return (source, await TipsCache.shared.batch(query, source, allowStale: true))
                    }
                }
            }
            for await (source, batch) in group { if let batch { batches.append((source, batch)) } }
        }
        for (source, batch) in batches {
            tips += batch.tips
            if !batch.tips.isEmpty { sources.insert(source) }
            if source == .google { rating = batch.rating; ratingCount = batch.ratingCount }
            if source == .foursquare, let id = batch.fsqId, id != query.fsqId { onFoursquareMatch(id) }
        }
        tips = Self.sorted(tips, by: .useful)
        phase = .loaded

        // Tradução e resumo no aparelho, depois que as fontes responderam.
        summarizing = OnDeviceAI.isAvailable && tips.contains { $0.source != .caption }
        for (i, tip) in tips.enumerated() where tip.isJapanese && tip.translation == nil {
            if let pt = await TipsAI.translate(tip.quote) { tips[i].translated = pt }
        }
        if summarizing {
            summary = await TipsAI.summarize(tips, place: query.name)
            summarizing = false
        }
    }

    var visible: [Tip] {
        let shown = Self.sorted(tips, by: filter)
        switch filter {
        case .useful, .recent: return shown
        case .japanese: return shown.filter(\.isJapanese)
        case .critical:
            let negative = Set(summary?.themes.filter { $0.sentiment == .negative }.map(\.word) ?? [])
            return shown.filter { tip in
                if let r = tip.rating, r <= 3 { return true }
                let text = (tip.translation ?? tip.text).lowercased()
                return negative.contains { text.contains($0) }
            }
        }
    }

    var hasJapanese: Bool { tips.contains { $0.isJapanese } }

    nonisolated static func sorted(_ tips: [Tip], by filter: Filter) -> [Tip] {
        tips.sorted { a, b in
            // A legenda de origem é sempre o primeiro card.
            if (a.source == .caption) != (b.source == .caption) { return a.source == .caption }
            switch filter {
            case .recent:
                return (a.date ?? .distantPast) > (b.date ?? .distantPast)
            default:
                return usefulness(a) > usefulness(b)
            }
        }
    }

    /// Mais votada, melhor detalhada (texto médio) e mais recente primeiro.
    nonisolated static func usefulness(_ tip: Tip) -> Double {
        let votes = log2(Double(max(0, tip.votes ?? 0)) + 1) * 2
        let length = min(Double(tip.text.count), 280) / 70
        let rating = (tip.rating ?? 3.5) / 2
        let age = tip.date.map { max(0, 2 - Date().timeIntervalSince($0) / (86400 * 365)) } ?? 0.5
        return votes + length + rating + age
    }
}
