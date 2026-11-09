import SwiftUI

/// Peças V9 usadas pelas telas da aba Viagem e da entrada de dados (prompt 32, Fase 2 · J). Mesmos formatos das peças
/// do V8 (`FormSection`, `FormRow`, `Pill`, `CutPage`, `CutSheet`), mas com fundos e texto do sistema, Dynamic Type e
/// modo escuro. Se virarem úteis a mais gente, o orquestrador promove pro `V9.swift`.

/// Seção em cartão arredondado (como o grupo de Ajustes do iOS), com título pequeno em cima e rodapé opcional.
struct J9Section<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                    .padding(.horizontal, V9.gutter).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, V9.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(V9.groupedCard, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, V9.gutter)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 8)
    }
}

/// Linha título + detalhe + acessório à direita.
struct J9Row<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var titleColor: Color = .primary
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, titleColor: Color = .primary, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension J9Row where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleColor: Color = .primary) {
        self.init(title, subtitle: subtitle, titleColor: titleColor) { EmptyView() }
    }
}

struct J9Divider: View {
    var body: some View { Divider() }
}

/// Valor à direita (números tabulares), com chevron opcional.
struct J9Value: View {
    var text: String
    var chevron = false
    var color: Color = .secondary

    init(_ text: String, chevron: Bool = false, color: Color = .secondary) {
        self.text = text
        self.chevron = chevron
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.body).monospacedDigit().foregroundStyle(color).lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Status com ponto: "● ligado".
struct J9Status: View {
    var text: String
    var on: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(on ? V9.accent : Color.secondary).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Chip de filtro/opção (substitui `Pill`): cápsula; selecionada ou principal = acento.
struct J9Chip: View {
    var text: String
    var isOn = false
    var prominent = false
    var systemImage: String?

    init(_ text: String, isOn: Bool = false, prominent: Bool = false, systemImage: String? = nil) {
        self.text = text
        self.isOn = isOn
        self.prominent = prominent
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(text).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOn || prominent ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(isOn || prominent ? V9.accent : V9.fill, in: Capsule())
        .contentShape(Capsule())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Tela empurrada: título na barra nativa (volta nativo), conteúdo rolável sobre o fundo agrupado.
struct J9Page<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    /// `corner` e `height` existem só pra receber as chamadas antigas do `CutPage`; `corner` vira o subtítulo se faltar.
    init(title: String, corner: [String] = [], subtitle: String? = nil, height: CGFloat = 0, onBack: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle ?? (corner.isEmpty ? nil : corner.joined(separator: " · "))
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, V9.gutter * 2).padding(.top, 4)
                }
                content
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen(grouped: true)
    }
}

/// Folha de edição: NavigationStack própria, "Fechar" na barra, conteúdo rolável e botão principal embaixo.
struct J9Sheet<Content: View>: View {
    var title: String
    var subtitle: String?
    var footer: String?
    var footerEnabled = true
    var footerId: String?
    var onFooter: () -> Void = {}
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    content
                }
                .padding(V9.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { if let onClose { onClose() } else { dismiss() } }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let footer {
                    Button(action: onFooter) { Text(footer).frame(maxWidth: .infinity) }
                        .v9Primary()
                        .disabled(!footerEnabled)
                        .padding(V9.gutter)
                        .background(.bar)
                        .accessibilityIdentifier(footerId ?? "sheet.footer")
                }
            }
            .v9Screen(grouped: true)
        }
    }
}

/// Campo com rótulo em cima (substitui `CutBox`).
struct J9Field<Content: View>: View {
    var label: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { Text(label).font(.footnote).foregroundStyle(.secondary) }
            content
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
