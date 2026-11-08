import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// TicketEntrada (`design/screens/TicketEntrada.png`): seis fontes pra trazer um ingresso e o card "lendo".
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconButton(.fechar, style: .glass, label: "Fechar", action: close)
                    Spacer()
                    Micro("ingresso · 1 de 3")
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, 8)

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text("6").font(V8Font.numeral(96)).tracking(-3).foregroundStyle(V8.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trazer ingresso").font(V8Font.display(30)).foregroundStyle(V8.ink)
                        Text("FORMAS DE TRAZER").font(V8Font.mono(10, weight: .semibold)).tracking(1).foregroundStyle(V8.mute)
                    }
                }
                .padding(.top, 22)
                Text("PDF, print, QR, link ou passe: eu leio no aparelho e você confere antes de salvar.")
                    .font(V8Font.text(15)).foregroundStyle(V8.mute).padding(.top, 8)

                VStack(spacing: 0) {
                    RuleLine()
                    Button(action: scan) {
                        SourceRow(index: "01", title: "Escanear", detail: "câmera no QR, no código de barras ou no papel", icon: .cameraFoto, primary: true)
                    }
                    .buttonStyle(MustPressStyle())
                    RuleLine()
                    Button { hint = "No Mail, nos Arquivos ou no Safari, toque em Compartilhar e escolha Must. O ingresso aparece aqui." } label: {
                        SourceRow(index: "02", title: "Compartilhar", detail: "do Mail, Arquivos ou Safari → Must", icon: .compartilhar, badge: "mais usado")
                    }
                    .buttonStyle(MustPressStyle())
                    RuleLine()
                    PhotosPicker(selection: $photo, matching: .images) {
                        SourceRow(index: "03", title: "Fotos", detail: "print do app do fornecedor ou foto do ingresso", icon: .arteGaleria)
                    }
                    .buttonStyle(MustPressStyle())
                    RuleLine()
                    Button(action: paste) {
                        SourceRow(index: "04", title: "Colar", detail: "código de confirmação ou link da reserva", icon: .colarLink)
                    }
                    .buttonStyle(MustPressStyle())
                    RuleLine()
                    Button { picking = true } label: {
                        SourceRow(index: "05", title: "Arquivo", detail: "PDF do e-mail ou .pkpass salvo", icon: .exportar)
                    }
                    .buttonStyle(MustPressStyle())
                    RuleLine()
                    Button { manualEditing = true } label: {
                        SourceRow(index: "06", title: "À mão", detail: "eu preencho os campos do ingresso", icon: .editar)
                    }
                    .buttonStyle(MustPressStyle())
                    RuleLine()
                }
                .padding(.top, 22)

                if let hint { Text(hint).mustMeta().padding(.top, 14) }

                if model.isReading || !model.progress.isEmpty {
                    ReadingCard(lines: model.progress).padding(.top, 22)
                }
                if let url = model.pendingURL, !model.isReading {
                    linkCard(url).padding(.top, 22)
                }
                if let error = model.error {
                    Text(error).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D)).padding(.top, 14)
                }

                Text("Nada sai do iPhone: PDF, foto e QR ficam no app. Só o nome do lugar vai ao Places se precisar achar o endereço.")
                    .mustMeta().multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 26)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background(V8.paper)
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

    private func linkCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Micro("link recebido")
            Text(url.absoluteString).font(.must.mono(13)).lineLimit(2).foregroundStyle(Color.must.ink)
            Text("Só leio a página se você mandar. Uma requisição, sem seguir outros links.").mustMeta()
            PrimaryButton("Ler a página", icon: .colarLink, style: .dark) { Task { await model.readLink() } }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Um cartão da grade de entradas (ícone, título, detalhe; o preto é a ação principal).
struct ImportCard: View {
    var title: String
    var detail: String
    var icon: MustIcon
    var dark = false
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                MustIconView(icon, size: 22)
                    .foregroundStyle(dark ? .white : Color.must.ink)
                    .frame(width: 48, height: 48)
                    .background(dark ? Color.white.opacity(0.12) : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer(minLength: 0)
                if let badge {
                    Text(badge).font(.must.archivo(11, .semibold)).foregroundStyle(Color.must.greenText)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Color.must.green.opacity(0.35), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.must.archivo(18, .semibold)).foregroundStyle(dark ? .white : Color.must.ink)
                Text(detail).font(.must.archivo(13)).foregroundStyle(dark ? .white.opacity(0.7) : Color.must.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(dark ? Color.must.ink : Color.must.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Card "lendo": os passos da leitura (texto · QR · campos · combinando · conferir), como em Adicionar por link.
struct ReadingCard: View {
    var lines: [TicketImportModel.ReadLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if line.done {
                        MustIconView(.ok, size: 16).foregroundStyle(V8.ink)
                    } else {
                        ProgressView().controlSize(.small).tint(V8.orange)
                    }
                    Text(line.text).font(.must.archivo(15, line.done ? .regular : .semibold))
                        .foregroundStyle(line.done ? Color.must.ink : Color.must.secondary)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { RuleLine() }
        .overlay(alignment: .bottom) { RuleLine() }
    }
}

/// Uma fonte de ingresso como linha de índice (corte): índice laranja, título, detalhe; a principal vai em tinta.
struct SourceRow: View {
    var index: String
    var title: String
    var detail: String
    var icon: MustIcon
    var primary = false
    var badge: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(index)
                .font(V8Font.numeral(30)).tracking(-1.2)
                .foregroundStyle(primary ? V8.orange : V8.orangeDeep)
                .frame(width: 44, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V8Font.text(18, weight: .bold)).foregroundStyle(primary ? V8.white : V8.ink)
                Text(detail).font(V8Font.text(13)).foregroundStyle(primary ? V8.muteDark : V8.mute)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let badge {
                Text(badge.uppercased()).font(V8Font.mono(9, weight: .semibold)).tracking(0.8).foregroundStyle(V8.orangeDeep)
            }
            MustIconView(icon, size: 20).foregroundStyle(primary ? V8.white : V8.ink)
        }
        .padding(.horizontal, primary ? 12 : 0).padding(.vertical, 14)
        .background(primary ? V8.ink : .clear)
        .contentShape(Rectangle())
    }
}
