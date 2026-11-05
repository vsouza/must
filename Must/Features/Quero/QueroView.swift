import SwiftUI

/// Quero… (prompt 25 · A, `Quero.png`). Stub do contrato; agente 25/1.
struct QueroView: View {
    var initialText: String?
    var body: some View {
        VStack(spacing: 12) {
            SpecLabel("prompt 25 · agente 1")
            Text("Quero…").font(V8Font.display(34)).foregroundStyle(V8.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V8.paper.ignoresSafeArea())
    }
}
