import CoreLocation
import Foundation

/// Uma região por vez. Cada uma tem o próprio container, moeda, fuso, cidades, board e gastos.
enum Region: String, CaseIterable, Codable, Sendable, Identifiable {
    /// `it`: Roma (prompt 24), terceira região — EUR, `Europe/Rome`, container `must-it.store`, seed `seed-it.json`.
    case bh, jp, it

    var id: String { rawValue }

    static let appGroup = "group.dev.viniso.must"

    var displayName: String {
        switch self {
        case .bh: "Belo Horizonte"
        case .jp: "Japão"
        case .it: "Roma"
        }
    }

    var shortName: String {
        switch self {
        case .bh: "BH"
        case .jp: "Japão"
        case .it: "Roma"
        }
    }

    var kanji: String? { self == .jp ? "日本" : nil }

    /// Nome do país em pt-BR (Ajustes › Mapas offline, Regras da volta).
    var countryName: String {
        switch self {
        case .bh: "Brasil"
        case .jp: "Japão"
        case .it: "Itália"
        }
    }

    /// País da região (ISO 3166-1 alfa-2): a bandeira e o tom da viagem vêm daqui (`TripTheme`).
    var country: String {
        switch self {
        case .bh: "BR"
        case .jp: "JP"
        case .it: "IT"
        }
    }

    /// Código ISO 4217.
    var currency: String {
        switch self {
        case .bh: "BRL"
        case .jp: "JPY"
        case .it: "EUR"
        }
    }

    var currencySymbol: String {
        switch self {
        case .bh: "R$"
        case .jp: "¥"
        case .it: "€"
        }
    }

    /// A UI é sempre pt-BR; o locale define separadores e formato de data.
    var locale: Locale { Locale(identifier: "pt_BR") }

    var timeZone: TimeZone {
        switch self {
        case .bh: TimeZone(identifier: "America/Sao_Paulo")!
        case .jp: TimeZone(identifier: "Asia/Tokyo")!
        case .it: TimeZone(identifier: "Europe/Rome")!
        }
    }

    /// Cor de destaque da região (sheet Região).
    var color: MustColor {
        switch self {
        case .bh: .eat
        case .jp: .drink
        case .it: .drink
        }
    }

    /// Orçamento diário padrão, na moeda da região (Roma: € 120, como no design "€ 64 de € 120").
    var defaultBudget: Double {
        switch self {
        case .bh: 200
        case .jp: 15_000
        case .it: 120
        }
    }

    // MARK: Câmbio

    /// Quanto vale 1 unidade da moeda em R$ quando o usuário ainda não pôs o câmbio dele (Ajustes › Moeda).
    /// Mesma fonte do iene: valor de referência editado à mão, sem API.
    var defaultFXRate: Double {
        switch self {
        case .bh: 1
        case .jp: 0.036
        case .it: 6.2
        }
    }

    /// A região tem câmbio pra R$ (Japão e Itália; BH já é real).
    var hasFX: Bool { currency != "BRL" }

    /// Unidade do câmbio em Ajustes: "¥100 = R$ 3,60", "€1 = R$ 6,20".
    var fxUnit: Double { self == .jp ? 100 : 1 }

    /// "¥100" / "€1"
    var fxUnitLabel: String { "\(currencySymbol)\(Int(fxUnit))" }

    // MARK: GPS

    /// Região pelo GPS: Japão (ilhas principais), Itália (com Vaticano e San Marino) ou Brasil → BH.
    /// Fora dos três, `nil` (não troca).
    static func detect(_ c: CLLocationCoordinate2D) -> Region? {
        if (24...46).contains(c.latitude), (122...154).contains(c.longitude) { return .jp }
        if (35.4...47.1).contains(c.latitude), (6.6...18.6).contains(c.longitude) { return .it }
        if (-34...6).contains(c.latitude), (-74...(-34)).contains(c.longitude) { return .bh }
        return nil
    }

    /// Centro padrão (cidade de casa / primeira cidade).
    var defaultCenter: CLLocationCoordinate2D {
        switch self {
        case .bh: CLLocationCoordinate2D(latitude: -19.9245, longitude: -43.9352)
        case .jp: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        case .it: CLLocationCoordinate2D(latitude: 41.8955, longitude: 12.4823)
        }
    }

    var storeFileName: String { "must-\(rawValue).store" }

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
