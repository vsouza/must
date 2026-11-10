import SwiftUI

// Peças da aba Hoje no corte (rodada 33): bloco do bairro, linha laranja da próxima parada, linhas do índice e faixas.
// Tudo recebe dado pronto (`HojeNext`, `Suggestion`, `SpecialDay`); nada decide nada aqui.

/// O campo "Pedir algo…": faixa quadrada com nome visível, logo abaixo da régua. Toque abre o Quero.
struct HojeAskField: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.ink)
                Text("Pedir algo…").font(V8Font.text(16, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(1)
                Spacer(minLength: 8)
                MonoLabel("quero", size: 10, color: V8.mute)
                Image(systemName: "mic.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(V8.ink).accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityLabel("Pedir algo")
        .accessibilityHint("Abre o Quero")
    }
}

/// Chip "sem internet · offline ok" (só sem rede).
struct HojeOfflineStrip: View {
    var body: some View {
        DayStrip {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash").font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                MonoLabel("sem internet · offline ok", size: 10, color: V8.ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sem internet. O app funciona offline com o que já está no aparelho.")
    }
}

/// Faixa de aviso com uma ação e ✕: Bom dia / Boa noite e "Você chegou em X · ver perto".
struct HojeNoticeStrip: View {
    var tone: DayStrip<EmptyView>.Tone = .paper
    var systemImage: String
    var text: String
    var actionTitle: String
    var action: () -> Void
    var dismiss: () -> Void

    private var fg: Color { tone == .ink ? V8.white : V8.ink }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .bold)).accessibilityHidden(true)
                    Text(text).font(V8Font.text(15, weight: .bold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(actionTitle.uppercased()).font(V8Font.mono(10, weight: .semibold)).tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .overlay(Rectangle().stroke(fg, lineWidth: 1.5))
                }
                .foregroundStyle(fg)
                .padding(.leading, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(text). \(actionTitle)")
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(fg)
                    .frame(width: 52, height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dispensar")
        }
        .background(tone == .ink ? V8.ink : tone == .orange ? V8.orange : Color.clear)
        .overlay(alignment: .bottom) { IndexRule() }
    }
}

/// A próxima parada (ou a de agora): bloco laranja inteiro, hora grande, nome, "saia às" do `DayClock` e o botão Ir.
struct HojeNextBlock: View {
    var next: HojeNext
    var region: Region
    var onGo: () -> Void

    private var actionText: String { HojeLogic.action(next, region: region) }
    private var isNow: Bool { actionText.hasSuffix("agora") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNow ? "já" : region.timeString(next.actionAt))
                        .font(V8Font.numeral(isNow ? 44 : 40)).tracking(-1)
                        .foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.6)
                    Text((isNow ? next.verb + " agora" : next.verb + " às").uppercased())
                        .font(V8Font.mono(9)).tracking(0.9).foregroundStyle(V8.ink.opacity(0.75)).lineLimit(1)
                }
                .frame(width: 104, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(next.phase == .next ? "próxima" : "agora", size: 10, color: V8.ink.opacity(0.75))
                    Text(next.name).font(V8Font.text(22, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                    Text(HojeLogic.detail(next, region: region)).font(V8Font.text(13)).foregroundStyle(V8.ink.opacity(0.8))
                        .lineLimit(2).monospacedDigit()
                    if let then = next.thenName, next.phase == .now {
                        Text("Depois: \(then)").font(V8Font.text(13)).foregroundStyle(V8.ink.opacity(0.8)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if next.placeId != nil {
                Button(action: onGo) {
                    HStack {
                        Text("IR").font(V8Font.mono(14, weight: .semibold)).tracking(1.4)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(V8.paper)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(V8.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ir pra \(next.name)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.orange)
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityElement(children: .contain)
    }
}

/// Uma linha do índice: número grande (hora ou distância) à esquerda, nome e motivo à direita. Laranja = Must seu,
/// tinta = de fora do board, papel = o resto. Régua de 2 pt embaixo.
struct HojeIndexRow: View {
    enum Tone { case orange, ink, paper }
    var tone: Tone
    var big: String
    var unit: String
    var title: String
    var reason: String
    var trust: String?
    var chevron = true
    var action: () -> Void

    private var main: Color { tone == .ink ? V8.white : V8.ink }
    private var sub: Color { tone == .ink ? V8.muteDark : tone == .orange ? V8.ink.opacity(0.75) : V8.mute }
    private var fill: Color { tone == .ink ? V8.ink : tone == .orange ? V8.orange : .clear }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(big).font(V8Font.numeral(30)).tracking(-0.6).foregroundStyle(main).lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(unit.uppercased()).font(V8Font.mono(9)).tracking(0.9).foregroundStyle(sub).lineLimit(1)
                    }
                }
                .frame(width: 88, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(main).lineLimit(2)
                    if let trust {
                        Text(trust.uppercased()).font(V8Font.mono(8)).tracking(0.7).foregroundStyle(sub)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay(Rectangle().stroke(sub.opacity(0.7), lineWidth: 0.8))
                    }
                    if !reason.isEmpty {
                        Text(reason).font(V8Font.text(12.5)).foregroundStyle(sub).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(main).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(fill)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(big) \(unit). \(reason)\(trust.map { ". \($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

extension HojeIndexRow {
    /// Linha do "Agora vale": distância ou hora grande, nome e o motivo (`SuggestionReason`).
    init(card: Suggestion, action: @escaping () -> Void) {
        let tone: Tone
        switch card.kind {
        case .must, .closing, .gift: tone = .orange
        case .event, .indicated: tone = .ink
        case .plan, .light, .rain: tone = .paper
        }
        var big = "·", unit = card.kind == .rain ? "chuva" : "agora"
        if let trailing = card.trailing {
            let parts = trailing.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2 { big = parts[0]; unit = parts[1] == "m" ? "metros" : parts[1] } else { big = trailing; unit = "" }
        } else if card.kind == .plan, let range = card.meta.range(of: #"\d{1,2}[:h]\d{2}"#, options: .regularExpression) {
            big = String(card.meta[range]); unit = "agora"
        }
        self.init(tone: tone, big: big, unit: unit, title: card.title, reason: SuggestionReason.line(card),
                  trust: card.trust, action: action)
    }
}

/// Botão de ponta a ponta no papel (Montar o dia): tinta cheia, mono caixa alta.
struct HojeWideButton: View {
    var title: String
    var filled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title.uppercased()).font(V8Font.mono(14, weight: .semibold)).tracking(1.2).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(filled ? V8.paper : V8.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(filled ? V8.ink : Color.clear)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { IndexRule() }
    }
}
