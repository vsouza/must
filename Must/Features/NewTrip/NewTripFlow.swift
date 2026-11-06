import SwiftUI

/// Nova viagem (prompt 28 · F3): stub do contrato até o agente p28/f3 entregar as 9 telas (`design/v8/screens/NovaViagem1…9`).
struct NewTripFlow: View {
    var startStep: Int = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Nova viagem").font(V8Font.display(40)).foregroundStyle(V8.ink)
            Text("passo \(startStep) de 9").font(V8Font.mono(12)).foregroundStyle(V8.mute)
            Button("Fechar") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V8.paper.ignoresSafeArea())
    }
}
