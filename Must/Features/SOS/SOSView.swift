import SwiftUI

/// SOS (prompt 25 · C, `SOS.png`). Stub do contrato; agente 25/2.
struct SOSView: View {
    var body: some View {
        VStack(spacing: 12) {
            SpecLabel("prompt 25 · agente 2", color: V8.muteDark)
            Text("SOS").font(V8Font.display(34)).foregroundStyle(V8.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V8.ink.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
