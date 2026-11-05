import SwiftUI

/// Tela-stub do contrato da rodada 22 (fase 0): ocupa o lugar de uma tela v8 até o agente dono entregar.
/// Some quando nenhuma tela usar mais (o QA da fase 3 confere com `grep V8StubScreen`).
struct V8StubScreen: View {
    var number: String
    var title: String
    var owner: String
    var dark = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            (dark ? V8.ink : V8.paper).ignoresSafeArea()
            Rings(color: dark ? V8.white : V8.ink)
            VStack(alignment: .leading, spacing: 8) {
                SpecLabel("Tela \(number) · agente \(owner)", color: dark ? V8.muteDark : V8.mute)
                Text(title).font(V8Font.display(34)).foregroundStyle(dark ? V8.white : V8.ink)
                Spacer()
                BigNumeral(number, size: 180, color: dark ? V8.white : V8.ink)
            }
            .padding(.horizontal, 22)
            .padding(.top, 60)
            .padding(.bottom, 96)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
