import SwiftUI

/// Ajustes › Dados › Uso do Google: o contador do mês por SKU (`ApiBudget`), o teto diário e o corte de 80%.
struct GoogleUsageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store

    var body: some View {
        // Relê a cada render: os números mudam quando uma chamada sai.
        let now = AppClock.now
        ZStack(alignment: .top) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 344, cy: 110, rx: 90, ry: 52, rotation: 12, fill: .blue),
                Blob(cx: 46, cy: 800, rx: 70, ry: 60, rotation: -8, fill: .green),
            ]))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        IconButton(.voltar, label: "Voltar") { dismiss() }
                        Spacer()
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Uso do Google").mustTitle()
                        Text("o que o Must gasta na API, por SKU").mustSerif(18).foregroundStyle(Color.must.secondary)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                    dailyCap(now)
                    monthly(now)

                    Text("Cota grátis do mês · corte automático em 80% · 403 da API marca a SKU como indisponível até amanhã (sem erro na tela)")
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
