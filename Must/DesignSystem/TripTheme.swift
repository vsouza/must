import SwiftUI

/// Tema da viagem (prompt 20): bandeira e tom leve do país da região. Muda o clima, não a identidade:
/// botões verdes, links azuis, tinta, cores das listas, linhas de trem e pinos do mapa **não** usam este tema
/// (ver `MustTests/TripThemeTests`). Usado no lavado do topo, nos selos (`StampPalette`), no rótulo da cidade,
/// no ponto dos títulos de seção e na aba ativa.
///
/// Cores em `UInt32` (0xRRGGBB) pra que o teste compare valores exatos. A tabela é aberta: um país novo entra
/// aqui com bandeira e quatro tons (ISO 3166-1 alfa-2). Região sem entrada cai no `neutral` (sem lavado).
struct TripTheme: Equatable, Sendable {
    /// ISO 3166-1 alfa-2 ("JP", "BR"). Vazio no `neutral`.
    let country: String
    /// Vermelho/verde da bandeira: ponto da aba, ponto dos títulos, borda da coleção.
    let trip: UInt32
    /// Texto pequeno em tom do país (rótulo da cidade e do dia).
    let tripInk: UInt32
    /// Topo do lavado (300 pt, ou cor sólida de 120 pt com "Reduzir transparência").
    let tripSoft: UInt32
    /// Meio do lavado, e a cor sólida quando não há transparência.
    let tripSoft2: UInt32
    /// Tinta dos selos sobre papel (e o fundo do selo sobre foto, a 55%).
    let stampInk: UInt32
    /// Só o `neutral` não lava o topo.
    var washes: Bool { !country.isEmpty }

    /// Identidade do Must, pra região sem país na tabela: mesma tinta verde do app, sem lavado.
    static let neutral = TripTheme(country: "", trip: 0x22DD7E, tripInk: 0x0B5A33,
                                   tripSoft: 0xFFFFFF, tripSoft2: 0xFFFFFF, stampInk: 0x121316)

    static let japan = TripTheme(country: "JP", trip: 0xBC002D, tripInk: 0x8A0021,
                                 tripSoft: 0xFDECEF, tripSoft2: 0xFFF6F7, stampInk: 0xC8102E)

    static let brazil = TripTheme(country: "BR", trip: 0x009C3B, tripInk: 0x00692A,
                                  tripSoft: 0xE6F6EC, tripSoft2: 0xFFF9DB, stampInk: 0x00692A)

    /// Tabela por país (ISO 3166-1 alfa-2). Acrescente aqui um país novo.
    static let byCountry: [String: TripTheme] = [
        "JP": .japan,
        "BR": .brazil,
    ]

    /// Tema do país; país fora da tabela cai no `neutral`.
    static func forCountry(_ iso: String?) -> TripTheme {
        guard let iso, let theme = byCountry[iso.uppercased()] else { return .neutral }
        return theme
    }

    /// Tema da região (o país de cada região está em `Region.country`).
    static func forRegion(_ region: Region) -> TripTheme { forCountry(region.country) }

    var tripColor: Color { Color(hex: trip) }
    var tripInkColor: Color { Color(hex: tripInk) }
    var stampInkColor: Color { Color(hex: stampInk) }
    /// Rótulo micro da cidade e do dia: tom do país; sem país, o secundário de sempre.
    var labelColor: Color { washes ? tripInkColor : Color.must.secondary }
}

// MARK: - Ambiente

private struct TripThemeKey: EnvironmentKey {
    static var defaultValue: TripTheme { .neutral }
}

extension EnvironmentValues {
    /// Tema da viagem da região atual. Injetado em `MustApp` (fora do `.id` da árvore).
    var tripTheme: TripTheme {
        get { self[TripThemeKey.self] }
        set { self[TripThemeKey.self] = newValue }
    }
}

// MARK: - Lavado

/// Lavado do topo (`tripSoft → tripSoft2 → transparente`, 300 pt). Com "Reduzir transparência" vira a cor
/// sólida `tripSoft2` em 120 pt. Atrás de tudo: nunca cobre conteúdo.
struct TripWash: View {
    enum Shape: Equatable, Sendable {
        case none
        case gradient(height: CGFloat)
        case solid(color: UInt32, height: CGFloat)
    }

    /// Forma do lavado pro tema e a preferência do sistema. Função pura, pra teste.
    static func shape(for theme: TripTheme, reduceTransparency: Bool) -> Shape {
        guard theme.washes else { return .none }
        return reduceTransparency ? .solid(color: theme.tripSoft2, height: 120) : .gradient(height: 300)
    }

    @Environment(\.tripTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch Self.shape(for: theme, reduceTransparency: reduceTransparency) {
        case .none:
            EmptyView()
        case .gradient(let height):
            LinearGradient(
                stops: [
                    .init(color: Color(hex: theme.tripSoft), location: 0),
                    .init(color: Color(hex: theme.tripSoft2), location: 0.45),
                    .init(color: Color(hex: theme.tripSoft2).opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.4), value: theme)
        case .solid(let color, let height):
            Color(hex: color)
                .frame(height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.4), value: theme)
        }
    }
}

extension View {
    /// Lavado do tema no topo da tela. Aplique **antes** do `.background` de fundo da tela: o lavado fica
    /// por cima do fundo branco e por baixo do conteúdo (o `.background` seguinte fica por trás dele).
    func tripWash() -> some View {
        background(alignment: .top) {
            TripWash().ignoresSafeArea()
        }
    }
}
