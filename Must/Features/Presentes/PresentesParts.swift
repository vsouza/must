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

/// A caixa do checklist: 22 pt, borda de 2 pt; marcada = tinta cheia com ✓. É um botão "Marcar comprado".
struct GiftCheckbox: View {
    var done: Bool
    var onInk = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle().fill(done ? (onInk ? V8.orange : V8.ink) : Color.clear)
                Rectangle().stroke(onInk ? V8.white : V8.ink, lineWidth: 2)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(onInk ? V8.ink : V8.white)
                }
            }
            .frame(width: 22, height: 22)
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

/// A faixa laranja do quero "presente": os presentes pendentes com a loja mais perto, a qualquer distância na cidade de hoje.
struct GiftWantBand: View {
    var rows: [GiftNearby]
    var onGo: (GiftNearby) -> Void
    var onOpen: (GiftNearby) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel("seus presentes · \(rows.count)", size: 10, color: V8.ink)
                Spacer(minLength: 8)
                MonoLabel("dá pra comprar aqui", size: 10, color: V8.ink)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(V8.orange)
            ForEach(rows) { row in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Walk.distanceText(row.meters))
                            .font(V8Font.mono(22, weight: .semibold)).foregroundStyle(V8.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(row.minutes) MIN A PÉ").font(V8Font.mono(8.5)).tracking(0.6).foregroundStyle(V8.ink.opacity(0.75)).lineLimit(1)
                    }
                    .frame(width: 84, alignment: .leading)
                    Button { onOpen(row) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.storeName).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                            Text(GiftCopy.reason(row)).font(V8Font.text(12)).foregroundStyle(V8.ink.opacity(0.75)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { onGo(row) } label: {
                        Text("IR").font(V8Font.mono(10, weight: .semibold)).tracking(0.8).foregroundStyle(V8.ink)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(minHeight: 64)
                .background(V8.orange.opacity(0.9))
                .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
