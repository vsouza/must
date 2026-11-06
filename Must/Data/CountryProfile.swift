import CoreLocation
import Foundation
import OSLog

/// O que muda de um país pro outro (prompt 28 §3.4), como **dado**: `data/countries/<cc>.json` no bundle
/// (pasta `countries/`). Moeda, fuso padrão, cor da capa, câmbio de referência, janelas de refeição, regras locais do
/// solver, textos curtos do dia, SOS, Bolso e as tabelas curadas (bairros, linhas, hospitais) das viagens de fábrica.
///
/// País sem arquivo = `generic(...)`: bandeira/cor que a viagem escolheu, moeda e fuso dela, nada curado. Nunca erro.
/// Todos os campos além de `code/name/currency/timeZone` são opcionais no JSON; quem lê usa os acessores com padrão.
struct CountryProfile: Codable, Hashable, Sendable {
    /// ISO 3166-1 alfa-2 ("JP").
    var code: String
    /// Nome em pt-BR ("Japão").
    var name: String
    /// Artigo com preposição: "no" (no Japão, no Brasil), "na" (na Itália), "em" (em Portugal).
    var preposition: String?
    /// ISO 4217 ("JPY").
    var currency: String
    var currencySymbol: String?
    /// Fuso padrão do país (cada cidade pode ter o seu).
    var timeZone: String
    /// Idioma local pra mostrar endereço a um taxista e ler vídeo ("ja_JP"). `nil` = pt_BR.
    var localLocale: String?
    /// Cor da capa (`#RRGGBB`). `nil` = sem cor do lugar (papel + tinta).
    var colorHex: String?
    /// Orçamento diário padrão e as três sugestões do Montar, na moeda do país.
    var defaultBudget: Double?
    var budgetPresets: [Double]?
    var fx: FX?
    /// Caixas de lat/lng do país (região automática pelo GPS).
    var bounds: [Box]?
    /// Centro padrão quando a viagem não tem cidade.
    var center: Area.Coordinate?
    /// Janelas do dia (minutos desde a meia-noite). `nil` = as do solver.
    var meals: Meals?
    /// Regras locais ligadas no solver e no dia.
    var rules: [Rule]?
    var transit: Transit?
    var money: Money?
    var day: DayText?
    var sos: SOS?
    /// Pacote de regras da volta (`Must/Data/rules/<id>.json`).
    var shoppingPack: String?
    /// Tabelas de bairros curadas (`Must/Data/areas/<nome>.json`). Só as viagens de fábrica usam.
    var curatedAreas: [String]?
    /// Bolso e Dicas do país (cards, frases, dicas). `nil` = Bolso só com o câmbio.
    var pocket: PocketCountry?

    // MARK: Tipos

    struct FX: Codable, Hashable, Sendable {
        /// R$ por 1 unidade quando o usuário ainda não pôs o câmbio (Ajustes › Moeda). Real = 1.
        var defaultBRLPerUnit: Double
        /// Unidade mostrada em Ajustes: ¥100, €1.
        var unit: Double?
    }

    struct Box: Codable, Hashable, Sendable {
        var minLat: Double, maxLat: Double, minLng: Double, maxLng: Double

        func contains(_ c: CLLocationCoordinate2D) -> Bool {
            (minLat...maxLat).contains(c.latitude) && (minLng...maxLng).contains(c.longitude)
        }
    }

    /// `[início, fim)` em minutos; manhã cedo começa em `morningEarly`.
    struct Meals: Codable, Hashable, Sendable {
        var morning: [Int]
        var morningEarly: Int
        var lunch: [Int]
        var afternoon: [Int]
        var dinner: [Int]
        var night: [Int]
    }

    /// Regras locais (prompt 24 §2: Roma). Os detalhes de texto ficam em `ItalyRules`; o país só liga.
    enum Rule: String, Codable, Hashable, Sendable {
        /// Lojas pequenas fecham 13–16; igrejas 12:30–15:30.
        case middayClosures
        /// Museus estatais fecham segunda; a Borghese só com reserva.
        case stateMuseumsMonday
        /// Reserva com "turno de 2 h" termina na hora do turno.
        case reservationShift
        /// Domingo: Via Appia sem carro vira âncora de manhã.
        case appiaSunday
        /// Metrô com um horário só pra cidade toda (23:30; sex/sáb 01:30).
        case cityLastMetro
        /// Micro-parada de gelato à tarde.
        case treatMicroStop
        /// Preço de restaurante é por pessoa; fila sem reserva.
        case perPersonPrice
        /// Passaporte no dia de ingresso ou tax-free (fora de casa).
        case passportReminder
    }

    struct Transit: Codable, Hashable, Sendable {
        /// `<nome>.geojson` das linhas no bundle.
        var lines: String?
        /// Google Routes tem TRANSIT aqui (no Japão a API volta vazio).
        var googleTransit: Bool?
        /// Deslocamento sem tabela: modo e rótulo ("trem ou metrô").
        var legMode: String?
        var legLabel: String?
        /// Rótulo curto do transporte no Lugar ("metrô", "bus/metrô").
        var placeLabel: String?
        /// Tarifa de táxi estimada ("jpy" | "brl").
        var taxiFare: String?
        /// Modelos extras do Open-Meteo ("jma_seamless,best_match").
        var weatherModels: String?
        /// Nome da fonte do tempo em Ajustes ("Open-Meteo + JMA").
        var weatherLabel: String?
        /// Fonte local nos rótulos do mapa (Hiragino no Japão).
        var localMapFont: Bool?
        /// Cartão de transporte de valor (Suica): lembrete de recarga, Wallet nos Atalhos, Carteira de partida.
        var storedValueCard: String?
        /// Último metrô da tabela da cidade (BH: a linha 1 inteira).
        var lastTrainFromLine: Bool?
        /// Sem estação perto (Atalhos).
        var noStationText: String?
        /// "Linha 1" (fim do nome) ou "Metro A" (começo) quando o nome tem " · ".
        var shortLineFromTail: Bool?
        /// Largura do mapa do bairro em metros.
        var areaMapWidth: Double?
    }

    struct Money: Codable, Hashable, Sendable {
        /// Dinheiro vivo é comum (gasto começa em dinheiro, chip "caixa", câmbio no gasto).
        var cashCommon: Bool?
        /// "cartão e cash" (ficha do Lugar).
        var paymentLabel: String?
        /// Métodos do gasto (`PaymentMethod.rawValue`). `nil` = dinheiro e cartão.
        var paymentMethods: [String]?
        /// Atalho do teclado de valor ("000" no iene, "," no resto).
        var amountQuickKey: String?
        /// Chip/linha "caixa" no Agora, no Ir e no Lugar.
        var atmChip: String?
        var atmLine: String?
        var atmFilter: String?
        /// Saldo baixo padrão do cartão de transporte (Carteira).
        var lowBalance: String?
        /// Mostra o ≈ R$ nos gastos e no Wallet.
        var showsBRL: Bool?
    }

    struct DayText: Codable, Hashable, Sendable {
        /// "café, konbini, descanso" (Montar).
        var microStops: String?
        /// Chips do Agora: banheiro na estação, konbini no caminho.
        var konbiniChips: Bool?
        /// Pergunta-exemplo do Assistente e da busca do mapa.
        var assistantQuestion: String?
        var mapSearchExample: String?
        /// "entrega no Airbnb não é opção" (Quero…).
        var deliveryNote: String?
        /// Domínio das lojas pro Quero… ("jp", "it", "com.br").
        var storeTLD: String?
        /// Subreddits das Dicas.
        var subreddits: [String]?
        /// Dica de lámen (fila curta no balcão).
        var ramenTips: Bool?
        /// Rótulo do Bolso ("Utilidades" no Japão).
        var pocketTitle: String?
    }

    struct SOS: Codable, Hashable, Sendable {
        /// "119 · 110 · seguro · hospital" (Atalhos).
        var numbersLabel: String?
        /// Cidades da lista curada de hospitais (`hospitals.json`).
        var hospitalCities: [String]?
        /// "Onde estou · em japonês".
        var whereAmITitle: String?
        /// Endereço na ordem japonesa (do maior pro menor).
        var japaneseAddressOrder: Bool?
        /// Numeral do "Onde estou".
        var whereAmIFontSize: Double?
    }

    // MARK: Acessores com padrão

    var symbol: String { currencySymbol ?? Self.symbol(for: currency) }
    var tz: TimeZone { TimeZone(identifier: timeZone) ?? .gmt }
    var local: Locale { Locale(identifier: localLocale ?? "pt_BR") }
    var budget: Double { defaultBudget ?? 100 }
    var presets: [Double] { budgetPresets ?? [budget / 2, budget, budget * 2].map { ($0 / 10).rounded() * 10 } }
    /// Sem referência no perfil: 1 (o usuário digita o câmbio em Ajustes › Moeda).
    var defaultFXRate: Double { fx?.defaultBRLPerUnit ?? 1 }
    var fxUnit: Double { fx?.unit ?? 1 }
    func has(_ rule: Rule) -> Bool { rules?.contains(rule) ?? false }
    /// "no Japão", "na Itália", "em Portugal".
    var inName: String { "\(preposition ?? "em") \(name)" }
    /// Cor da capa como `0xRRGGBB`, `nil` sem cor.
    var coverRGB: UInt32? { colorHex.flatMap(Self.rgb) }
    var isCurated: Bool { CountryProfile.bundledCodes.contains(code) }

    /// "#D7000F" → 0xD7000F.
    static func rgb(_ hex: String) -> UInt32? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6 else { return nil }
        return UInt32(h, radix: 16)
    }

    /// Símbolo da moeda em pt-BR (US$, €, ¥…), sem rede.
    static func symbol(for currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "pt_BR")
        f.currencyCode = currency
        return f.currencySymbol ?? currency
    }

    // MARK: Catálogo

    /// Perfil do país (ISO). Sem arquivo: o genérico (com a moeda/fuso que quem chama souber).
    static func forCountry(_ code: String, currency: String? = nil, timeZone: String? = nil) -> CountryProfile {
        let key = code.uppercased()
        if let bundled = bundled[key] { return bundled }
        return generic(code: key, currency: currency, timeZone: timeZone)
    }

    /// País sem perfil: bandeira, cor escolhida, moeda e fuso; nada de Bolso curado nem regras locais.
    static func generic(code: String, currency: String? = nil, timeZone: String? = nil, name: String? = nil) -> CountryProfile {
        let code = code.uppercased()
        let ptName = name ?? Locale(identifier: "pt_BR").localizedString(forRegionCode: code) ?? code
        let currency = currency ?? Locale(identifier: "en_\(code)").currency?.identifier ?? "USD"
        return CountryProfile(code: code, name: ptName, preposition: nil, currency: currency, currencySymbol: nil,
                              timeZone: timeZone ?? TimeZone.current.identifier, localLocale: nil, colorHex: nil,
                              defaultBudget: nil, budgetPresets: nil, fx: nil, bounds: nil, center: nil, meals: nil,
                              rules: nil, transit: nil, money: nil, day: nil, sos: nil, shoppingPack: nil,
                              curatedAreas: nil, pocket: nil)
    }

    /// Países com arquivo no bundle.
    static let bundledCodes: [String] = ["BR", "JP", "IT", "PT"]

    /// Carregados uma vez por processo (JSON pequeno, nunca no `body`).
    static let bundled: [String: CountryProfile] = {
        var out: [String: CountryProfile] = [:]
        for code in bundledCodes {
            if let profile = load(code, bundle: nil) { out[code] = profile }
        }
        return out
    }()

    private final class BundleAnchor {}

    static func load(_ code: String, bundle: Bundle?) -> CountryProfile? {
        for candidate in [bundle ?? .main, Bundle(for: BundleAnchor.self)] {
            guard let url = candidate.url(forResource: code, withExtension: "json", subdirectory: "countries")
                    ?? candidate.url(forResource: code, withExtension: "json") else { continue }
            do {
                return try JSONDecoder().decode(CountryProfile.self, from: Data(contentsOf: url))
            } catch {
                Log.app.error("countries/\(code, privacy: .public).json inválido: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        Log.app.error("countries/\(code, privacy: .public).json não está no bundle")
        return nil
    }

    /// País pelo GPS (caixas dos perfis, na ordem do catálogo). Fora de todos: `nil`.
    static func detect(_ c: CLLocationCoordinate2D) -> String? {
        // A ordem importa onde as caixas se encostam (Itália antes do resto da Europa).
        for code in ["JP", "IT", "PT", "BR"] {
            if bundled[code]?.bounds?.contains(where: { $0.contains(c) }) == true { return code }
        }
        return nil
    }
}
