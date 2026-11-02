import Foundation

/// Aeroportos que a viagem usa (prompt 15 · C). Sem rede: fuso e país saem daqui.
/// Fora da tabela, o trecho guarda o código e usa o fuso da região (aviso na tela de conferência).
struct Airport: Sendable, Hashable {
    let iata: String
    let city: String
    /// ISO 3166-1 alpha-2.
    let country: String
    /// Fuso IANA do aeroporto (a hora de partida e chegada é local dele).
    let timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

enum Airports {
    static let table: [Airport] = [
        // Brasil
        Airport(iata: "CNF", city: "Belo Horizonte", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "GRU", city: "São Paulo", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "CGH", city: "São Paulo", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "GIG", city: "Rio de Janeiro", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "BSB", city: "Brasília", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "CWB", city: "Curitiba", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "POA", city: "Porto Alegre", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "FLN", city: "Florianópolis", country: "BR", timeZoneID: "America/Sao_Paulo"),
        Airport(iata: "SSA", city: "Salvador", country: "BR", timeZoneID: "America/Bahia"),
        Airport(iata: "REC", city: "Recife", country: "BR", timeZoneID: "America/Recife"),
        Airport(iata: "FOR", city: "Fortaleza", country: "BR", timeZoneID: "America/Fortaleza"),
        Airport(iata: "MAO", city: "Manaus", country: "BR", timeZoneID: "America/Manaus"),
        // Japão
        Airport(iata: "HND", city: "Tóquio", country: "JP", timeZoneID: "Asia/Tokyo"),
        Airport(iata: "NRT", city: "Tóquio", country: "JP", timeZoneID: "Asia/Tokyo"),
        Airport(iata: "KIX", city: "Osaka", country: "JP", timeZoneID: "Asia/Tokyo"),
        Airport(iata: "ITM", city: "Osaka", country: "JP", timeZoneID: "Asia/Tokyo"),
        Airport(iata: "NGO", city: "Nagoya", country: "JP", timeZoneID: "Asia/Tokyo"),
        Airport(iata: "CTS", city: "Sapporo", country: "JP", timeZoneID: "Asia/Tokyo"),
        Airport(iata: "FUK", city: "Fukuoka", country: "JP", timeZoneID: "Asia/Tokyo"),
        // Escalas e destinos comuns
        Airport(iata: "DOH", city: "Doha", country: "QA", timeZoneID: "Asia/Qatar"),
        Airport(iata: "DXB", city: "Dubai", country: "AE", timeZoneID: "Asia/Dubai"),
        Airport(iata: "IST", city: "Istambul", country: "TR", timeZoneID: "Europe/Istanbul"),
        Airport(iata: "ICN", city: "Seul", country: "KR", timeZoneID: "Asia/Seoul"),
        Airport(iata: "PVG", city: "Xangai", country: "CN", timeZoneID: "Asia/Shanghai"),
        Airport(iata: "SIN", city: "Singapura", country: "SG", timeZoneID: "Asia/Singapore"),
        Airport(iata: "BKK", city: "Bangkok", country: "TH", timeZoneID: "Asia/Bangkok"),
        Airport(iata: "JFK", city: "Nova York", country: "US", timeZoneID: "America/New_York"),
        Airport(iata: "EWR", city: "Nova York", country: "US", timeZoneID: "America/New_York"),
        Airport(iata: "MIA", city: "Miami", country: "US", timeZoneID: "America/New_York"),
        Airport(iata: "LAX", city: "Los Angeles", country: "US", timeZoneID: "America/Los_Angeles"),
        Airport(iata: "MEX", city: "Cidade do México", country: "MX", timeZoneID: "America/Mexico_City"),
        Airport(iata: "BOG", city: "Bogotá", country: "CO", timeZoneID: "America/Bogota"),
        Airport(iata: "LIM", city: "Lima", country: "PE", timeZoneID: "America/Lima"),
        Airport(iata: "SCL", city: "Santiago", country: "CL", timeZoneID: "America/Santiago"),
        Airport(iata: "EZE", city: "Buenos Aires", country: "AR", timeZoneID: "America/Argentina/Buenos_Aires"),
        Airport(iata: "LIS", city: "Lisboa", country: "PT", timeZoneID: "Europe/Lisbon"),
        Airport(iata: "MAD", city: "Madri", country: "ES", timeZoneID: "Europe/Madrid"),
        Airport(iata: "CDG", city: "Paris", country: "FR", timeZoneID: "Europe/Paris"),
        Airport(iata: "FRA", city: "Frankfurt", country: "DE", timeZoneID: "Europe/Berlin"),
        Airport(iata: "FCO", city: "Roma", country: "IT", timeZoneID: "Europe/Rome"),
        Airport(iata: "LHR", city: "Londres", country: "GB", timeZoneID: "Europe/London"),
        Airport(iata: "SYD", city: "Sydney", country: "AU", timeZoneID: "Australia/Sydney"),
    ]

    private static let byCode: [String: Airport] = Dictionary(table.map { ($0.iata, $0) }, uniquingKeysWith: { a, _ in a })

    static func airport(_ iata: String) -> Airport? { byCode[iata.uppercased()] }

    /// Cidade (com ou sem acento, em qualquer caixa) → aeroporto principal. Pra títulos do tipo "BH → São Paulo".
    static func iata(forCity name: String) -> String? {
        let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespaces)
        return cityCodes[key]
    }

    private static let cityCodes: [String: String] = [
        "bh": "CNF", "belo horizonte": "CNF", "confins": "CNF",
        "sao paulo": "GRU", "guarulhos": "GRU", "rio de janeiro": "GIG", "rio": "GIG", "brasilia": "BSB", "curitiba": "CWB",
        "porto alegre": "POA", "salvador": "SSA", "recife": "REC", "fortaleza": "FOR", "manaus": "MAO",
        "toquio": "HND", "tokyo": "HND", "narita": "NRT", "kyoto": "KIX", "osaka": "KIX", "nagoya": "NGO",
        "sapporo": "CTS", "fukuoka": "FUK", "doha": "DOH", "dubai": "DXB", "istambul": "IST", "seul": "ICN",
        "nova york": "JFK", "new york": "JFK", "miami": "MIA", "los angeles": "LAX", "lisboa": "LIS", "lisbon": "LIS",
        "paris": "CDG", "londres": "LHR", "london": "LHR", "madri": "MAD", "roma": "FCO", "santiago": "SCL",
        "lima": "LIM", "bogota": "BOG", "buenos aires": "EZE", "cidade do mexico": "MEX",
    ]

    /// Aeroportos do Japão (a Carteira e o checklist "Japão" se ligam a eles).
    static func isJapan(_ iata: String) -> Bool { airport(iata)?.country == "JP" }

    static func isBrazil(_ iata: String) -> Bool { airport(iata)?.country == "BR" }
}
