import CoreLocation
import Foundation

/// Uma região por vez. Cada uma tem o próprio container, moeda, fuso, cidades, board e gastos.
enum Region: String, CaseIterable, Codable, Sendable, Identifiable {
    case bh, jp

    var id: String { rawValue }

    static let appGroup = "group.dev.viniso.must"

    var displayName: String {
        switch self {
        case .bh: "Belo Horizonte"
        case .jp: "Japão"
        }
    }

    var shortName: String {
        switch self {
        case .bh: "BH"
        case .jp: "Japão"
        }
    }

    var kanji: String? { self == .jp ? "日本" : nil }

    /// Código ISO 4217.
    var currency: String {
        switch self {
        case .bh: "BRL"
        case .jp: "JPY"
        }
    }

    var currencySymbol: String {
        switch self {
        case .bh: "R$"
        case .jp: "¥"
        }
    }

    /// A UI é sempre pt-BR; o locale define separadores e formato de data.
    var locale: Locale { Locale(identifier: "pt_BR") }

    var timeZone: TimeZone {
        switch self {
        case .bh: TimeZone(identifier: "America/Sao_Paulo")!
        case .jp: TimeZone(identifier: "Asia/Tokyo")!
        }
    }

    /// Cor de destaque da região (sheet Região).
    var color: MustColor {
        switch self {
        case .bh: .eat
        case .jp: .drink
        }
    }

    var defaultBudget: Double {
        switch self {
        case .bh: 200
        case .jp: 15_000
        }
    }

    /// Centro padrão (cidade de casa / primeira cidade).
    var defaultCenter: CLLocationCoordinate2D {
        switch self {
        case .bh: CLLocationCoordinate2D(latitude: -19.9245, longitude: -43.9352)
        case .jp: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
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
