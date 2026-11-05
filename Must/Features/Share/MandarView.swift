import SwiftUI

/// Mandar o dia (prompt 25 · B, `Compartilhar.png`). Stub do contrato; agente 25/2. `date` nil = a viagem inteira.
struct MandarView: View {
    var date: Date?
    var body: some View {
        VStack(spacing: 12) {
            SpecLabel("prompt 25 · agente 2")
            Text("Mandar o dia").font(V8Font.display(34)).foregroundStyle(V8.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V8.paper.ignoresSafeArea())
    }
}
