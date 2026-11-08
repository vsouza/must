import SwiftUI

/// Faixa tinta "✦ isso é uma pergunta" com a resposta curta e a faixa laranja "Continuar no Assistente" (`Assistente-3.png`).
/// Largura total, sem raio. Nunca mistura resposta e lugares: os chips de lugar ficam embaixo, em outra faixa.
struct QueroQuestionSlab: View {
    var question: QueroQuestionState
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("✦ ISSO É UMA PERGUNTA")
                    .font(V8Font.mono(10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(V8.orange)
                if let answer = question.answer {
                    Text(answer)
                        .font(V8Font.text(17, weight: .semibold))
                        .foregroundStyle(V8.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("pensando no aparelho…")
                        .font(V8Font.text(15))
                        .foregroundStyle(V8.muteDark)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.ink)
            .accessibilityElement(children: .combine)
            Button(action: onContinue) {
                HStack {
                    Text("Continuar no Assistente")
                        .font(V8Font.text(17, weight: .bold))
                        .foregroundStyle(V8.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold)).foregroundStyle(V8.ink)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(V8.orange)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("abre o Assistente com a sua pergunta")
        }
    }
}
