import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Entrada do ingresso (V9): lista nativa com as fontes, o passo "lendo" e Cancelar sempre visível.
/// Leitura no aparelho; a conferência vem na tela seguinte.
struct TicketEntradaView: View {
    @Bindable var model: TicketImportModel
    var close: () -> Void

    @Environment(RegionStore.self) private var store
    @State private var picking = false
    @State private var photo: PhotosPickerItem?
    @State private var manualEditing = false
    @State private var hint: String?

    private var passType: UTType { UTType(filenameExtension: "pkpass") ?? .data }

    var body: some View {
        List {
            Section {
                Button(action: scan) { SourceLabel("Escanear", "Câmera no QR, no código de barras ou no papel", "camera") }
                PhotosPicker(selection: $photo, matching: .images) { SourceLabel("Fotos", "Print do app do fornecedor ou foto do ingresso", "photo") }
                Button(action: paste) { SourceLabel("Colar", "Código de confirmação ou link da reserva", "doc.on.clipboard") }
                Button { picking = true } label: { SourceLabel("Arquivo", "PDF do e-mail ou .pkpass salvo", "doc") }
                Button { manualEditing = true } label: { SourceLabel("À mão", "Você preenche os campos do ingresso", "square.and.pencil") }
                Button { hint = "No Mail, nos Arquivos ou no Safari, toque em Compartilhar e escolha Must. O ingresso aparece aqui." } label: {
                    SourceLabel("Compartilhar de outro app", "Do Mail, Arquivos ou Safari para o Must", "square.and.arrow.up")
                }
            } header: {
                Text("Como trazer")
            } footer: {
                Text(hint ?? "PDF, print, QR, link ou passe: eu leio no aparelho e você confere antes de salvar.")
            }

            if model.isReading || !model.progress.isEmpty {
                Section("Lendo") {
                    ForEach(model.progress) { line in
                        HStack(spacing: 10) {
                            if line.done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary).accessibilityLabel("feito")
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            Text(line.text).foregroundStyle(line.done ? .primary : .secondary)
                        }
                    }
                }
            }
            if let url = model.pendingURL, !model.isReading {
                Section {
                    Text(url.absoluteString).font(.footnote).lineLimit(3).textSelection(.enabled)
                    Button("Ler a página") { Task { await model.readLink() } }.v9Primary()
                } header: {
                    Text("Link recebido")
                } footer: {
                    Text("Só leio a página se você mandar. Uma requisição, sem seguir outros links.")
                }
            }
            if let error = model.error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(V9.alert) }
            }
            Section {} footer: {
                Text("Nada sai do iPhone: PDF, foto e QR ficam no app. Só o nome do lugar vai ao Places se precisar achar o endereço.")
            }
        }
        .navigationTitle("Trazer ingresso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: close) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image, passType]) { result in
            switch result {
            case .success(let url): openFile(url)
            case .failure(let failure): model.error = "Não consegui abrir o arquivo: \(failure.localizedDescription)"
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.read(.image(data))
                } else {
                    model.error = "Não consegui ler essa foto."
                }
                photo = nil
            }
        }
        .sheet(isPresented: $manualEditing) {
            TicketEditor(ticket: nil, sessions: [], region: store.region, placeName: "Ingresso à mão",
                         onSave: { ticket in model.manual(ticket) }, onRemove: nil)
        }
    }

    private func scan() {
        if TicketScanner.isAvailable {
            model.step = .scan
        } else {
            hint = "A câmera de leitura não está disponível aqui (simulador ou aparelho sem scanner). Use Fotos ou Arquivo."
        }
    }

    private func paste() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            hint = "Nada copiado: copie o código ou o link e volte aqui."
            return
        }
        Task { await model.readPasted(text) }
    }

    /// Arquivo do seletor: lê os bytes dentro do acesso com escopo de segurança.
    private func openFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let source = TicketSource.file(data, name: url.lastPathComponent)
            Task { await model.read(source) }
        } catch {
            model.error = "Não consegui abrir o arquivo: \(error.localizedDescription)"
        }
    }
}

/// Linha de fonte: ícone, título e detalhe (44 pt no mínimo).
private struct SourceLabel: View {
    var title: String
    var detail: String
    var symbol: String

    init(_ title: String, _ detail: String, _ symbol: String) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(V9.accent)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
