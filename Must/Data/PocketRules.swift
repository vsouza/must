import Foundation

// Bolso e Dicas por país (prompt 23 §2 · 07/08, prompt 24 §2). Conteúdo curado, 100 % offline: nada aqui chama rede.
// Os valores que mudam no dia (câmbio guardado, saldo anotado da Suica, último trem da tabela) entram pelo
// `PocketContext`; o resto é texto fixo por país em `PocketRulesJP/BR/IT.swift`.

/// Tom de um card (v8: três cores — tinta, laranja, branco sobre papel).
enum PocketTone: String, Codable, Sendable, Hashable {
    case ink, orange, white
}

/// O que cada card do Bolso é (o toque abre o conversor, as frases ou o detalhe).
enum PocketCardKind: String, Codable, Sendable, Hashable, CaseIterable {
    case exchange, transitCard, ticket, phrases, lastTrain, taxFree, nearby, etiquette, lockers
    case tipping, water, churches, caution, riposo, booking
}

/// Um card da grade 2×N do Bolso.
struct PocketCard: Identifiable, Codable, Hashable, Sendable {
    var kind: PocketCardKind
    /// Micro-rótulo ("TAX-FREE"). Já em caixa alta na tela.
    var label: String
    /// O valor grande ("¥ 5.000", "Trem em\nsilêncio").
    var value: String
    /// Uma linha embaixo ("por loja, por dia · passaporte").
    var detail: String
    var tone: PocketTone = .white
    /// Linhas do detalhe (toque no card).
    var more: [String] = []

    var id: String { kind.rawValue }
}

/// Frase com áudio (sintetizador do aparelho, offline). A tela mostra só letras latinas e o sentido em pt-BR;
/// `speech` (na escrita local) vai só pro `AVSpeechSynthesizer`, nunca aparece.
struct PocketPhrase: Identifiable, Codable, Hashable, Sendable {
    var latin: String
    var meaning: String
    var speech: String

    var id: String { latin }
}

/// Momento do dia de uma dica do país (Dicas por momento).
enum TipMoment: String, Codable, Sendable, Hashable, CaseIterable {
    case morning, beforeQueue, afternoon, night, back, anytime

    /// Rótulo à direita do card ("NOITE", "VOLTA").
    var label: String {
        switch self {
        case .morning: "manhã"
        case .beforeQueue: "fila"
        case .afternoon: "tarde"
        case .night: "noite"
        case .back: "volta"
        case .anytime: "sabia que"
        }
    }
}

/// Dica fixa do país ("Não tem lixeira na rua…"). `etiquette` = entra no filtro Etiqueta.
struct CountryTip: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var moment: TipMoment
    var title: String
    var detail: String
    var etiquette: Bool = false
}

/// O que muda no dia e o Bolso mostra.
struct PocketContext: Sendable, Hashable {
    var now: Date
    /// R$ por 1 unidade da moeda da região (o câmbio guardado em Ajustes). `nil` = o padrão do país.
    var brlPerUnit: Double?
    /// Saldo anotado do cartão de transporte (Carteira › Suica).
    var transitBalance: Double?
    /// Último trem da tabela (`LastTrains`), quando há.
    var lastTrain: LastTrain?

    init(now: Date, brlPerUnit: Double? = nil, transitBalance: Double? = nil, lastTrain: LastTrain? = nil) {
        self.now = now
        self.brlPerUnit = brlPerUnit
        self.transitBalance = transitBalance
        self.lastTrain = lastTrain
    }
}

/// Conteúdo fixo de um país.
struct PocketCountry: Codable, Hashable, Sendable {
    /// "Japão" (filtro e rótulo dos cards "Sabia que").
    var name: String
    /// Idioma do sintetizador ("ja-JP").
    var speechLanguage: String
    /// R$ por 1 unidade quando não há câmbio guardado.
    var fallbackBRLPerUnit: Double
    /// Quanto o câmbio mostra de cara (¥ 100, € 1, R$ 1 → US$).
    var exchangeUnit: Double
    var cards: [PocketCard]
    var phrases: [PocketPhrase]
    var tips: [CountryTip]
}

enum PocketRules {
    static func country(_ region: Region) -> PocketCountry {
        switch region {
        case .jp: jp
        case .bh: br
        case .it: it
        }
    }

    /// Cards do Bolso, na ordem da grade (câmbio e o cartão/bilhete de transporte primeiro).
    static func cards(for region: Region, context: PocketContext) -> [PocketCard] {
        let country = country(region)
        return country.cards.map { card in
            var card = card
            switch card.kind {
            case .exchange:
                let rate = rate(region, stored: context.brlPerUnit)
                card.value = exchangeValue(region, rate: rate, unit: country.exchangeUnit)
            case .transitCard:
                if let balance = context.transitBalance {
                    card.value = region.money(balance)
                } else if region == .jp {
                    card.value = "anotar"
                }
            case .lastTrain:
                if region == .it {
                    card.value = lastMetro(at: context.now, region: region)
                } else if let last = context.lastTrain {
                    card.value = last.time
                    if region == .jp { card.detail = shortTrainLabel(last.label) }
                }
            default: break
            }
            return card
        }
    }

    static func phrases(for region: Region) -> [PocketPhrase] { country(region).phrases }
    static func tips(for region: Region) -> [CountryTip] { country(region).tips }

    /// Câmbio que vale: o guardado se faz sentido pro país, senão o padrão (nenhuma API nova).
    /// O Japão guarda R$ por ¥1 (~0,036); a Itália R$ por €1 (~6,4); BH não converte (usa R$ por US$ 1).
    static func rate(_ region: Region, stored: Double?) -> Double {
        let fallback = country(region).fallbackBRLPerUnit
        guard let stored, stored > 0 else { return fallback }
        switch region {
        case .jp: return stored < 1 ? stored : fallback
        case .it: return stored > 1.5 ? stored : fallback
        case .bh: return stored > 1.5 ? stored : fallback
        }
    }

    /// "¥100\nR$ 3,60" — duas linhas, a unidade e o valor em reais. BH: "US$ 1\nR$ 5,50".
    static func exchangeValue(_ region: Region, rate: Double, unit: Double) -> String {
        let brl = (unit * rate).formatted(.money("BRL"))
        switch region {
        case .jp: return "¥\(Int(unit))\n\(brl)"
        case .it: return "€ \(Int(unit))\n\(brl)"
        case .bh: return "US$ \(Int(unit))\n\(brl)"
        }
    }

    /// Converte `value` na moeda da região pra reais (e de volta com `reverse`).
    static func convert(_ value: Double, region: Region, rate: Double, toBRL: Bool = true) -> Double {
        guard rate > 0 else { return 0 }
        return toBRL ? value * rate : value / rate
    }

    /// Roma: metrô até 23:30; sexta e sábado até 01:30 (a madrugada de sábado e domingo conta).
    static func lastMetro(at date: Date, region: Region) -> String {
        let cal = region.calendar
        let hour = cal.component(.hour, from: date)
        // Depois da meia-noite ainda é a noite de ontem.
        let night = hour < 5 ? cal.date(byAdding: .day, value: -1, to: date) ?? date : date
        let weekday = cal.component(.weekday, from: night) // 1 = domingo … 6 = sexta, 7 = sábado
        return weekday == 6 || weekday == 7 ? "01:30" : "23:30"
    }

    /// "Último Yamanote → Hibiya Shinjuku → Naka-Meguro" → "Yamanote → Hibiya · Shinjuku → Naka-Meguro".
    static func shortTrainLabel(_ label: String) -> String {
        var text = label
        if text.hasPrefix("Último ") { text.removeFirst("Último ".count) }
        // A estação de partida é a penúltima palavra antes da última seta.
        guard let arrow = text.range(of: " → ", options: .backwards) else { return text }
        let head = text[..<arrow.lowerBound]
        guard let space = head.lastIndex(of: " ") else { return text }
        return "\(head[..<space]) · \(head[head.index(after: space)...]) → \(text[arrow.upperBound...])"
    }

    /// Momento do dia de uma hora (Dicas por momento).
    static func moment(at date: Date, region: Region) -> TipMoment {
        let hour = region.calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .morning
        case 11..<18: return .afternoon
        case 18..<23: return .night
        default: return .back
        }
    }

    /// Lugar só aceita dinheiro? (notas do board: "só cash", "levar dinheiro", "cash only").
    static func cashOnly(notes: String) -> Bool {
        let n = notes.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
        return ["so cash", "cash only", "levar dinheiro", "so dinheiro", "nao aceita cartao", "dinheiro vivo"].contains { n.contains($0) }
    }
}

// MARK: - JSON (`data/countries/<cc>.json`, campo `pocket`)

extension PocketCard {
    private enum CodingKeys: String, CodingKey { case kind, label, value, detail, tone, more }

    /// `tone` e `more` são opcionais no JSON (padrão: branco, sem detalhe).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(PocketCardKind.self, forKey: .kind), label: try c.decode(String.self, forKey: .label),
                  value: try c.decodeIfPresent(String.self, forKey: .value) ?? "",
                  detail: try c.decodeIfPresent(String.self, forKey: .detail) ?? "",
                  tone: try c.decodeIfPresent(PocketTone.self, forKey: .tone) ?? .white,
                  more: try c.decodeIfPresent([String].self, forKey: .more) ?? [])
    }
}

extension CountryTip {
    private enum CodingKeys: String, CodingKey { case id, moment, title, detail, etiquette }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), moment: try c.decode(TipMoment.self, forKey: .moment),
                  title: try c.decode(String.self, forKey: .title), detail: try c.decode(String.self, forKey: .detail),
                  etiquette: try c.decodeIfPresent(Bool.self, forKey: .etiquette) ?? false)
    }
}
