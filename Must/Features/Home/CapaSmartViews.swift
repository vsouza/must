import SwiftUI

// Peças da capa inteligente (prompt 26 §4, `CapaInteligente.png`): fileira "Agora vale", cartão, card da noite, chip "Em cartaz".

/// Cartão do "Agora vale": Must = tinta, evento = laranja, o resto = papel. Toque abre; toque longo = "não me sugere isso hoje".
struct SuggestionCardView: View {
    var card: Suggestion
    var open: () -> Void
    var dismiss: () -> Void

    private var background: Color {
        switch card.style {
        case .ink: V8.ink
        case .orange: V8.orange
        case .paper: V8.paper
        }
    }
    private var labelColor: Color { card.style == .ink ? V8.orange : (card.style == .orange ? V8.ink : V8.orangeDeep) }
    private var titleColor: Color { card.style == .ink ? V8.white : V8.ink }
    private var metaColor: Color { card.style == .ink ? V8.muteDark : V8.ink.opacity(0.7) }
    private var dotColor: Color { card.style == .orange ? V8.ink : V8.orange }
    private var reasonColor: Color { card.style == .ink ? V8.white.opacity(0.85) : V8.ink.opacity(0.8) }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MonoLabel(card.label, size: 10, color: labelColor)
                    Spacer(minLength: 4)
                    if let trailing = card.trailing {
                        Text(trailing.uppercased()).font(V8Font.mono(10)).foregroundStyle(card.style == .ink ? V8.white : V8.ink).lineLimit(1)
                    }
                }
                Text(card.title)
                    .font(V8Font.text(21, weight: .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(card.meta)
                    .font(V8Font.text(13))
                    .foregroundStyle(metaColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                    MonoLabel(card.reasonLine, size: 9, color: reasonColor)
                }
            }
            .padding(16)
            .frame(width: 264, height: 142, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(background))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(MustPressStyle())
        .contextMenu {
            Button(role: .destructive, action: dismiss) { Label("Não me sugere isso hoje", systemImage: "eye.slash") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label). \(card.title). \(card.meta). \(card.reasonLine)")
        .accessibilityHint("Toque abre. Segure pra não sugerir isso hoje.")
        .accessibilityAction(named: "Não me sugerir isso hoje", dismiss)
    }
}

/// "Agora vale · por quê → toque" + a fileira de cartões + o rodapé das fontes.
struct AgoraValeRow: View {
    var cards: [Suggestion]
    var sources: [String]
    var ink: Color
    var open: (Suggestion) -> Void
    var dismiss: (Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agora vale").font(V8Font.display(26, weight: 700)).foregroundStyle(ink)
                Spacer(minLength: 8)
                MonoLabel("por quê → toque", size: 10, color: ink.opacity(0.85))
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cards) { card in
                        SuggestionCardView(card: card, open: { open(card) }, dismiss: { dismiss(card) })
                    }
                }
                .padding(.horizontal, 20)
            }
            if !sources.isEmpty {
                MonoLabel("fontes: " + sources.joined(separator: " · "), size: 9, color: ink.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Fontes: " + sources.joined(separator: ", "))
            }
        }
    }
}

/// "Noite, pra onde? → Montar a noite · Lourdes e Savassi" (mesmo card preto do "Agora").
struct NightCard: View {
    var night: SuggestCopy.Night
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(night.title, size: 10, color: V8.orange)
                    Text(night.line).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.white).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V8.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(V8.white))
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(V8.ink))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("\(night.title) \(night.line)")
    }
}

/// Chip papel "● Em cartaz · 2 hoje ↗" (`CapaEmCartaz.png`): abre a tela Em cartaz.
struct EmCartazChip: View {
    var count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(V8.orange).frame(width: 10, height: 10)
                Text("Em cartaz · \(count) hoje").font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V8.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(V8.ink))
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Capsule().fill(V8.paper))
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("Em cartaz, \(count) hoje")
    }
}
