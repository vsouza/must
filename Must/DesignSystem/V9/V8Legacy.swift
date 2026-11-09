import SwiftUI

/// Modo escuro na Fase 1 (prompt 32 §5): o app segue o aparelho, mas as telas que ainda são V8 (papel fixo + texto
/// do sistema misturados) continuam no claro até serem convertidas. Ao converter uma tela pro V9: tire o
/// `.v8Legacy()` dela (ou a rota de `Route.legacyLight`) e use `.v9Screen()`.
extension View {
    /// Tela V8 dentro de uma pilha ou aba: força o claro só nesta subárvore.
    @ViewBuilder func v8Legacy(_ enabled: Bool = true) -> some View {
        if enabled { environment(\.colorScheme, .light) } else { self }
    }

    /// Sheet/tela cheia V8: a apresentação inteira no claro.
    func v8LegacySheet(_ enabled: Bool = true) -> some View {
        preferredColorScheme(enabled ? .light : nil)
    }
}

extension Route {
    /// Rotas que ainda são V8 (ficam no claro). As outras já são V9 (Fases 1 e 2 do prompt 32).
    var legacyLight: Bool {
        switch self {
        case .montar, .day, .bomDia, .boaNoite, .guia, .bairros, .irBairro, .mapa: return true
        default: return false
        }
    }
}
