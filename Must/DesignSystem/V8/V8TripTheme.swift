import SwiftUI

/// Cor do lugar v8 (prompt 23 §1, prompt 24 §1): só a **capa do dia**, a **Boa noite** e o **anel do selo**.
/// Nunca em botão, lista, mapa ou aba. Japão #D7000F + branco; Brasil #007A33 + branco; Itália azzurro #1F5FB4 + branco;
/// sem viagem: papel + tinta.
///
/// Contrato da fase 0: extensão do `TripTheme` existente (prompt 20). O agente A transforma no tema v8 de verdade
/// (e pode tirar o lavado/tons do v5); as telas usam só `cover`, `coverInk`, `flag` e `TripTheme.forRegion(_:)`.
extension TripTheme {
    /// Fundo da capa, da Boa noite e anel do selo.
    var cover: Color { Color(hex: Self.coverHex(country)) }
    /// Tinta sobre a cor do lugar (branco; tinta quando não há viagem).
    var coverInk: Color { country.isEmpty ? V8.ink : V8.white }
    /// Bandeira do país em vetor (círculo 22 pt). Vazia sem viagem.
    var flag: AnyView { AnyView(TripFlag(self)) }

    static func coverHex(_ country: String) -> UInt32 {
        switch country.uppercased() {
        case "JP": 0xD7000F
        case "BR": 0x007A33
        case "IT": 0x1F5FB4
        default: V8.Hex.paper
        }
    }
}
