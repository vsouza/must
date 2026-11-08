import SwiftUI

// Peças da tela Compras (prompt 17 · B): cor e ícone de cada categoria, o card horizontal, o chip de regra.

extension ShoppingCategory {
    /// Cor da categoria na fileira e no card: claro → forte (a mesma escala dos Musts).
    var tint: (light: Color, strong: Color) {
        switch self {
        case .cameras: (Color(hex: 0xE9EBEF), Color(hex: 0x121316))
        case .food: (Color(hex: 0xFFD27A), Color(hex: 0xFFB020))
        case .tech: (Color(hex: 0x9FD6FF), Color(hex: 0x2B7BFF))
        case .gifts: (Color(hex: 0xFFB3CF), Color(hex: 0xFF4D8D))
        case .pharmacy: (Color(hex: 0xB8F2EA), Color(hex: 0x14B8A6))
        case .home: (Color(hex: 0xB9F5CF), Color(hex: 0x22DD7E))
        case .clothes: (Color(hex: 0xDCCFFF), Color(hex: 0x8B5CF6))
        case .other: (Color(hex: 0xE9EBEF), Color(hex: 0x8A94A6))
        }
    }

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

/// Bloco de cor da categoria (a "miniatura" do item, sem foto nesta fatia).
struct ShoppingTile: View {
    var category: ShoppingCategory
    var size: CGFloat

    var body: some View {
        Rectangle()
            .fill(category == .cameras ? V8.ink : category.tint.strong)
            .frame(width: size, height: size)
            .overlay {
                ShoppingIcon(category: category, size: size * 0.45, color: .white)
            }
    }
}

/// Card horizontal de um item (150 pt): bloco de cor, tag de status, nome, loja e preço em mono.
struct ShoppingItemCard: View {
    var item: ShoppingItem
    var storeName: String
    /// Moeda do item: o preço aparece na moeda que foi anotado (¥ ou R$), não na da região.
    var currency: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    item.category.tint.light.opacity(0.45)
                    ShoppingIcon(category: item.category, size: 34)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    statusTag.padding(8)
                }
                .frame(height: 80)
                .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.must.archivo(17, .semibold)).foregroundStyle(Color.must.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(meta).font(.must.archivo(13)).foregroundStyle(Color.must.secondary).lineLimit(1)
                    Text(ShoppingReport.money(item.committedAmount, currency: currency))
                        .font(.must.mono(15, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 150, alignment: .topLeading)
            .background(Color.must.surface2, in: Rectangle())
            .contentShape(Rectangle())
        }
        .buttonStyle(MustPressStyle())
    }

    @ViewBuilder private var statusTag: some View {
        switch item.status {
        case .want: Tag("quero")
        case .mustHave: Tag("quero muito", style: .dark)
        case .bought: Tag("comprado", style: .green)
        }
    }

    private var meta: String {
        let place = [storeName, item.area ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        if item.isBought { return place.isEmpty ? "na mão" : "\(place) · na mão" }
        return place
    }
}

/// Chip de regra na seção "Comidinhas pra levar": verde (ok), âmbar (atenção) ou vermelho (não passa).
struct ShoppingRuleChip: View {
    var text: String
    var tone: ShoppingTone

    var body: some View {
        Text(text)
            .font(.must.archivo(13, .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(background, in: Rectangle())
    }

    private var foreground: Color {
        switch tone {
        case .ok: Color(hex: 0x0B2A18)
        case .warn: Color(hex: 0x4A2E00)
        case .no: Color(hex: 0x5A1A0E)
        }
    }

    private var background: Color {
        switch tone {
        case .ok: MustColor.eat.light
        case .warn: Color(hex: 0xFFE3A3)
        case .no: MustColor.sport.light
        }
    }
}
