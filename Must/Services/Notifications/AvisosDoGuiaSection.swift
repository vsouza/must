import SwiftData
import SwiftUI

/// Ajustes › Avisos do guia (prompt 23 §4): o app fala sozinho com 4 avisos locais (nunca push), no máximo um a cada
/// 45 min, e a Live Activity do "saia às". Cada aviso liga/desliga aqui; mudar recalcula os pendentes na hora.
/// O orquestrador põe esta seção no lugar do toggle único "Avisos do guia" de `SettingsView`.
struct AvisosDoGuiaSection: View {
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @AppStorage(GuideNudgeScheduler.enabledKey) private var all = true
    @AppStorage(GuideNudgeScheduler.key(.morning)) private var morning = true
    @AppStorage(GuideNudgeScheduler.key(.leave)) private var leave = true
    @AppStorage(GuideNudgeScheduler.key(.golden)) private var golden = true
    @AppStorage(GuideNudgeScheduler.key(.lastTrain)) private var lastTrain = true
    @AppStorage(GuideNudgeScheduler.key(.opens)) private var opens = true

    var body: some View {
        FormSection("Avisos do guia") {
            row($all, "Avisos do guia", "só no aparelho · no máx. 1 a cada 45 min")
            if all {
                RowDivider()
                row($morning, "Bom dia", "07:20 · o bairro de hoje e a primeira parada")
                RowDivider()
                row($leave, "Saia em 5 min", "pra próxima parada · com a Live Activity")
                RowDivider()
                row($golden, "Golden em 20 min", "quando o dia tem foto no golden")
                RowDivider()
                row($lastTrain, "Último trem", "50 min antes · ou 23:50")
                RowDivider()
                row($opens, "Abre agora", "quando um lugar do dia abre depois que você saiu")
            }
        }
        .onChange(of: [all, morning, leave, golden, lastTrain, opens]) { _, _ in reschedule() }
    }

    private func row(_ value: Binding<Bool>, _ title: String, _ subtitle: String) -> some View {
        Toggle(isOn: value) { FormRow(title, subtitle: subtitle) }
            .toggleStyle(.must)
    }

    private func reschedule() {
        let region = store.region
        let origin = services.location.current?.coordinate
        let context = context
        Task {
            if all {
                await GuideNudgeScheduler.refresh(context: context, region: region, origin: origin, askPermission: false)
            } else {
                await GuideNudgeScheduler.disable()
            }
        }
    }
}
