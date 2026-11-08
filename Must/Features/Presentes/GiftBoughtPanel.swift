import SwiftData
import SwiftUI

/// Painel "Comprado" (`Presentes-Comprado.png`): faixa de tinta com filete laranja de 12 pt em cima, pede o valor pago, mostra
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
        VStack(spacing: 0) {
            Rectangle().fill(V8.orange).frame(height: 12)
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel("comprado\(gift.personName == GiftLogic.noPerson ? "" : " · pra \(gift.personName)")\(storeName.isEmpty ? "" : " · \(storeName)")",
                          size: 11, color: V8.white)
                    .lineLimit(2)
                    .padding(.top, 20)
                MonoLabel("quanto pagou? (previsto \(money.text(gift.estimatedTotal)))", size: 10, color: V8.muteDark).padding(.top, 14)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(MoneyFormatStyle.symbol(for: region.currency))
                        .font(V8Font.mono(34, weight: .semibold)).foregroundStyle(V8.white)
                    TextField("", text: $text)
                        .font(V8Font.mono(46, weight: .semibold))
                        .foregroundStyle(V8.white)
                        .tint(V8.orange)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel("Valor pago")
                    Spacer(minLength: 4)
                    if let brl = money.brl(amount) {
                        Text(brl).font(V8Font.text(15)).foregroundStyle(V8.muteDark).lineLimit(1)
                    }
                }
                .padding(.top, 6)
                Rectangle().fill(V8.white).frame(height: 2)
                HStack(alignment: .top, spacing: 12) {
                    infoCard("Gastos", "entra no dia \(dayNumber) · categoria compras")
                    if let taxFree {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tax-free").font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.white)
                            Text(taxFree.reached
                                 ? "\(money.text(taxFree.spent)) nessa loja hoje · vale"
                                 : "\(money.text(taxFree.spent)) de \(money.text(taxFree.minimum)) nessa loja hoje")
                                .font(V8Font.text(13)).foregroundStyle(V8.white)
                                .fixedSize(horizontal: false, vertical: true)
                            ZStack(alignment: .leading) {
                                Rectangle().stroke(V8.graphite, lineWidth: 2)
                                GeometryReader { geo in
                                    Rectangle().fill(V8.orange).frame(width: geo.size.width * taxFree.fraction).padding(3)
                                }
                            }
                            .frame(height: 16)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .overlay(Rectangle().stroke(V8.graphite, lineWidth: 2))
                    }
                }
                .padding(.top, 16)
                MonoLabel("foto do recibo: opcional · no aparelho", size: 9, color: V8.muteDark).padding(.top, 14).padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .background(V8.ink)
            HStack(spacing: 0) {
                Button(action: onUndo) {
                    Text("Desfazer").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                        .frame(maxWidth: .infinity, minHeight: 58).background(V8.paper).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    GiftLogic.setPaid(gift, to: amount, context: context)
                    onOk()
                } label: {
                    Text("Ok").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                        .frame(maxWidth: .infinity, minHeight: 58).background(V8.orange).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(V8.ink)
        }
        .onAppear {
            text = (gift.paidPrice ?? gift.estimatedTotal).formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        }
        .accessibilityElement(children: .contain)
    }

    private var dayNumber: Int { region.calendar.component(.day, from: gift.boughtAt ?? AppClock.now) }

    private func infoCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.white)
            Text(body).font(V8Font.text(13)).foregroundStyle(V8.white).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(Rectangle().stroke(V8.graphite, lineWidth: 2))
    }
}
