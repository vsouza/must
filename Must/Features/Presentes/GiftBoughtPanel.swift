import SwiftData
import SwiftUI

/// Painel "Comprado" (V9, material do sistema): pede o valor pago, mostra
/// que entra em Gastos e na cota tax-free da loja. Desfazer reverte gasto e estado; Ok grava o valor.
struct GiftBoughtPanel: View {
    var gift: Gift
    var gifts: [Gift]
    var region: Region
    var money: GiftMoney
    var storeName: String
    var onUndo: () -> Void
    var onOk: () -> Void

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @FocusState private var focused: Bool

    private var amount: Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? gift.estimatedTotal }

    private var taxFree: GiftLogic.TaxFree? {
        GiftLogic.taxFree(for: gift, among: gifts, on: gift.boughtAt ?? AppClock.now, calendar: region.calendar,
                          currency: region.currency, extra: amount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comprado\(gift.personName == GiftLogic.noPerson ? "" : " · pra \(gift.personName)")\(storeName.isEmpty ? "" : " · \(storeName)")")
                .font(.headline).lineLimit(2)
            Text("Quanto pagou? (previsto \(money.text(gift.estimatedTotal)))").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MoneyFormatStyle.symbol(for: region.currency)).font(.title2).foregroundStyle(.secondary)
                TextField("", text: $text)
                    .font(.title.weight(.semibold).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .accessibilityLabel("Valor pago")
                Spacer(minLength: 4)
                if let brl = money.brl(amount) {
                    Text(brl).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Divider()
            infoCard("Gastos", "entra no dia \(dayNumber) · categoria compras")
            if let taxFree {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tax-free").font(.subheadline.weight(.semibold))
                    Text(taxFree.reached
                         ? "\(money.text(taxFree.spent)) nessa loja hoje · vale"
                         : "\(money.text(taxFree.spent)) de \(money.text(taxFree.minimum)) nessa loja hoje")
                        .font(.footnote).foregroundStyle(.secondary)
                    ProgressView(value: min(1, max(0, taxFree.fraction))).tint(V9.accent)
                }
            }
            Text("Foto do recibo: opcional, fica no aparelho.").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Desfazer", action: onUndo).v9Secondary()
                Button("Ok") {
                    GiftLogic.setPaid(gift, to: amount, context: context)
                    onOk()
                }
                .v9Primary()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
        .padding(.horizontal, V9.gutter)
        .padding(.bottom, 8)
        .onAppear {
            text = (gift.paidPrice ?? gift.estimatedTotal).formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        }
        .accessibilityElement(children: .contain)
    }

    private var dayNumber: Int { region.calendar.component(.day, from: gift.boughtAt ?? AppClock.now) }

    private func infoCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
