import Foundation
import UIKit
import Vision

// Leitura de link, vídeo, texto e foto pro "Novo presente" (prompt 31 · item 7). Tudo no aparelho: legenda do link
// (`CaptionFetcher`), vídeo (`VideoReader`: fala + texto na tela) e texto da foto (Vision). Nada de API nova.

/// O que a leitura achou: nome, preço de uma unidade, quantidade e loja. Cada campo é opcional (confiança por campo).
struct GiftGuess: Equatable, Sendable {
    var title: String?
    var price: Double?
    var quantity: Int?
    var storeName: String?
    /// Loja que já está no board (`Place.id`).
    var storeId: String?
    /// "Qualquer <rede>": a loja é uma rede conhecida, sem endereço.
    var chain = false
    /// Autor do vídeo/link ("@tokyosnacks").
    var author: String?
    var clip: String?

    var isEmpty: Bool { title == nil && price == nil && storeName == nil }
}

/// Texto → palpite. Puro e testado.
enum GiftTextGuess {
    /// Redes comuns de presente no Japão e na Itália (a loja vira "qualquer rede" quando não está no board).
    static let chains = ["don quijote", "donki", "uniqlo", "muji", "loft", "tokyu hands", "hands", "bic camera", "yodobashi",
                         "daiso", "pokémon center", "pokemon center", "disk union", "ito-ya", "itoya", "tower records",
                         "lush", "sephora", "feltrinelli", "coin"]

    struct Store: Equatable, Sendable { var id: String; var name: String }

    static func guess(from text: String, stores: [Store] = [], author: String? = nil) -> GiftGuess {
        var out = GiftGuess()
        out.author = author ?? mention(in: text)
        out.title = title(from: text)
        if let price = price(in: text) { out.price = price }
        out.quantity = quantity(in: text)
        let lower = text.lowercased()
        if let store = stores.first(where: { lower.contains($0.name.lowercased()) }) {
            out.storeName = store.name
            out.storeId = store.id
        } else if let chain = chains.first(where: { lower.contains($0) }) {
            out.storeName = chain.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            out.chain = true
        }
        return out
    }

    /// Primeira frase útil, sem link, #hashtag, @menção nem emoji; até 60 caracteres.
    static func title(from text: String) -> String? {
        var cleaned = text
        for pattern in [#"https?://\S+"#, #"[#@]\S+"#, #"[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]"#] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let lines = cleaned.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 }
        guard var first = lines.first else { return nil }
        if let end = first.firstIndex(where: { ".!?:".contains($0) }), first.distance(from: first.startIndex, to: end) >= 3 {
            first = String(first[..<end])
        }
        first = first.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard first.count >= 3 else { return nil }
        if first.count > 60 { first = String(first.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return first
    }

    /// "¥1.200", "1,200円", "R$ 25,90", "€ 12,50" → valor de uma unidade.
    static func price(in text: String) -> Double? {
        let patterns = [#"(?:¥|￥|R\$|€|\$)\s?(\d[\d.,]*)"#, #"(\d[\d.,]*)\s?(?:円|yen|reais|euros?)"#]
        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(text[range])
            let digits = match.drop { !$0.isNumber }.prefix { $0.isNumber || ".,".contains($0) }
            let isYen = match.contains("¥") || match.contains("￥") || match.contains("円") || match.lowercased().contains("yen")
            if let value = parse(String(digits), whole: isYen) { return value }
        }
        return nil
    }

    private static func parse(_ raw: String, whole: Bool) -> Double? {
        var s = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if whole { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "") }
        else if let comma = s.lastIndex(of: ","), s.distance(from: comma, to: s.endIndex) <= 3 {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let dot = s.lastIndex(of: "."), s.distance(from: dot, to: s.endIndex) == 4 {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        return Double(s).flatMap { $0 > 0 ? $0 : nil }
    }

    /// "3 caixas", "x3", "× 3", "3 unidades" → 3.
    static func quantity(in text: String) -> Int? {
        let patterns = [#"[x×]\s?(\d{1,2})\b"#, #"\b(\d{1,2})\s?(?:caixas?|unidades?|pacotes?|un\b|pcs|peças)"#]
        for pattern in patterns {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let digits = text[range].filter(\.isNumber)
            if let n = Int(digits), (2...50).contains(n) { return n }
        }
        return nil
    }

    private static func mention(in text: String) -> String? {
        text.range(of: #"@[A-Za-z0-9_.]{3,30}"#, options: .regularExpression).map { String(text[$0]) }
    }
}

/// Leitura com rede/arquivo: link → legenda; vídeo → fala e texto da tela; foto → texto (Vision).
enum GiftReader {
    /// Legenda do link (uma chamada). Sem rede ou sem legenda: `nil` (a pessoa digita).
    static func readLink(_ input: String, stores: [GiftTextGuess.Store]) async -> GiftGuess? {
        let link = LinkResolver.resolve(input)
        guard link.url != nil else { return link.text.isEmpty ? nil : GiftTextGuess.guess(from: link.text, stores: stores) }
        guard let caption = try? await CaptionFetcher().fetch(link) else { return nil }
        let text = [caption.title, caption.text].compactMap { $0 }.joined(separator: "\n")
        var guess = GiftTextGuess.guess(from: text, stores: stores)
        if guess.title == nil { guess.title = caption.title }
        return guess
    }

    /// Vídeo gravado (arquivo local): fala + texto na tela, no aparelho.
    static func readVideo(_ url: URL, region: Region, caption: String?, stores: [GiftTextGuess.Store]) async -> GiftGuess? {
        var options = VideoReader.Options()
        options.locale = VideoReader.Options.locale(for: region)
        options.allowModelDownload = false
        guard let reading = try? await VideoReader().read(url, options: options) else { return nil }
        return GiftTextGuess.guess(from: reading.merged(caption: caption), stores: stores)
    }

    /// Texto de uma foto (etiqueta, embalagem, print).
    static func readPhoto(_ image: UIImage, stores: [GiftTextGuess.Store]) async -> GiftGuess? {
        guard let cg = image.cgImage else { return nil }
        let text: String = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US", "ja-JP", "it-IT"]
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
        guard !text.isEmpty else { return nil }
        return GiftTextGuess.guess(from: text, stores: stores)
    }
}
