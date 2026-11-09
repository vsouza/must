import SwiftData
import SwiftUI

/// Ajustes › Dados: "105 lugares · 94 confirmados" (relatório do viajante, problema 3). Mostra quantos lugares do board têm
/// horário e coordenada de verdade e dispara a sincronização que já existe (`syncPlaces`, dentro do `ApiBudget`), só no Wi-Fi.
struct TrustSyncRows: View {
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Query private var places: [Place]

    var body: some View {
        let confidence = BoardConfidence(places)
        let wifi = services.connectivity.isWiFi
        let syncing = services.sync.isSyncingPlaces
        Button {
            Task { await services.sync.syncPlaces(context: context, region: store.region) }
        } label: {
            LabeledContent {
                if let progress = services.sync.placesProgress {
                    Text("\(progress.done)/\(progress.total)").monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(confidence.isComplete ? "ok" : "sincronizar").foregroundStyle(.secondary)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(confidence.headline)
                    Text(confidence.detail(onWiFi: wifi)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(syncing || confidence.isComplete || !wifi)
        .accessibilityHint("Busca horário e local no Google, só no Wi-Fi")
    }
}
