import CoreLocation
import Foundation

/// A viagem aberta (prompt 28): o que a UI lê de uma viagem — a `Trip` do registro e o `CountryProfile` do país.
/// Era o `enum Region` (bh | jp | it); virou valor pra que viagens criadas no app (`must-<slug>-<4 letras>.store`)
/// funcionem igual. `.bh`, `.jp` e `.it` continuam existindo como as viagens de fábrica, com os mesmos ids, arquivos e
/// chaves de UserDefaults (`onboarded.<id>`, `region`). Igualdade e hash pelo id; Codable como o id (`"jp"`).
struct Region: RawRepresentable, Hashable, Codable, Sendable, Identifiable, CaseIterable {
    let trip: Trip
    /// O que muda por país (`data/countries/<cc>.json`); genérico quando o país não tem arquivo.
    let profile: CountryProfile
    let timeZone: TimeZone

    init(trip: Trip) {
        self.trip = trip
        profile = CountryProfile.forCountry(trip.countryCode, currency: trip.currency, timeZone: trip.timeZone)
        timeZone = trip.tz
    }

    /// Id de viagem: as de fábrica e as do registro já lido neste processo (`KnownTrips`). Desconhecido: `nil`.
    init?(rawValue: String) {
        guard let trip = KnownTrips.shared.trip(rawValue) ?? BuiltInTrip.trip(rawValue) else { return nil }
        self.init(trip: trip)
    }

    /// Belo Horizonte (casa), `must-bh.store`, seed `seed-bh.json`.
    static let bh = Region(trip: BuiltInTrip.bh)
    /// Japão, 11–24 nov 2026, `must-jp.store`.
    static let jp = Region(trip: BuiltInTrip.jp)
    /// `it`: Roma (prompt 24), EUR, `Europe/Rome`, container `must-it.store`, seed `seed-it.json`.
    static let it = Region(trip: BuiltInTrip.it)

    /// As de fábrica (os prints, o menu escondido e os testes). A lista de viagens de verdade é `TripStore.trips`.
    static var allCases: [Region] { [.bh, .jp, .it] }

    var rawValue: String { trip.id }
    var id: String { trip.id }

    static func == (a: Region, b: Region) -> Bool { a.trip.id == b.trip.id }
    func hash(into hasher: inout Hasher) { hasher.combine(trip.id) }

    static let appGroup = "group.dev.viniso.must"

    var displayName: String { trip.name }

    var shortName: String { trip.displayShortName }

    var kanji: String? { self == .jp ? "日本" : nil }

    /// Nome do país em pt-BR (Ajustes › Mapas offline, Regras da volta).
    var countryName: String { profile.name }

    /// País da região (ISO 3166-1 alfa-2): a bandeira e o tom da viagem vêm daqui (`TripTheme`).
    var country: String { trip.countryCode.uppercased() }

    /// Código ISO 4217.
    var currency: String { trip.currency }

    var currencySymbol: String { profile.symbol }

    /// A UI é sempre pt-BR; o locale define separadores e formato de data.
    var locale: Locale { Locale(identifier: "pt_BR") }

    /// Cor de destaque da região (sheet Região).
    var color: MustColor { country == "BR" ? .eat : .drink }

    /// Orçamento diário padrão, na moeda da região (Roma: € 120, como no design "€ 64 de € 120").
    var defaultBudget: Double { profile.budget }

    // MARK: Câmbio

    /// Quanto vale 1 unidade da moeda em R$ quando o usuário ainda não pôs o câmbio dele (Ajustes › Moeda).
    /// Mesma fonte do iene: valor de referência editado à mão, sem API.
    var defaultFXRate: Double { profile.defaultFXRate }

    /// A região tem câmbio pra R$ (Japão e Itália; BH já é real).
    var hasFX: Bool { currency != "BRL" }

    /// Unidade do câmbio em Ajustes: "¥100 = R$ 3,60", "€1 = R$ 6,20".
    var fxUnit: Double { profile.fxUnit }

    /// "¥100" / "€1"
    var fxUnitLabel: String { "\(currencySymbol)\(Int(fxUnit))" }

    // MARK: GPS

    /// Região pelo GPS: Japão (ilhas principais), Itália (com Vaticano e San Marino) ou Brasil → BH.
    /// Fora dos três, `nil` (não troca).
    static func detect(_ c: CLLocationCoordinate2D) -> Region? {
        switch CountryProfile.detect(c) {
        case "JP": .jp
        case "IT": .it
        case "BR": .bh
        default: nil
        }
    }

    /// Centro padrão (cidade de casa / primeira cidade).
    var defaultCenter: CLLocationCoordinate2D { trip.center }

    var storeFileName: String { trip.storeFileName }

    /// `must-<região>.store` no container do App Group (cai pro Application Support se não houver).
    var storeURL: URL { Self.storeDirectory.appending(path: storeFileName) }

    static var storeDirectory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory
    }

    /// `seed-<região>.json` no bundle. Só as de fábrica têm seed; viagem criada no app nasce vazia (prompt 28 §3.8).
    func seedURL(in bundle: Bundle = .main) -> URL? {
        guard let seed = trip.seedId else { return nil }
        return bundle.url(forResource: "seed-\(seed)", withExtension: "json")
    }

    /// "-03:00" / "+09:00"
    var utcOffsetLabel: String {
        let seconds = timeZone.secondsFromGMT(for: AppClock.now)
        let sign = seconds < 0 ? "-" : "+"
        let m = abs(seconds) / 60
        return String(format: "%@%02d:%02d", sign, m / 60, m % 60)
    }

    /// Calendário gregoriano no fuso da região.
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = locale
        return cal
    }
}
