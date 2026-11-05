import SwiftUI

/// Minhas viagens (`TrocarViagem.png`), aberta pelo botão no canto superior esquerdo da capa. Stub; agente E.
struct TripSwitcherSheet: View {
    var body: some View {
        Text("Minhas viagens").font(V8Font.display(28)).foregroundStyle(V8.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(V8.paper.ignoresSafeArea())
    }
}
