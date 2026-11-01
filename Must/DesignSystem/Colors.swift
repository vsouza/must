import SwiftUI

extension Color {
    /// `Color(hex: 0x22DD7E)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static let must = MustPalette()
}

/// Tokens do tema claro (v5). Nada no app usa `Color.accentColor`.
struct MustPalette: Sendable {
    let bg = Color(hex: 0xFFFFFF)
    let ink = Color(hex: 0x121316)
    let secondary = Color(hex: 0x7A7F87)
    let surface = Color(hex: 0xF1F2F4)
    let surface2 = Color(hex: 0xF6F7F9)
    let line = Color(hex: 0xEEF0F3)
    /// Borda de botões fantasma e toggles.
    let lineStrong = Color(hex: 0xE4E6EA)
    let green = Color(hex: 0x22DD7E)
    let greenText = Color(hex: 0x0B2A18)
    let blue = Color(hex: 0x2B7BFF)
    let blueText = Color(hex: 0x0F3B8C)
    /// Texto secundário sobre o verde (subtítulos dos stack cards).
    let greenTextSoft = Color(hex: 0x0B5A33)
    let link = Color(hex: 0x1E73FF)
}

/// Cor de cada Must: claro → forte, com texto escuro por cima.
enum MustColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case eat, drink, coffee, see, temple, listen, shop, night, photo, art, sport

    var id: String { rawValue }

    var light: Color {
        switch self {
        case .eat: Color(hex: 0xB9F5CF)
        case .drink: Color(hex: 0x9FD6FF)
        case .coffee: Color(hex: 0xFFD2BF)
        case .see: Color(hex: 0xDCCFFF)
        case .temple: Color(hex: 0xB8F2EA)
        case .listen: Color(hex: 0xFFC6DA)
        case .shop: Color(hex: 0xFFE3A3)
        case .night: Color(hex: 0xC9D2FF)
        case .photo: Color(hex: 0xE9EBEF)
        case .art: Color(hex: 0xDCCFFF)
        case .sport: Color(hex: 0xFFD1C7)
        }
    }

    var strong: Color {
        switch self {
        case .eat: Color(hex: 0x22DD7E)
        case .drink: Color(hex: 0x2B7BFF)
        case .coffee: Color(hex: 0xFF7A45)
        case .see: Color(hex: 0x8B5CF6)
        case .temple: Color(hex: 0x14B8A6)
        case .listen: Color(hex: 0xFF4D8D)
        case .shop: Color(hex: 0xFFB020)
        case .night: Color(hex: 0x5B6CFF)
        case .photo: Color(hex: 0x8A94A6)
        case .art: Color(hex: 0x8B5CF6)
        case .sport: Color(hex: 0xFF5A3C)
        }
    }

    var text: Color {
        switch self {
        case .eat: Color(hex: 0x0B2A18)
        case .drink: Color(hex: 0x0F3B8C)
        case .coffee: Color(hex: 0x5A2200)
        case .see: Color(hex: 0x2E1065)
        case .temple: Color(hex: 0x063F3A)
        case .listen: Color(hex: 0x5A0F2E)
        case .shop: Color(hex: 0x4A2E00)
        case .night: Color(hex: 0x161C66)
        case .photo: Color(hex: 0x121316)
        case .art: Color(hex: 0x2E1065)
        case .sport: Color(hex: 0x5A1A0E)
        }
    }

    /// 135°, claro → forte.
    var gradient: LinearGradient {
        LinearGradient(colors: [light, strong], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func gradient(opacity: Double) -> LinearGradient {
        LinearGradient(colors: [light.opacity(opacity), strong.opacity(opacity)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Nome pt-BR pra pickers.
    var label: String {
        switch self {
        case .eat: "eat"
        case .drink: "drink"
        case .coffee: "coffee"
        case .see: "see"
        case .temple: "temple"
        case .listen: "listen"
        case .shop: "shop"
        case .night: "night"
        case .photo: "photo"
        case .art: "art"
        case .sport: "sport"
        }
    }
}

extension UnitPoint {
    /// Pontos de um `linear-gradient(<deg>)` do CSS num quadrado unitário.
    static func cssGradient(_ degrees: Double) -> (start: UnitPoint, end: UnitPoint) {
        let r = degrees * .pi / 180
        let dx = sin(r) / 2, dy = -cos(r) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

/// Gradientes que não são de um Must (céu do card "Perto de você", blobs).
enum MustGradient {
    static var sky: LinearGradient {
        let p = UnitPoint.cssGradient(160)
        return LinearGradient(colors: [Color(hex: 0xEAF4FF), Color(hex: 0x9CCBFF)], startPoint: p.start, endPoint: p.end)
    }

    static func sky(opacity: (Double, Double)) -> LinearGradient {
        let p = UnitPoint.cssGradient(160)
        return LinearGradient(colors: [Color(hex: 0xEAF4FF).opacity(opacity.0), Color(hex: 0x9CCBFF).opacity(opacity.1)],
                              startPoint: p.start, endPoint: p.end)
    }

    /// Golden hour (chip "golden em 1h18", card Sol hoje): claro → forte, texto `goldText`.
    static let goldLight = Color(hex: 0xFFE9C2)
    static let goldStrong = Color(hex: 0xFFB347)
    static let goldText = Color(hex: 0x4A2E00)
    /// Laranja do trecho golden no arco.
    static let goldArc = Color(hex: 0xFF8A00)
    static var gold: LinearGradient {
        LinearGradient(colors: [goldLight, goldStrong], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Hora azul / crepúsculo.
    static let duskLight = Color(hex: 0xC9D2FF)
    static let duskStrong = Color(hex: 0x5B6CFF)
    static let duskText = Color(hex: 0x161C66)
    static var dusk: LinearGradient {
        LinearGradient(colors: [duskLight, duskStrong], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Avatar "V": azul → verde.
    static var avatar: LinearGradient {
        LinearGradient(colors: [Color.must.blue, Color.must.green], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
