import SwiftUI

// Peças das telas de Presentes (prompt 31 · item 7, `design/v9/Presentes-*.png`): botão quadrado dos cantos, valores em moeda
// da viagem + R$, a caixa do checklist e a faixa "seus presentes" do quero.

/// Botão quadrado de 40 pt, borda de 2 pt, sem raio (cantos fixos do v9: ← ✕ ✦).
struct GiftSquareButton: View {
    var systemName: String
    var label: String
    var onInk = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onInk ? V8.white : V8.ink)
                .frame(width: 40, height: 40)
                .overlay(Rectangle().stroke(onInk ? V8.white : V8.ink, lineWidth: 2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Valores da lista: moeda da viagem e a conversão em R$ (câmbio de Ajustes).
struct GiftMoney {
    var region: Region
    var userRate: Double?

    /// "¥ 41.300".
    func text(_ amount: Double) -> String { region.money(amount) }

    /// R$ por unidade da moeda da viagem; `nil` quando a viagem já é em R$.
    var brlRate: Double? {
        region.currency == "BRL" ? nil : ShoppingFX.baseRate(for: region, userRate: userRate)
    }

    /// "≈ R$ 1.480" (sem conversão em viagem em R$).
    func brl(_ amount: Double) -> String? {
        guard let rate = brlRate else { return nil }
        return "≈ " + (amount * rate).formatted(.money("BRL"))
    }
}

/// A caixa do checklist: círculo do sistema (marcado = ✓ cheio). É um botão "Marcar comprado", alvo de 44 pt.
struct GiftCheckbox: View {
    var done: Bool
    var onInk = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? V9.accent : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Comprado" : "Marcar comprado")
        .accessibilityAddTraits(.isButton)
    }
}

/// "pra Ana · 450 m" (a ordem do quero e da capa).
enum GiftCopy {
    static func reason(_ nearby: GiftNearby) -> String {
        let who = nearby.person.isEmpty ? "" : " pra \(nearby.person)"
        return "\(GiftLogic.titleWithQtyText(nearby.title, nearby.quantity))\(who)"
    }
}

extension GiftLogic {
    static func titleWithQtyText(_ title: String, _ quantity: Int) -> String { quantity > 1 ? "\(title) × \(quantity)" : title }
}
