import CoreLocation
import Foundation

/// Uma região por vez. Cada uma tem o próprio container, moeda, fuso, cidades, board e gastos.
enum Region: String, CaseIterable, Codable, Sendable, Identifiable {
    /// `it`: Roma (prompt 24), terceira região — EUR, `Europe/Rome`, container `must-it.store`, seed `seed-it.json`.
    case bh, jp, it

    var id: String { rawValue }

    static let appGroup = "group.dev.viniso.must"

    /// A viagem de fábrica desta região (prompt 28: o registro `trips.json` é semeado com estas).
    var trip: Trip { KnownTrips.shared.trip(rawValue) ?? BuiltInTrip.trip(rawValue)! }

    /// O que muda por país (`data/countries/<cc>.json`).
    var profile: CountryProfile { CountryProfile.forCountry(country, currency: currency, timeZone: trip.timeZone) }

    var displayName: String { trip.name }

    var shortName: String { trip.displayShortName }

    var kanji: String? { self == .jp ? "日本" : nil }

    /// Nome do país em pt-BR (Ajustes › Mapas offline, Regras da volta).
    var countryName: String { profile.name }

    /// País da região (ISO 3166-1 alfa-2): a bandeira e o tom da viagem vêm daqui (`TripTheme`).
    var country: String { BuiltInTrip.trip(rawValue)?.countryCode ?? trip.countryCode }

    /// Código ISO 4217.
    var currency: String { trip.currency }

    var currencySymbol: String { profile.symbol }

    /// A UI é sempre pt-BR; o locale define separadores e formato de data.
    var locale: Locale { Locale(identifier: "pt_BR") }

    var timeZone: TimeZone { trip.tz }

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

    /// `seed-<região>.json` no bundle.
    func seedURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "seed-\(rawValue)", withExtension: "json")
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
