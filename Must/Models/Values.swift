import Foundation

// Tipos de valor usados pelos modelos SwiftData e pelo JSON do board
// (`data/board.schema.json`). Os raw values são os do schema.

enum DayWindow: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, lunch, afternoon, dinner, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: "manhã"
        case .lunch: "almoço"
        case .afternoon: "tarde"
        case .dinner: "jantar"
        case .night: "noite"
        }
    }

    /// Janelas que são refeição (regra "uma refeição por janela").
    var isMeal: Bool { self == .lunch || self == .dinner }
}

enum DayKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case free, shopping, night, photo, temples, rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "livre"
        case .shopping: "compras"
        case .night: "noite"
        case .photo: "fotografia"
        case .temples: "templos"
        case .rest: "descanso"
        }
    }
}

enum WalkLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, normal, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "pouco"
        case .normal: "normal"
        case .high: "muito"
        }
    }
}

enum ExpenseCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case food, coffee, transit, shop, ticket, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: "comida"
        case .coffee: "café"
        case .transit: "transporte"
        case .shop: "compras"
        case .ticket: "ingresso"
        case .other: "outro"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case cash, card
    case transitCard = "transit-card"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: "dinheiro"
        case .card: "cartão"
        case .transitCard: "Suica/PASMO"
        }
    }
}

enum SourceKind: String, Codable, CaseIterable, Sendable {
    case instagram, tiktok, youtube, maps, manual, board

    var label: String {
        switch self {
        case .instagram: "Reel"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .maps: "Google Maps"
        case .manual: "à mão"
        case .board: "board"
        }
    }
}

/// Foto de fundo de uma lista (Flickr CC).
struct ListPhoto: Codable, Hashable, Sendable {
    var flickrId: String?
    var url: String?
    var credit: String?
    var license: String?
    /// Página da foto no Flickr (o crédito abre aqui).
    var page: String?
}

struct Reservation: Codable, Hashable, Sendable {
    var at: Date
    var party: Int?
    var note: String?
}

/// De onde veio o lugar. `savedAt` é uma data "yyyy-MM-dd".
struct Source: Codable, Hashable, Sendable {
    var kind: SourceKind
    var url: String?
    var savedAt: String?
}

/// 済 — quando foi feito e quanto custou.
struct DoneMark: Codable, Hashable, Sendable {
    var at: Date
    var spent: Double?
}

/// Cache dos horários do Google Places (formato `regularOpeningHours`).
/// `day`: 0 = domingo … 6 = sábado, no fuso da região.
struct PlaceHours: Codable, Hashable, Sendable {
    struct Point: Codable, Hashable, Sendable {
        var day: Int
        var hour: Int
        var minute: Int
    }

    struct Period: Codable, Hashable, Sendable {
        var open: Point
        var close: Point?
    }

    var weekdayText: [String]?
    var periods: [Period]?
    var fetchedAt: Date?
}

/// Trecho de cidade da viagem (ou a cidade de casa, em BH).
struct City: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var from: Date?
    var to: Date?
    var tz: String
    var currency: String
    var lat: Double
    var lng: Double

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }
}
