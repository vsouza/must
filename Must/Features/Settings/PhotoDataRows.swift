import SwiftData
import SwiftUI

/// Ajustes › Dados (premissa de dados, prompt 19 · item 5): MB do mês (celular × Wi-Fi), o cache de fotos
/// com limpeza, e "Baixar fotos dos lugares" com contador, pausa e a chave "só no Wi-Fi".
struct PhotoDataRows: View {
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context

    @State private var cacheBytes: Int64?
    @State private var eligible = 0
    @State private var wifiOnly = PhotoBatch.wifiOnly

    private var batch: PhotoBatch { services.photoBatch }

    var body: some View {
        let now = AppClock.now
        Group {
            LabeledContent {
                Text(dataLine(now)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            } label: { row("Dados no mês", "o que o app baixou · sem o cache do sistema") }
            LabeledContent {
                HStack(spacing: 10) {
                    Text(cacheBytes.map(Self.size) ?? "…").foregroundStyle(.secondary).monospacedDigit()
                    Button("Limpar") {
                        PlacePhotoStore.clear()
                        Task { await refreshCache() }
                    }
                    .buttonStyle(.borderless)
                }
            } label: { row("Fotos em cache", "30 dias sem uso · teto de 300 MB, o que sai primeiro é o menos usado") }
            batchButton(now)
            Toggle(isOn: $wifiOnly) {
                row("Baixar só no Wi-Fi", "no celular, só a foto do lugar aberto · Modo de Pouco Dados nunca baixa")
            }
            .onChange(of: wifiOnly) { _, on in PhotoBatch.wifiOnly = on }
        }
        .task { await refreshCache() }
        .task(id: batch.done) { refreshEligible() }
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Lote

    private func batchButton(_ now: Date) -> some View {
        Button(action: toggleBatch) {
            LabeledContent {
                Text(batchLabel).foregroundStyle(V9.accent)
            } label: { row("Baixar fotos dos lugares", batchSubtitle(now)) }
        }
        .foregroundStyle(.primary)
        .disabled(batch.state == .done || (batch.state == .idle && eligible == 0))
    }

    private var batchLabel: String {
        switch batch.state {
        case .idle: "Baixar"
        case .running: "Pausar"
        case .paused: "Continuar"
        case .waitingNetwork: "Espera o Wi-Fi"
        case .stopped: "Continuar"
        case .done: "Concluído"
        }
    }

    /// "84 de 130 · usa 84 da cota de 1.000 do mês" (o contador do prompt 19).
    private func batchSubtitle(_ now: Date) -> String {
        let used = ApiBudget.used(.placePhotos, now: now)
        let quota = GoogleSKU.placePhotos.freeMonthly ?? 1_000
        switch batch.state {
        case .stopped(let why):
            return "\(batch.done) de \(batch.total) · parou: \(why) · continua amanhã"
        case .waitingNetwork:
            return "\(batch.done) de \(batch.total) · esperando Wi-Fi · usa \(used) da cota de \(quota) do mês"
        case .idle, .done:
            let base = batch.state == .done ? "\(batch.total) de \(batch.total)" : "\(eligible) lugares com foto no Google"
            return "\(base) · usa \(used) da cota de \(quota) do mês"
        case .running, .paused:
            return "\(batch.done) de \(batch.total) · usa \(used) da cota de \(quota) do mês"
        }
    }

    private func toggleBatch() {
        switch batch.state {
        case .running, .waitingNetwork: batch.pause()
        case .paused: batch.resume()
        case .idle, .stopped, .done:
            let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
            batch.start(places: places, context: context, network: { services.connectivity.prefetchNetwork })
        }
    }

    private func refreshEligible() {
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        eligible = PhotoBatch.queue(places).count
    }

    // MARK: Medidas

    private func dataLine(_ now: Date) -> String {
        "\(Self.size(DataUsage.used(.cellular, now: now))) celular · \(Self.size(DataUsage.used(.wifi, now: now))) Wi-Fi"
    }

    private func refreshCache() async {
        cacheBytes = await Task.detached(priority: .utility) { PlacePhotoStore.sizeBytes() }.value
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
