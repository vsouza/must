import SwiftUI

/// Destino da rota `.presenteNovo` (`+ › Presente`). O agente dos Presentes troca este placeholder pela folha de verdade
/// (o case no `Route` e a entrada no `+` já apontam pra cá).
struct PresenteNovoPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                V8CornerButton(systemName: "chevron.left", label: "Voltar") { dismiss() }
                Spacer(minLength: 12)
                AssistantCorner()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Text("Presente")
                .font(V8Font.display(52))
                .tracking(-1.6)
                .foregroundStyle(V8.ink)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
            Text("Em breve: o que, pra quem, quanto e onde comprar.")
                .font(V8Font.text(15))
                .foregroundStyle(V8.mute)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            Spacer()
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
