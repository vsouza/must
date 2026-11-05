import SwiftUI

extension Color {
    /// `Color(hex: 0xFF4A1C)`
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

/// Tokens v5 mantidos pras telas que ainda não foram redesenhadas, **redirecionados pra identidade v8**
/// (`V8Palette.swift`): três cores — tinta, papel, laranja — e cinzas só pra texto secundário.
/// Lima, azul e verde-ação somem: ação = laranja, link = laranja escuro, o resto vira tinta/papel.
/// Nada no app usa `Color.accentColor`.
struct MustPalette: Sendable {
    /// Fundo padrão das telas: papel.
    let bg = V8.paper
    let ink = V8.ink
    let secondary = V8.mute
    /// Superfície sobre papel (cards cinza da v5): osso.
    let surface = V8.bone
    /// Card claro sobre papel: branco (os cards de Must do design).
    let surface2 = V8.white
    /// Filete (tinta a 14 % sobre papel).
    let line = Color(hex: V8.Hex.rule)
    /// Borda de botões fantasma e toggles (tinta a 30 % sobre papel).
    let lineStrong = Color(hex: V8.Hex.ruleStrong)
    /// Verde-ação v5 → laranja (ação).
    let green = V8.orange
    /// Texto sobre a ação: tinta (5,6:1).
    let greenText = V8.ink
    /// Azul v5 → tinta.
    let blue = V8.ink
    /// Texto azul v5 → tinta.
    let blueText = V8.ink
    /// Texto secundário sobre a ação.
    let greenTextSoft = V8.ink
    /// Link: laranja como texto sobre papel (4,7:1).
    let link = V8.orangeDeep
}

/// Cor de cada Must (v5). Na v8 as listas **não têm cor**: os tokens viram papel/osso e tinta, iguais pra toda lista.
/// O enum fica (é o tipo da lista no modelo e no JSON); as telas v8 nem leem estas cores.
enum MustColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case eat, drink, coffee, see, temple, listen, shop, night, photo, art, sport

    var id: String { rawValue }

    /// Fundo claro (chips, faixas): osso, com tinta por cima.
    var light: Color { V8.bone }

    /// Cor forte (pontos, barras, pinos): tinta.
    var strong: Color { V8.ink }

    /// Texto sobre `light`/`gradient`: tinta.
    var text: Color { V8.ink }

    /// Sem degradê na v8: cor sólida (`light`), com o mesmo tipo da v5.
    var gradient: LinearGradient {
        LinearGradient(colors: [light, light], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func gradient(opacity: Double) -> LinearGradient {
        LinearGradient(colors: [light.opacity(opacity), light.opacity(opacity)],
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

/// Gradientes v5 (céu, golden, crepúsculo, avatar). Na v8 não há degradê: viram cor sólida da identidade.
/// Golden = laranja (o selo "SOL" da Linha); céu e crepúsculo = osso com tinta.
enum MustGradient {
    private static func solid(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom)
    }

    static var sky: LinearGradient { solid(V8.bone) }

    static func sky(opacity: (Double, Double)) -> LinearGradient {
        solid(V8.bone.opacity(opacity.0))
    }

    /// Golden hour: laranja sólido, texto tinta.
    static let goldLight = V8.orange
    static let goldStrong = V8.orange
    static let goldText = V8.ink
    /// Trecho golden no arco.
    static let goldArc = V8.orange
    static var gold: LinearGradient { solid(V8.orange) }

    /// Hora azul / crepúsculo: osso → tinta como texto.
    static let duskLight = V8.bone
    static let duskStrong = V8.bone
    static let duskText = V8.ink
    static var dusk: LinearGradient { solid(V8.bone) }

    /// Avatar "V": laranja sólido.
    static var avatar: LinearGradient { solid(V8.orange) }
}
