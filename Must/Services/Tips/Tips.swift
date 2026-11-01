import CoreLocation
import Foundation

/// De onde veio uma dica (chip mono no card).
enum TipSource: String, Codable, Sendable, CaseIterable {
    case caption, google, foursquare, reddit, tripadvisor

    var chip: String {
        switch self {
        case .caption: "IG"
        case .google: "G"
        case .foursquare: "FSQ"
        case .reddit: "Reddit"
        case .tripadvisor: "TA"
        }
    }

    /// Fontes de terceiros guardam no máximo 30 dias (regra do Google; vale pra todas).
    var isThirdParty: Bool { self != .caption }
}

/// Uma dica de quem foi.
struct Tip: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var source: TipSource
    /// Texto mostrado (o Google já manda traduzido quando dá).
    var text: String
    /// Original quando a fonte traduziu (Google `originalText`).
    var originalText: String?
    var language: String?
    var author: String?
    var authorURL: String?
    /// Nota 1–5 (Google).
    var rating: Double?
    /// ↑ (Reddit) / concordâncias (Foursquare).
    var votes: Int?
    var date: Date?
    /// "há 2 meses" (Google).
    var relativeDate: String?
    var subreddit: String?
    var url: String?
    /// Tradução pt-BR feita no aparelho.
    var translated: String?

    /// Original em japonês (kana/kanji) — mostra o original em serif e a tradução embaixo.
    var isJapanese: Bool {
        if let language, language.hasPrefix("ja") { return true }
        return (originalText ?? text).unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    /// Texto no idioma original (pra citação).
    var quote: String { originalText ?? text }

    /// Tradução pra mostrar embaixo do original, se houver.
    var translation: String? {
        if let translated, !translated.isEmpty { return translated }
        if let originalText, originalText != text { return text }
        return nil
    }
}

/// O que uma fonte devolve pra um lugar.
struct TipsBatch: Codable, Sendable {
    var tips: [Tip]
    var rating: Double?
    var ratingCount: Int?
    /// Foursquare: id do match, pra guardar no `Place`.
    var fsqId: String?
    var fetchedAt: Date = Date()
}

/// Lugar visto pelas fontes de dicas.
struct TipsQuery: Sendable, Hashable {
    var id: String
    var name: String
    var nameLocal: String?
    var city: String
    var region: Region
    var lat: Double
    var lng: Double
    var googlePlaceId: String?
    var fsqId: String?
    var sourceKind: SourceKind?
    var sourceCaption: String?
    var sourceAuthor: String?
    var sourceSavedAt: String?
    var sourceURL: String?
}

protocol TipsProviding: Sendable {
    var source: TipSource { get }
    var isConfigured: Bool { get }
    func tips(for query: TipsQuery) async throws -> TipsBatch
}

// MARK: - Cache (24 h de validade, apagado com 30 dias)

/// Guarda as respostas por lugar e fonte. Serve do cache por 24 h; sem rede, até 30 dias; depois apaga.
actor TipsCache {
    static let shared = TipsCache()
    static let fresh: TimeInterval = 24 * 3600
    static let maxAge: TimeInterval = 30 * 24 * 3600

    private let directory = URL.cachesDirectory.appending(path: "must-tips", directoryHint: .isDirectory)

    func batch(_ query: TipsQuery, _ source: TipSource, allowStale: Bool = false) -> TipsBatch? {
        let url = file(query, source)
        guard let data = try? Data(contentsOf: url),
              let batch = try? JSONDecoder.tips.decode(TipsBatch.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(batch.fetchedAt)
        if age > Self.maxAge { try? FileManager.default.removeItem(at: url); return nil }
        return age < Self.fresh || allowStale ? batch : nil
    }

    func store(_ batch: TipsBatch, _ query: TipsQuery, _ source: TipSource) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.tips.encode(batch) { try? data.write(to: file(query, source), options: .atomic) }
    }

    /// Apaga tudo com mais de 30 dias (chamado ao abrir as Dicas).
    func purge(now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > Self.maxAge { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func file(_ query: TipsQuery, _ source: TipSource) -> URL {
        let safe = "\(query.region.rawValue)-\(query.id)-\(source.rawValue)".map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return directory.appending(path: "\(safe).json")
    }
}

extension JSONDecoder {
    static let tips: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let tips: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - Legenda de origem (sem rede)

/// A legenda do Reel/TikTok/YouTube que trouxe o lugar vira o primeiro card, em verde.
struct SourceCaptionTips: TipsProviding {
    var source: TipSource { .caption }
    var isConfigured: Bool { true }

    func tips(for query: TipsQuery) async throws -> TipsBatch {
        guard let caption = query.sourceCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty else {
            return TipsBatch(tips: [])
        }
        let tip = Tip(id: "caption-\(query.id)", source: .caption, text: caption, author: query.sourceAuthor,
                      date: query.sourceSavedAt.flatMap { BoardDates(timeZone: query.region.timeZone).day(from: $0) },
                      url: query.sourceURL)
        return TipsBatch(tips: [tip])
    }
}

// MARK: - TripAdvisor (TODO)

/// TODO: TripAdvisor Content API (5k chamadas grátis/mês, precisa de aprovação). Desligado por flag até ter chave.
struct TripAdvisorTips: TipsProviding {
    static let enabled = false
    var source: TipSource { .tripadvisor }
    var isConfigured: Bool { Self.enabled }
    func tips(for query: TipsQuery) async throws -> TipsBatch { TipsBatch(tips: []) }
}

// MARK: - Fake (prévias, testes e prints)

struct FakeTipsProvider: TipsProviding {
    var source: TipSource
    var batch: TipsBatch
    var isConfigured: Bool { true }
    func tips(for query: TipsQuery) async throws -> TipsBatch { batch }

    /// Amostras no formato das fontes reais (Dicas.png).
    static func samples(for query: TipsQuery) -> [FakeTipsProvider] {
        let jp = query.region == .jp
        let google = TipsBatch(tips: jp ? [
            Tip(id: "g1", source: .google, text: "Counter seats only, 8 people. The chef speaks great English and explains each neta. Uni from Hokkaido was the best I had in Japan.",
                language: "en", author: "Marcus L.", rating: 5, relativeDate: "ago 2026"),
            Tip(id: "g2", source: .google, text: "Pontualidade total; chegue 10 min antes. Cartão só acima de ¥10k.",
                originalText: "予約時間厳守。10分前に着くのがベスト。カードは1万円以上から。", language: "ja", author: "Tabelog-er", rating: 4, relativeDate: "jun 2026"),
            Tip(id: "g3", source: .google, text: "Caro pra Naka-Meguro, mas vale. Otoro derrete.", language: "pt", author: "Ana P.", rating: 3, relativeDate: "mai 2026"),
        ] : [
            Tip(id: "g1", source: .google, text: "Vai cedo, antes das 10h, e almoça no Casa Cheia. Depois some lugar pra sentar.",
                language: "pt", author: "Rafael M.", rating: 5, relativeDate: "há 2 meses"),
            Tip(id: "g2", source: .google, text: "Lotado no sábado, estacionamento caro. Mas é o melhor lugar pra comprar queijo canastra.",
                language: "pt", author: "Juliana S.", rating: 4, relativeDate: "há 1 mês"),
        ], rating: jp ? 4.7 : 4.6, ratingCount: jp ? 1248 : 98_000)
        let fsq = TipsBatch(tips: [
            Tip(id: "f1", source: .foursquare, text: jp ? "Reserve pelo Omakase.in com 3 semanas." : "Doce de leite da Banca do Seu Zé!",
                language: "pt", author: "fsq", votes: 12, date: Date().addingTimeInterval(-86400 * 40)),
        ])
        let reddit = TipsBatch(tips: [
            Tip(id: "r1", source: .reddit, text: jp ? "Udatsu was the highlight — bring cash, they only take cards above 10k." : "Mercado Central é obrigatório, vai com fome.",
                language: "en", author: "u/tokyo_eats", votes: 214, date: Date().addingTimeInterval(-86400 * 120), subreddit: jp ? "JapanTravel" : "belohorizonte"),
        ])
        return [FakeTipsProvider(source: .google, batch: google), FakeTipsProvider(source: .foursquare, batch: fsq),
                FakeTipsProvider(source: .reddit, batch: reddit)]
    }
}
