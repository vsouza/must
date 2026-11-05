import SwiftUI

/// Cor do lugar v8 (prompt 23 §1, prompt 24 §1): só a **capa do dia**, a **Boa noite** e o **anel do selo**.
/// Nunca em botão, lista, mapa ou aba. Japão #D7000F + branco; Brasil #007A33 + branco; Itália azzurro #1F5FB4 + branco;
/// sem viagem: papel + tinta. As telas usam só `cover`, `coverInk`, `flag` e `TripTheme.forRegion(_:)`.
extension TripTheme {
    /// Fundo da capa, da Boa noite e anel do selo.
    var cover: Color { Color(hex: coverRGB) }
    /// Tinta sobre a cor do lugar (branco; tinta quando não há viagem).
    var coverInk: Color { hasTrip ? V8.white : V8.ink }
    /// Bandeira do país em vetor (círculo 22 pt). Vazia sem viagem.
    var flag: AnyView { AnyView(TripFlag(self)) }

    /// Cor do lugar pro país (0xRRGGBB); sem país na tabela, papel.
    static func coverHex(_ country: String) -> UInt32 { forCountry(country).coverRGB }
}
