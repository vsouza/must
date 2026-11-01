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
    case eat, drink, coffee, see, temple, listen, shop, night

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

    /// Avatar "V": azul → verde.
    static var avatar: LinearGradient {
        LinearGradient(colors: [Color.must.blue, Color.must.green], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
