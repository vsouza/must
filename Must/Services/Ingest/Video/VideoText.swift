import Foundation

/// Um pedaço de texto tirado do vídeo (prompt 29): de onde veio e em que segundo.
struct VideoSnippet: Equatable, Sendable {
    enum Origin: String, Sendable { case caption, screen, speech }
    var origin: Origin
    var seconds: Double
    var text: String
}

/// De onde um lugar apareceu: "visto na tela 00:04", "falado 00:07", "na legenda".
struct VideoOrigin: Equatable, Sendable {
    var origin: VideoSnippet.Origin
    var seconds: Double

    var label: String {
        switch origin {
        case .screen: "visto na tela \(VideoText.clock(seconds))"
        case .speech: "falado \(VideoText.clock(seconds))"
        case .caption: "na legenda"
        }
    }
}

/// Junta legenda + OCR + fala num texto só, com marcas de origem, e acha de onde cada nome veio.
enum VideoText {
    /// Orçamento do texto que vai pro extrator (`CaptionFetcher.maxLength`): legenda, depois tela, depois fala.
    static let captionBudget = 500
    static let screenBudget = 900

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func merge(caption: String?, screen: [VideoSnippet], speech: [VideoSnippet], limit: Int = CaptionFetcher.maxLength) -> String {
        var lines: [String] = []
        var used = 0
        func add(_ line: String, budget: Int, spent: inout Int) -> Bool {
            guard spent + line.count + 1 <= budget, used + line.count + 1 <= limit else { return false }
            lines.append(line)
            spent += line.count + 1
            used += line.count + 1
            return true
        }
        var spentCaption = 0
        let cleanCaption = (caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanCaption.isEmpty {
            let flat = cleanCaption.replacingOccurrences(of: "\n", with: " ")
            _ = add("[legenda] " + String(flat.prefix(captionBudget - 12)), budget: captionBudget, spent: &spentCaption)
        }
        var spentScreen = 0
        for item in dedupe(screen).sorted(by: { $0.seconds < $1.seconds }) {
            _ = add("[tela \(clock(item.seconds))] \(item.text)", budget: screenBudget, spent: &spentScreen)
        }
        var spentSpeech = 0
        for item in speech.sorted(by: { $0.seconds < $1.seconds }) {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            _ = add("[fala \(clock(item.seconds))] \(text)", budget: limit, spent: &spentSpeech)
        }
        return lines.joined(separator: "\n")
    }

    /// Linhas repetidas entre quadros viram uma só (a primeira vez que apareceram); a mais completa vence.
    static func dedupe(_ snippets: [VideoSnippet]) -> [VideoSnippet] {
        var kept: [(key: String, snippet: VideoSnippet)] = []
        for snippet in snippets.sorted(by: { $0.seconds < $1.seconds }) {
            let key = normalize(snippet.text)
            guard key.count >= 3 else { continue }
            if kept.contains(where: { $0.key.contains(key) }) { continue }
            if let i = kept.firstIndex(where: { key.contains($0.key) }) {
                // O novo é a versão completa de um texto que o OCR leu cortado: troca, mantendo o instante.
                kept[i] = (key, VideoSnippet(origin: snippet.origin, seconds: kept[i].snippet.seconds, text: snippet.text))
                continue
            }
            kept.append((key, snippet))
        }
        return kept.map(\.snippet)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Textos de interface do Instagram/TikTok que o OCR lê na gravação de tela e não são lugar.
    static let interfaceWords: Set<String> = [
        "seguir", "seguindo", "follow", "following", "curtir", "comentar", "compartilhar", "reels", "reel", "salvar",
        "patrocinado", "sponsored", "mensagem", "enviar", "mais", "ver traducao", "audio original", "original audio",
        "para voce", "for you", "ao vivo", "live", "likes", "curtidas", "comentarios", "tiktok", "instagram",
    ]

    /// Primeira vez que cada nome aparece, preferindo a tela, depois a fala, depois a legenda.
    static func origin(of names: [String], in merged: String) -> VideoOrigin? {
        let keys = names.map(normalize).filter { $0.count >= 3 }
        guard !keys.isEmpty else { return nil }
        var best: [VideoSnippet.Origin: VideoOrigin] = [:]
        for line in merged.split(separator: "\n") {
            guard let parsed = parse(String(line)) else { continue }
            let key = normalize(parsed.text)
            guard keys.contains(where: { key.contains($0) }), best[parsed.origin] == nil else { continue }
            best[parsed.origin] = VideoOrigin(origin: parsed.origin, seconds: parsed.seconds)
        }
        return best[.screen] ?? best[.speech] ?? best[.caption]
    }

    /// "[tela 00:04] Udatsu Sushi" → (tela, 4, "Udatsu Sushi").
    static func parse(_ line: String) -> (origin: VideoSnippet.Origin, seconds: Double, text: String)? {
        if let m = line.wholeMatch(of: /\[(tela|fala) (\d{2,}):(\d{2})\]\s*(.*)/) {
            let seconds = (Double(m.2) ?? 0) * 60 + (Double(m.3) ?? 0)
            return (m.1 == "tela" ? .screen : .speech, seconds, String(m.4))
        }
        if let m = line.wholeMatch(of: /\[legenda\]\s*(.*)/) { return (.caption, 0, String(m.1)) }
        return nil
    }
}

/// Texto do vídeo → candidatos com a origem (prompt 29). O extrator entra por parâmetro (teste usa um falso).
enum VideoIngest {
    struct Candidate: Equatable, Sendable {
        var place: ExtractedPlace
        var origin: VideoOrigin?
    }

    static func candidates(merged: String,
                           extractor: @Sendable (String) async -> [ExtractedPlace]) async -> [Candidate] {
        let places = await extractor(merged)
        return places.map { place in
            let names = [place.name, place.nameLocal].compactMap { $0 } + place.aliases
            return Candidate(place: place, origin: VideoText.origin(of: names, in: merged))
        }
    }
}
