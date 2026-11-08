import SwiftUI

/// Ajustes › Dados › Uso do Google: o contador do mês por SKU (`ApiBudget`), o teto diário e o corte de 80%.
struct GoogleUsageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store

    var body: some View {
        // Relê a cada render: os números mudam quando uma chamada sai.
        let now = AppClock.now
        CutPage(title: "Uso do Google", corner: ["Ajustes · dados"], subtitle: "O que o Must gasta na API, por SKU",
                height: 200, onBack: { dismiss() }) {
            dailyCap(now)
            monthly(now)
            Text("Cota grátis do mês · corte automático em 80% · 403 da API marca a SKU como indisponível até amanhã (sem erro na tela)")
                .font(V8Font.text(13))
                .foregroundStyle(V8.mute)
                .padding(20)
        }
    }

    private func dailyCap(_ now: Date) -> some View {
        let cap = ApiBudget.dailyCap()
        return FormSection("Teto diário") {
            Menu {
                Picker("Teto diário", selection: Binding(get: { ApiBudget.dailyCap() }, set: { ApiBudget.setDailyCap($0) })) {
                    ForEach(ApiBudget.dailyCapOptions, id: \.self) { Text(cap == 0 ? "0 · desligado" : "\($0)").tag($0) }
                }
            } label: {
                FormRow("Chamadas por dia", subtitle: cap == 0 ? "0 · nada sai pro Google; a tela cai no cache e na estimativa"
                        : "somadas, todas as SKUs · hoje \(ApiBudget.usedToday(now: now)) de \(cap)") {
                    MonoValue("\(cap)", chevron: true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func monthly(_ now: Date) -> some View {
        FormSection("Mês de \(ApiBudget.monthKey(now))") {
            ForEach(Array(GoogleSKU.allCases.enumerated()), id: \.element.id) { index, sku in
                if index > 0 { RowDivider() }
                row(sku, now: now)
            }
        }
    }

    private func row(_ sku: GoogleSKU, now: Date) -> some View {
        let used = ApiBudget.used(sku, now: now)
        let status: (text: String, color: Color) = {
            if ApiBudget.isUnavailable(sku, now: now) { return ("indisponível hoje", Color(hex: 0xC2261D)) }
            guard let free = sku.freeMonthly else { return ("sem limite", Color.must.green) }
            if Double(used) >= Double(free) * ApiBudget.cutFraction { return ("cortado em 80%", Color(hex: 0xC2261D)) }
            return ("grátis", Color.must.green)
        }()
        return FormRow(sku.label, subtitle: "\(sku.detail) · \(status.text)") {
            MonoValue(sku.freeMonthly.map { "\(used) / \($0)" } ?? "\(used)", color: status.color == Color.must.green ? Color.must.ink : status.color)
        }
    }
}
