import SwiftUI

// Peças da tela Compras (V9): ícone de cada categoria, a linha do item, a regra.

extension ShoppingCategory {
    /// Cor da categoria: neutra no V9 (a cor só aparece como ponto de ação e "agora").
    var tint: (light: Color, strong: Color) { (Color(uiColor: .tertiarySystemFill), Color.secondary) }

    /// Ícone do set do Must quando existe; senão um SF Symbol (fallback do design/icons/README.md).
    var icon: MustIcon? {
        switch self {
        case .cameras: .cameraFoto
        case .food: .doceKonbini
        case .clothes: .roupa
        case .other: .compras
        default: nil
        }
    }

    var systemName: String {
        switch self {
        case .tech: "iphone"
        case .gifts: "gift"
        case .pharmacy: "cross.case"
        case .home: "house"
        default: "bag"
        }
    }
}

/// Ícone da categoria (o set do Must ou o SF Symbol de reserva), na cor forte.
struct ShoppingIcon: View {
    var category: ShoppingCategory
    var size: CGFloat = 26
    var color: Color?

    var body: some View {
        Group {
            if let icon = category.icon {
                MustIconView(icon, size: size)
            } else {
                Image(systemName: category.systemName).font(.system(size: size * 0.9, weight: .regular))
            }
        }
        .foregroundStyle(color ?? category.tint.strong)
    }
}

/// Linha de um item (V9): ícone da categoria, nome, loja/bairro, preço em número tabular e o status em texto.
struct ShoppingItemCard: View {
    var item: ShoppingItem
    var storeName: String
    /// Moeda do item: o preço aparece na moeda que foi anotado (¥ ou R$), não na da região.
    var currency: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ShoppingIcon(category: item.category, size: 24, color: .secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if !meta.isEmpty { Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    Text(statusText).font(.footnote).foregroundStyle(item.isBought ? Color.secondary : V9.accent)
                }
                Spacer(minLength: 8)
                Text(ShoppingReport.money(item.committedAmount, currency: currency))
                    .font(.body.monospacedDigit()).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch item.status {
        case .want: "quero"
        case .mustHave: "quero muito"
        case .bought: "comprado"
        }
    }

    private var meta: String {
        let place = [storeName, item.area ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        if item.isBought { return place.isEmpty ? "na mão" : "\(place) · na mão" }
        return place
    }
}

/// Regra na seção "Comidinhas pra levar": ícone + texto (ok, atenção ou não passa); só o vermelho do sistema chama atenção.
struct ShoppingRuleChip: View {
    var text: String
    var tone: ShoppingTone

    var body: some View {
        Label {
            Text(text).font(.body).foregroundStyle(tone == .no ? Color.red : Color.primary).lineLimit(3)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone == .no ? Color.red : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(text + (tone == .ok ? ", passa" : tone == .warn ? ", atenção" : ", não passa"))
    }

    private var symbol: String {
        switch tone {
        case .ok: "checkmark.circle"
        case .warn: "exclamationmark.circle"
        case .no: "xmark.circle.fill"
        }
    }
}
