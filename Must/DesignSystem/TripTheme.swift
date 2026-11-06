import SwiftUI

/// Cor do lugar (v8, prompt 23 §1 e prompt 24 §1). Muda **só** a capa do dia, a Boa noite e o anel do selo
/// (`cover`/`coverInk`, em `V8/V8TripTheme.swift`) e a bandeira. Barra, botões, listas, mapa e abas nunca mudam com a
/// região (ver `MustTests/TripThemeTests`).
///
/// Simplifica o tema do prompt 20 (lavado do topo e quatro tons por país): na v8 não há lavado nem tinta do país em
/// rótulos. As propriedades antigas (`tripColor`, `labelColor`, `stampInkColor`, `washes`) ficam pras telas que ainda
/// não foram redesenhadas, já neutras (tinta/cinza), exceto a tinta do selo, que é a cor do lugar.
///
/// Cores em `UInt32` (0xRRGGBB) pra que o teste compare valores exatos. A tabela é aberta: um país novo entra
/// aqui com bandeira (`TripFlag`) e uma cor (ISO 3166-1 alfa-2). Região sem entrada cai no `neutral` (papel + tinta).
struct TripTheme: Equatable, Sendable {
    /// ISO 3166-1 alfa-2 ("JP", "BR", "IT"). Vazio no `neutral`.
    let country: String
    /// Cor do lugar: fundo da capa, da Boa noite e anel do selo.
    let coverRGB: UInt32

    /// Sem viagem: papel + tinta.
    static let neutral = TripTheme(country: "", coverRGB: V8.Hex.paper)
    /// Japão: vermelho #D7000F + branco.
    static let japan = TripTheme(country: "JP", coverRGB: 0xD7000F)
    /// Brasil: verde #007A33 + branco.
    static let brazil = TripTheme(country: "BR", coverRGB: 0x007A33)
    /// Itália (prompt 24): azzurro #1F5FB4 + branco (não repete o verde do Brasil nem o vermelho do Japão).
    static let italy = TripTheme(country: "IT", coverRGB: 0x1F5FB4)

    /// Tabela por país (ISO 3166-1 alfa-2): a cor do lugar vem de `data/countries/<cc>.json` (`colorHex`, prompt 28).
    /// País novo = arquivo novo; nada a mudar aqui.
    static let byCountry: [String: TripTheme] = CountryProfile.bundled.reduce(into: [:]) { out, entry in
        if let rgb = entry.value.coverRGB { out[entry.key] = TripTheme(country: entry.key, coverRGB: rgb) }
    }

    /// Tema do país; país fora da tabela cai no `neutral`.
    static func forCountry(_ iso: String?) -> TripTheme {
        guard let iso, let theme = byCountry[iso.uppercased()] else { return .neutral }
        return theme
    }

    /// Tema da viagem: a cor que ela escolheu (Nova viagem, passo 1), senão a do país. País sem cor nem escolha: neutro.
    static func forRegion(_ region: Region) -> TripTheme { forTrip(region.trip) }

    static func forTrip(_ trip: Trip) -> TripTheme {
        if let hex = trip.colorHex, let rgb = CountryProfile.rgb(hex) {
            return TripTheme(country: trip.countryCode.uppercased(), coverRGB: rgb)
        }
        return forCountry(trip.countryCode)
    }

    /// Há viagem (país na tabela)? Sem viagem, a capa é papel com tinta.
    var hasTrip: Bool { !country.isEmpty }

    // MARK: Compatibilidade (telas v5–v7 que ainda leem o tema do prompt 20)

    /// v8: nada lava o topo das telas.
    var washes: Bool { false }
    /// Ponto da aba / do título de seção (v5): a cor do lugar não entra em aba nem lista → tinta.
    var tripColor: Color { V8.ink }
    /// Rótulo micro da cidade e do dia (v5): cinza de texto secundário.
    var labelColor: Color { V8.mute }
    /// Tinta do selo: o anel na cor do lugar (sem viagem, tinta).
    var stampInkColor: Color { hasTrip ? Color(hex: coverRGB) : V8.ink }
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

// MARK: - Lavado (v5, desligado)

/// Lavado do topo do prompt 20. Na v8 não há lavado (a cor do lugar só entra na capa, na Boa noite e no anel do
/// selo): a view não desenha nada. Fica pra que as telas antigas compilem até serem redesenhadas.
struct TripWash: View {
    var body: some View { EmptyView() }
}

extension View {
    /// v8: não faz nada (sem lavado). Mantido pras telas antigas.
    func tripWash() -> some View { self }
}
