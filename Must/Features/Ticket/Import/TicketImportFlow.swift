import SwiftData
import SwiftUI

/// Trazer ingresso (prompt 15 · A): sheet com três telas — Entrada (`TicketEntrada`), Escanear (`TicketScan`)
/// e Conferir (`TicketRevisar`). Aberta pelo botão da Reservas ou por `must://import?id=` (caixa do Share Extension).
struct TicketImportFlow: View {
    /// Item da caixa do Share Extension (nil = começa na Entrada, sem arquivo).
    var inboxId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @State private var model = TicketImportModel()

    var body: some View {
        NavigationStack {
            TicketEntradaView(model: model, close: { dismiss() })
                .navigationDestination(isPresented: step(.scan)) {
                    TicketScanView(model: model, back: { model.step = .entrada })
                }
                .navigationDestination(isPresented: step(.revisar)) {
                    TicketRevisarView(model: model, close: { dismiss() })
                }
        }
        .v9Screen(grouped: true)
        .tint(V9.accent)
        .task {
            model.configure(context: context, region: store.region, provider: services.places)
            if let inboxId { await model.loadInbox(id: inboxId) }
        }
        .onDisappear { model.discard() }
    }

    /// Empilha a tela do passo; o Voltar do sistema devolve o passo pra Entrada.
    private func step(_ target: TicketImportModel.Step) -> Binding<Bool> {
        Binding(get: { model.step == target },
                set: { if !$0 && model.step == target { model.step = .entrada } })
    }
}

extension TicketSource {
    /// Arquivo escolhido no seletor, pelo nome: PDF, .pkpass ou imagem.
    static func file(_ data: Data, name: String) -> TicketSource {
        switch name.split(separator: ".").last.map({ $0.lowercased() }) {
        case "pdf": .pdf(data)
        case "pkpass": .pkpass(data)
        default: .image(data)
        }
    }
}
