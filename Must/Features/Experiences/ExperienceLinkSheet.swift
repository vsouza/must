import SwiftData
import SwiftUI

/// Colar link (Viator, Klook, Airbnb, GetYourGuide, e-plus, Peatix, Sympla): lê a página, mostra o que achou e grava na Must do.
struct ExperienceLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(RegionStore.self) private var store
    @Query private var settingsList: [Settings]

    @State private var model = ExperienceLinkModel()
    @FocusState private var focused: Bool

    private var region: Region { store.region }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Colar link").mustTitle()
                    Spacer()
                    IconButton(.fechar, label: "Fechar") { dismiss() }
                }
                .padding(.top, 14)
                Text("Cola o link de uma experiência. Eu leio o título, o preço, a duração e o ponto de encontro da página.")
                    .mustSerif(18).foregroundStyle(Color.must.secondary)

                TextField("https://www.klook.com/…", text: $model.text)
                    .font(.must.archivo(16))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { read() }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Rectangle().fill(Color.must.surface))

                PrimaryButton("Ler link", icon: .colarLink) { read() }
                    .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty || model.isReading)

                result
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
        .presentationDetents([.large])
        .onAppear { focused = true }
    }

    private func read() {
        guard !model.isReading else { return }
        Task { await model.read(region: region, onDeviceAI: settingsList.first?.onDeviceAI ?? true) }
    }

    @ViewBuilder private var result: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .reading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Lendo a página…").font(.must.meta).foregroundStyle(Color.must.secondary)
            }
        case .failed(let message):
            Text(message).font(.must.meta).foregroundStyle(Color.must.secondary)
        case .ready(let draft, let link):
            draftCard(draft, link: link)
        }
    }

    private func draftCard(_ draft: ExperienceDraft, link: ExperienceLink) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Tag(ExperienceSupplier.badge(link.supplier, url: link.url), style: .dark)
                Spacer()
                Micro(draft.via)
            }
            Text(draft.name).font(.must.archivo(20, .semibold)).foregroundStyle(Color.must.ink)
            Text(facts(draft)).font(.must.meta).foregroundStyle(Color.must.secondary)
            if let session = draft.session {
                Pill("\(region.shortDayTime(session.at)) · confira no fornecedor", style: .green)
            }
            PrimaryButton("Adicionar à Must do", icon: .adicionar) {
                ExperienceStore.add(draft, region: region, context: context)
                dismiss()
            }
            GhostButton("Ver no \(ExperienceSupplier.badge(link.supplier, url: link.url))", icon: .exportar) { openURL(link.url) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func facts(_ draft: ExperienceDraft) -> String {
        var parts: [String] = []
        if let price = draft.info.priceFrom { parts.append("a partir de \(region.money(price))") }
        if let minutes = draft.info.durationMinutes { parts.append(KindLines.duration(minutes)) }
        if let meeting = draft.info.meetingPoint { parts.append(meeting) }
        if !draft.info.languages.isEmpty { parts.append(draft.info.languages.joined(separator: ", ")) }
        return parts.isEmpty ? "Nada além do título na página." : parts.joined(separator: " · ")
    }
}

/// Estado da folha de colar link (MainActor, `@Observable`).
@MainActor
@Observable
final class ExperienceLinkModel {
    enum State {
        case idle
        case reading
        case ready(ExperienceDraft, ExperienceLink)
        case failed(String)
    }

    var text = ""
    private(set) var state: State = .idle

    var isReading: Bool {
        if case .reading = state { return true }
        return false
    }

    func read(region: Region, onDeviceAI: Bool) async {
        let resolved = LinkResolver.resolve(text).url
        guard let url = resolved else {
            state = .failed(ExperienceLinkError.notALink.localizedDescription)
            return
        }
        state = .reading
        do {
            let link = try await ExperienceLinkReader.read(url)
            let draft = await ExperienceExtractor.read(link, region: region, onDeviceAI: onDeviceAI)
            state = .ready(draft, link)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
