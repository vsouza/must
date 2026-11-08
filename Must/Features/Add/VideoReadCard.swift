import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Vídeo escolhido no seletor de Fotos, copiado pra uma pasta temporária (o seletor não pede acesso à biblioteca inteira).
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "must-pick-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}

/// Cartão "Ler o vídeo" (prompt 29): o link só deu legenda fraca; com a gravação de tela dá pra ler fala e texto, no aparelho.
struct VideoReadCard: View {
    @Bindable var model: AddLinkModel
    /// Chamado com o arquivo temporário do vídeo escolhido.
    var onPicked: (URL) -> Void

    @State private var picked: PhotosPickerItem?
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ler o vídeo").font(.must.archivo(17, .semibold)).foregroundStyle(Color.must.ink)
            if let progress = model.videoProgress {
                reading(progress)
            } else {
                steps
                PhotosPicker(selection: $picked, matching: .videos, preferredItemEncoding: .current) {
                    Pill("Escolher a gravação", style: .green)
                }
                .accessibilityIdentifier("video-escolher")
                if loadFailed {
                    Text("Não consegui abrir esse vídeo.").font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
                }
                ForEach(model.videoNotes, id: \.self) { note in
                    Text(note).mustMeta().foregroundStyle(Color.must.secondary)
                }
                Text("Fala e texto da tela são lidos no aparelho. O vídeo não é guardado.")
                    .mustMeta().foregroundStyle(Color.must.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 26)
        .accessibilityIdentifier("video-card")
        .onChange(of: picked) { _, item in
            guard let item else { return }
            loadFailed = false
            Task {
                if let video = try? await item.loadTransferable(type: PickedVideo.self) {
                    onPicked(video.url)
                } else {
                    loadFailed = true
                }
                picked = nil
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(1, "Grave a tela do reel por 10 a 20 s (Central de Controle)")
            step(2, "Volte pro Must")
            step(3, "Toque em “Escolher a gravação”")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.must.mono(12, .semibold)).foregroundStyle(Color.must.greenText)
                .frame(width: 22, height: 22).background(Rectangle().fill(Color.must.green))
            Text(text).font(.must.archivo(14)).foregroundStyle(Color.must.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reading(_ progress: VideoProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: progress.fraction).tint(Color.must.ink)
            Text(progress.label).mustMeta()
            Button { model.cancelVideo() } label: {
                Text("Cancelar").font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink).underline()
                    .padding(.vertical, 6)
            }
            .buttonStyle(MustPressStyle())
        }
    }
}
