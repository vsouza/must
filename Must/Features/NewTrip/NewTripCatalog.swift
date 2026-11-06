import CoreLocation
import Foundation

/// Tabelas do fluxo Nova viagem (prompt 28 · F3): país → moeda/fuso/cor, cidades sugeridas e câmbio de reserva.
/// Tudo no aparelho: o passo 1 funciona sem rede (a busca de cidade do MapKit só acrescenta).
enum NewTripCatalog {
    struct Country: Equatable, Sendable, Identifiable {
        var code: String
        var name: String
        var currency: String
        var timeZoneId: String
        var id: String { code }

        /// "Lisboa, Porto, Sintra · euro · fuso Lisboa".
        var subtitle: String {
            let cities = NewTripCatalog.suggestedCities(for: code).prefix(4).map(\.name)
            var parts: [String] = []
            if !cities.isEmpty { parts.append(cities.joined(separator: ", ")) }
            parts.append(NewTripCatalog.currencyName(currency))
            parts.append("fuso \(NewTripCatalog.zoneLabel(timeZoneId))")
            return parts.joined(separator: " · ")
        }
    }

    struct SuggestedCity: Equatable, Sendable {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    static let locale = Locale(identifier: "pt_BR")

    // MARK: País

    /// Todos os países do sistema, nomes em pt-BR (ordenados). Moeda pelo `Locale`; fuso por tabela (o iOS não tem país → fuso).
    static let allCountries: [Country] = {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { country(code: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()

    static func country(code raw: String) -> Country? {
        let code = raw.uppercased()
        guard let name = locale.localizedString(forRegionCode: code), name != code else { return nil }
        let currency = Locale(identifier: "en_\(code)").currency?.identifier ?? ""
        return Country(code: code, name: name, currency: currency, timeZoneId: zoneByCountry[code] ?? TimeZone.current.identifier)
    }

    /// Países que casam com o texto (sem acento, sem caixa): nome começando com o termo vem primeiro.
    static func search(_ query: String, limit: Int = 4) -> [Country] {
        let q = fold(query)
        guard !q.isEmpty else { return [] }
        let starts = allCountries.filter { fold($0.name).hasPrefix(q) }
        let contains = allCountries.filter { !fold($0.name).hasPrefix(q) && fold($0.name).contains(q) }
        return Array((starts + contains).prefix(limit))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale).trimmingCharacters(in: .whitespaces)
    }

    static let zoneByCountry: [String: String] = [
        "PT": "Europe/Lisbon", "ES": "Europe/Madrid", "FR": "Europe/Paris", "IT": "Europe/Rome", "DE": "Europe/Berlin",
        "GB": "Europe/London", "IE": "Europe/Dublin", "NL": "Europe/Amsterdam", "BE": "Europe/Brussels", "CH": "Europe/Zurich",
        "AT": "Europe/Vienna", "GR": "Europe/Athens", "CZ": "Europe/Prague", "TR": "Europe/Istanbul", "JP": "Asia/Tokyo",
        "KR": "Asia/Seoul", "CN": "Asia/Shanghai", "TH": "Asia/Bangkok", "BR": "America/Sao_Paulo", "AR": "America/Argentina/Buenos_Aires",
        "CL": "America/Santiago", "UY": "America/Montevideo", "PE": "America/Lima", "CO": "America/Bogota", "MX": "America/Mexico_City",
        "US": "America/New_York", "CA": "America/Toronto", "MA": "Africa/Casablanca", "EG": "Africa/Cairo", "AU": "Australia/Sydney",
        "NZ": "Pacific/Auckland",
    ]

    /// "America/Sao_Paulo" → "Sao Paulo"; o nome da cidade do fuso, quando há uma boa tradução, vai em pt-BR.
    static func zoneLabel(_ id: String) -> String {
        let zones = ["Europe/Lisbon": "Lisboa", "Europe/Madrid": "Madri", "Europe/Paris": "Paris", "Europe/Rome": "Roma",
                     "Europe/Berlin": "Berlim", "Europe/London": "Londres", "Asia/Tokyo": "Tóquio", "America/Sao_Paulo": "Brasília",
                     "America/New_York": "Nova York", "Europe/Amsterdam": "Amsterdã"]
        if let known = zones[id] { return known }
        return (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Moeda e câmbio

    static func currencyName(_ code: String) -> String {
        switch code {
        case "EUR": "euro"
        case "BRL": "real"
        case "JPY": "iene"
        case "USD": "dólar"
        case "GBP": "libra"
        case "ARS": "peso argentino"
        case "CLP": "peso chileno"
        case "CHF": "franco suíço"
        case "": "moeda local"
        default: code
        }
    }

    static func currencySymbol(_ code: String) -> String {
        switch code {
        case "EUR": "€"
        case "BRL": "R$"
        case "JPY": "¥"
        case "USD": "US$"
        case "GBP": "£"
        default: code
        }
    }

    /// R$ por 1 unidade da moeda: o último câmbio guardado (digitado ou do dia) > a tabela de reserva. Sem API nova.
    static func fallbackRate(_ currency: String) -> Double? {
        switch currency {
        case "BRL": 1
        case "EUR": ShoppingFX.brlPerEUR
        case "JPY": ShoppingFX.brlPerYen
        case "USD": ShoppingFX.brlPerUSD
        case "GBP": 7.2
        case "ARS": 0.005
        case "CHF": 6.3
        default: nil
        }
    }

    private static func rateKey(_ currency: String) -> String { "newtrip.fx.\(currency)" }

    static func cachedRate(_ currency: String, defaults: UserDefaults = .standard) -> Double? {
        let stored = defaults.double(forKey: rateKey(currency))
        return stored > 0 ? stored : fallbackRate(currency)
    }

    static func storeRate(_ rate: Double, for currency: String, defaults: UserDefaults = .standard) {
        guard rate > 0 else { return }
        defaults.set(rate, forKey: rateKey(currency))
    }

    // MARK: Cor da capa

    /// As 6 amostras do passo 1 (verde Portugal, vermelho, azzurro, roxo, tinta, laranja).
    static let swatches: [UInt32] = [0x0A5C48, 0xB3261E, 0x1F5FB4, 0x6B3FA0, 0x121212, 0xFF4A1C]

    /// Tabela por país: BR/JP/IT iguais ao `TripTheme`; PT e outros caem numa amostra que não repete as três.
    static func coverHex(for code: String) -> String {
        switch code.uppercased() {
        case "BR": return "#007A33"
        case "JP": return "#D7000F"
        case "IT": return "#1F5FB4"
        case "PT": return "#0A5C48"
        default:
            let pool = [0x0A5C48, 0xB3261E, 0x6B3FA0, 0xFF4A1C] as [UInt32]
            let sum = code.uppercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return hex(pool[sum % pool.count])
        }
    }

    static func hex(_ rgb: UInt32) -> String { String(format: "#%06X", rgb) }

    // MARK: Cidades sugeridas (offline)

    static func suggestedCities(for code: String) -> [SuggestedCity] {
        func c(_ n: String, _ la: Double, _ lo: Double) -> SuggestedCity { SuggestedCity(name: n, latitude: la, longitude: lo) }
        switch code.uppercased() {
        case "PT": return [c("Lisboa", 38.7223, -9.1393), c("Porto", 41.1579, -8.6291), c("Sintra", 38.8029, -9.3817),
                           c("Coimbra", 40.2033, -8.4103), c("Faro", 37.0194, -7.9304)]
        case "ES": return [c("Madri", 40.4168, -3.7038), c("Barcelona", 41.3874, 2.1686), c("Sevilha", 37.3891, -5.9845),
                           c("Valência", 39.4699, -0.3763)]
        case "FR": return [c("Paris", 48.8566, 2.3522), c("Lyon", 45.764, 4.8357), c("Nice", 43.7102, 7.262)]
        case "IT": return [c("Roma", 41.9028, 12.4964), c("Florença", 43.7696, 11.2558), c("Veneza", 45.4408, 12.3155),
                           c("Milão", 45.4642, 9.19)]
        case "GB": return [c("Londres", 51.5072, -0.1276), c("Edimburgo", 55.9533, -3.1883)]
        case "DE": return [c("Berlim", 52.52, 13.405), c("Munique", 48.1351, 11.582)]
        case "AR": return [c("Buenos Aires", -34.6037, -58.3816), c("Mendoza", -32.8908, -68.8272)]
        case "US": return [c("Nova York", 40.7128, -74.006), c("Los Angeles", 34.0522, -118.2437), c("Miami", 25.7617, -80.1918)]
        case "JP": return [c("Tóquio", 35.6762, 139.6503), c("Kyoto", 35.0116, 135.7681), c("Osaka", 34.6937, 135.5023)]
        case "BR": return [c("São Paulo", -23.5505, -46.6333), c("Rio de Janeiro", -22.9068, -43.1729), c("Belo Horizonte", -19.9167, -43.9345)]
        default: return []
        }
    }
}
