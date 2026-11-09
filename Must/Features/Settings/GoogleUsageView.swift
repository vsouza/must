import SwiftUI

/// Ajustes › Dados › Uso do Google: o contador do mês por SKU (`ApiBudget`), o teto diário e o corte de 80%.
struct GoogleUsageView: View {
    @Environment(RegionStore.self) private var store

    var body: some View {
        // Relê a cada render: os números mudam quando uma chamada sai.
        let now = AppClock.now
        Form {
            dailyCap(now)
            monthly(now)
            Section {} footer: {
                Text("Cota grátis do mês · corte automático em 80% · 403 da API marca a SKU como indisponível até amanhã (sem erro na tela)")
            }
        }
        .navigationTitle("Uso do Google")
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
    }

    private func dailyCap(_ now: Date) -> some View {
        let cap = ApiBudget.dailyCap()
        return Section("Teto diário") {
            Picker(selection: Binding(get: { ApiBudget.dailyCap() }, set: { ApiBudget.setDailyCap($0) })) {
                ForEach(ApiBudget.dailyCapOptions, id: \.self) { Text($0 == 0 ? "0 · desligado" : "\($0)").tag($0) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chamadas por dia")
                    Text(cap == 0 ? "0 · nada sai pro Google; a tela cai no cache e na estimativa"
                         : "somadas, todas as SKUs · hoje \(ApiBudget.usedToday(now: now)) de \(cap)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func monthly(_ now: Date) -> some View {
        Section("Mês de \(ApiBudget.monthKey(now))") {
            ForEach(GoogleSKU.allCases) { sku in row(sku, now: now) }
        }
    }

    private func row(_ sku: GoogleSKU, now: Date) -> some View {
        let used = ApiBudget.used(sku, now: now)
        let status: (text: String, alert: Bool) = {
            if ApiBudget.isUnavailable(sku, now: now) { return ("indisponível hoje", true) }
            guard let free = sku.freeMonthly else { return ("sem limite", false) }
            if Double(used) >= Double(free) * ApiBudget.cutFraction { return ("cortado em 80%", true) }
            return ("grátis", false)
        }()
        return LabeledContent {
            Text(sku.freeMonthly.map { "\(used) / \($0)" } ?? "\(used)").monospacedDigit()
                .foregroundStyle(status.alert ? Color.red : Color.secondary)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(sku.label)
                Text("\(sku.detail) · \(status.text)").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
