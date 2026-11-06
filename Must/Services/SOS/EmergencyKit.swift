import CoreLocation
import Foundation

// SOS (prompt 25 · C): o kit de emergência por país (`data/emergency-kit.json`) e os hospitais por cidade
// (`data/hospitals.json`), no bundle — funciona sem internet. Cada número tem `source` (onde foi conferido); o que não
// deu pra confirmar em fonte oficial vem com `verificar: true` e a tela mostra "conferir".

/// Um número de emergência ou de apoio.
struct EmergencyNumber: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// Como aparece na tela ("192", "050-3816-2787", "#7119").
    var number: String
    /// O que vai no `tel:` (dígitos, `+`, `#`).
    var dial: String
    var title: String
    var detail: String
    var source: String
    var verificar: Bool = false
    /// O que vai no lugar do número no botão grande quando o número é longo ("24 h\ninglês").
    var badge: String? = nil

    enum CodingKeys: String, CodingKey { case id, number, dial, title, detail, source, verificar, badge }

    init(id: String, number: String, dial: String, title: String, detail: String, source: String, verificar: Bool = false,
         badge: String? = nil) {
        self.badge = badge
        self.id = id
        self.number = number
        self.dial = dial
        self.title = title
        self.detail = detail
        self.source = source
        self.verificar = verificar
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        dial = try c.decode(String.self, forKey: .dial)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        verificar = try c.decodeIfPresent(Bool.self, forKey: .verificar) ?? false
        badge = try c.decodeIfPresent(String.self, forKey: .badge)
    }

    /// `tel:` pro discador. O iOS não disca `#` nem `*` vindos de link (o discador ignora): aí `nil`, e a tela pede pra
    /// discar no teclado. O app nunca liga sozinho: o `tel:` só abre o discador com o número.
    var telURL: URL? { EmergencyKit.telURL(dial) }
}

/// Embaixada ou consulado do Brasil (só fora do Brasil).
struct Consulate: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// Cidades atendidas (`tokyo`, `kyoto`, `roma`): o SOS mostra o da cidade de hoje.
    var cities: [String]
    var name: String
    var phone: String
    var dial: String
    var emergencyPhone: String?
    var emergencyDial: String?
    var address: String
    var addressLocal: String?
    var detail: String
    var source: String
    var verificar: Bool?

    var needsCheck: Bool { verificar == true }
    var telURL: URL? { EmergencyKit.telURL(dial) }
    var emergencyTelURL: URL? { emergencyDial.flatMap(EmergencyKit.telURL) }
}

/// Frase com áudio pro SOS (letras latinas na tela; `speech` só pro sintetizador).
struct EmergencyPhrase: Codable, Hashable, Sendable, Identifiable {
    var latin: String
    var meaning: String
    var speech: String
    var id: String { latin }
}

/// O kit de um país.
struct CountryKit: Codable, Hashable, Sendable {
    var name: String
    /// Os três botões grandes, nesta ordem: ambulância, polícia, o terceiro (hotline em inglês / bombeiros).
    var primary: [EmergencyNumber]
    var more: [EmergencyNumber] = []
    var consulates: [Consulate] = []
    var phrases: [EmergencyPhrase] = []

    enum CodingKeys: String, CodingKey { case name, primary, more, consulates, phrases }

    init(name: String, primary: [EmergencyNumber], more: [EmergencyNumber] = [], consulates: [Consulate] = [], phrases: [EmergencyPhrase] = []) {
        self.name = name
        self.primary = primary
        self.more = more
        self.consulates = consulates
        self.phrases = phrases
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        primary = try c.decode([EmergencyNumber].self, forKey: .primary)
        more = try c.decodeIfPresent([EmergencyNumber].self, forKey: .more) ?? []
        consulates = try c.decodeIfPresent([Consulate].self, forKey: .consulates) ?? []
        phrases = try c.decodeIfPresent([EmergencyPhrase].self, forKey: .phrases) ?? []
    }

    func number(_ id: String) -> EmergencyNumber? { (primary + more).first { $0.id == id } }

    /// Consulado da cidade (Tóquio 1 e 2 contam como `tokyo`); sem cidade, o primeiro.
    func consulate(cityId: String?) -> Consulate? {
        let city = cityId.map(AreaCatalog.cityGroup(forCityId:))
        return consulates.first { c in city.map { c.cities.contains($0) } ?? false } ?? consulates.first
    }
}

/// O arquivo `emergency-kit.json`.
struct EmergencyKit: Codable, Hashable, Sendable {
    var version: Int
    var checked: String?
    var countries: [String: CountryKit]

    func kit(for region: Region) -> CountryKit? { countries[region.country] }

    /// Lido uma vez por processo (JSON pequeno, nunca no `body`).
    static let bundled: EmergencyKit = load(bundle: nil) ?? EmergencyKit(version: 0, checked: nil, countries: [:])

    static func load(bundle: Bundle?) -> EmergencyKit? {
        guard let data = BundleJSON.data("emergency-kit", bundle: bundle) else { return nil }
        do {
            return try JSONDecoder().decode(EmergencyKit.self, from: data)
        } catch {
            Log.app.error("emergency-kit.json inválido: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func telURL(_ dial: String) -> URL? {
        let clean = dial.filter { $0.isNumber || $0 == "+" || $0 == "#" || $0 == "*" }
        guard !clean.isEmpty, !clean.contains("#"), !clean.contains("*") else { return nil }
        return URL(string: "tel:\(clean)")
    }
}

// MARK: - Hospitais

struct Hospital: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var `public`: Bool?
    var er24h: Bool
    var english: Bool
    var address: String
    var addressLocal: String?
    var phone: String?
    var dial: String?
    var lat: Double
    var lng: Double
    var approx: Bool?
    var note: String?
    var source: String
    var verificar: Bool?

    var needsCheck: Bool { verificar == true }
    var telURL: URL? { dial.flatMap(EmergencyKit.telURL) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lng) }
}

/// O arquivo `hospitals.json` (lista curada por cidade).
struct HospitalCatalog: Codable, Hashable, Sendable {
    var version: Int
    var checked: String?
    var cities: [String: [Hospital]]

    static let bundled: HospitalCatalog = load(bundle: nil) ?? HospitalCatalog(version: 0, checked: nil, cities: [:])

    static func load(bundle: Bundle?) -> HospitalCatalog? {
        guard let data = BundleJSON.data("hospitals", bundle: bundle) else { return nil }
        do {
            return try JSONDecoder().decode(HospitalCatalog.self, from: data)
        } catch {
            Log.app.error("hospitals.json inválido: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Cidades de cada região (a lista curada não tem o "1"/"2" de Tóquio).
    static func cities(for region: Region) -> [String] {
        // `sos.hospitalCities` do país (`data/countries/<cc>.json`). País sem lista curada: nenhum hospital inventado.
        region.profile.sos?.hospitalCities ?? []
    }

    func hospitals(for region: Region) -> [Hospital] {
        Self.cities(for: region).flatMap { cities[$0] ?? [] }
    }

    /// Os da região do mais perto pro mais longe. Sem posição: os da cidade de hoje primeiro, na ordem curada.
    func nearest(region: Region, to location: CLLocation?, cityId: String?) -> [(hospital: Hospital, meters: CLLocationDistance?)] {
        let all = hospitals(for: region)
        if let location {
            return all.map { ($0, location.distance(from: $0.location)) }.sorted { ($0.1 ?? 0) < ($1.1 ?? 0) }
        }
        let city = cityId.map(AreaCatalog.cityGroup(forCityId:))
        let own = city.flatMap { cities[$0] } ?? []
        let rest = all.filter { h in !own.contains { $0.id == h.id } }
        return (own + rest).map { ($0, nil) }
    }
}

/// JSON do bundle do app (ou do de testes).
enum BundleJSON {
    private final class Anchor {}

    static func data(_ name: String, bundle: Bundle?) -> Data? {
        for candidate in [bundle ?? .main, Bundle(for: Anchor.self)] {
            if let url = candidate.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) {
                return data
            }
        }
        Log.app.error("\(name, privacy: .public).json não está no bundle")
        return nil
    }
}
