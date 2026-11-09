import SwiftUI
import UIKit

/// V9 · visual calmo (prompt 32 §5, 09/11/2026). Fundos e texto do sistema, modo escuro, um acento laranja
/// dessaturado só em ação e "agora", SF Pro com Dynamic Type, materiais do sistema. Sem trama, arcos, régua preta,
/// numeral gigante nem sombra desenhada à mão. O V8 continua existindo pros prints antigos até a Fase 2 limpar.
enum V9 {
    /// Acento único (ação e "agora"): #D9572B no claro, #F07A4E no escuro. É o `.tint` do app.
    /// Nunca fundo de tela inteira; no máximo botão primário, ponto do "agora" e pino selecionado.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(v9Hex: 0xF07A4E) : UIColor(v9Hex: 0xD9572B)
    })
    /// Alerta (SOS, atraso): o vermelho do sistema.
    static let alert = Color.red

    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    /// Cartão sobre `.systemBackground`.
    static let card = Color(uiColor: .secondarySystemBackground)
    /// Cartão sobre `.systemGroupedBackground`.
    static let groupedCard = Color(uiColor: .secondarySystemGroupedBackground)
    /// Fundo de campo (o "Pedir algo…" e chips).
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)

    static let cornerRadius: CGFloat = 14
    /// Miniatura de lugar/bairro nas linhas (nunca foto como fundo de texto).
    static let thumb: CGFloat = 56
    static let gutter: CGFloat = 16
}

extension UIColor {
    convenience init(v9Hex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Tela

extension View {
    /// Raiz de uma tela V9: fonte do sistema (o app ainda usa a Schibsted como padrão por causa do V8), fundo do sistema,
    /// esquema de cor do aparelho. Use em toda tela convertida, no lugar do `.v8Legacy()`.
    func v9Screen(grouped: Bool = false) -> some View {
        self
            .font(.body)
            .fontDesign(.default)
            .background((grouped ? V9.groupedBackground : V9.background).ignoresSafeArea())
    }

    /// Cartão V9: `.secondarySystemBackground`, raio contínuo do sistema, sem sombra.
    func v9Card(padding: CGFloat = 16, grouped: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(grouped ? V9.groupedCard : V9.card, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
    }

    /// Botão primário (o único com o acento cheio na tela).
    func v9Primary() -> some View {
        self.buttonStyle(.borderedProminent).controlSize(.large).tint(V9.accent)
    }

    /// Botão secundário.
    func v9Secondary() -> some View {
        self.buttonStyle(.bordered).controlSize(.large)
    }
}

// MARK: - Componentes

/// Campo "Pedir algo…" com cara de campo de busca do sistema, que abre o Quero por **toque** (prompt 32 §1:
/// nada de régua puxável). É um botão: o teclado abre na tela do Quero.
struct V9AskField: View {
    var prompt: String = "Pedir algo…"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(prompt).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .font(.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt.replacingOccurrences(of: "…", with: ""))
        .accessibilityHint("Abre o Quero")
    }
}

/// Título de seção: `.headline`, com ação opcional à direita ("ver o dia").
struct V9SectionHeader: View {
    var title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline)
            }
        }
    }
}

/// Linha de lugar V9: miniatura opcional de 56 pt, nome, detalhe (distância/tempo, monoespaçado nos números) e o
/// **motivo** em uma linha ("seu Must · aberto até 22h · 6 min"). Conteúdo à direita opcional (botão Ir, chevron).
struct V9Row<Trailing: View>: View {
    var title: String
    var detail: String?
    var reason: String?
    var thumbnail: AnyView?
    var systemImage: String?
    var dimmed = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let thumbnail {
                thumbnail.frame(width: V9.thumb, height: V9.thumb)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3).foregroundStyle(.secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).lineLimit(2)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
                if let reason { Text(reason).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .opacity(dimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension V9Row where Trailing == EmptyView {
    init(title: String, detail: String? = nil, reason: String? = nil, thumbnail: AnyView? = nil, systemImage: String? = nil, dimmed: Bool = false) {
        self.init(title: title, detail: detail, reason: reason, thumbnail: thumbnail, systemImage: systemImage, dimmed: dimmed) { EmptyView() }
    }
}

/// Faixa discreta com uma ação e "dispensar": "Você chegou em Nakano · ver perto", Bom dia / Boa noite.
/// Toque na faixa = ação; ✕ = dispensar. Nunca troca nada sozinha.
struct V9Notice: View {
    var systemImage: String
    var text: String
    var actionTitle: String
    var action: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage).foregroundStyle(V9.accent).accessibilityHidden(true)
                    Text(text).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(actionTitle).fontWeight(.semibold).foregroundStyle(V9.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(text). \(actionTitle)")
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dispensar")
        }
        .font(.subheadline)
        .padding(.leading, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
    }
}

/// "sem internet · offline ok" (CLAUDE.md, premissa: offline é estado normal, não erro). Só aparece sem rede.
struct V9OfflineChip: View {
    @Environment(Services.self) private var services: Services?

    var body: some View {
        if services?.connectivity.status == .offline {
            Label("sem internet · offline ok", systemImage: "wifi.slash")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(V9.fill, in: Capsule())
                .accessibilityLabel("Sem internet. O app funciona offline com o que já está no aparelho.")
        }
    }
}
