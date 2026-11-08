import SwiftData
import SwiftUI

/// Assistente v9 (`design/v9/Assistente-1.png` e `-2.png`): tela cheia no corte. **Página 1 = Dicas** ("O que eu sei de
/// hoje": filtros, numeral, linhas de índice); a conversa mora embaixo (campo + microfone + enviar). Ao enviar a primeira
/// pergunta a página de dicas vira a conversa; "↑ dicas" volta. Sem balões: a pergunta em letra grande e a resposta em
/// texto; as trocas do dia viram linhas de índice que só o toque aplica. Roda no aparelho.
struct AssistantView: View {
    /// Pergunta que já chega digitada (o "Continuar no Assistente" do Quero…).
    var initialQuestion: String?

    init(initialQuestion: String? = nil) { self.initialQuestion = initialQuestion }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.tripTheme) private var theme
    @Environment(\.dayEngine) private var dayEngine
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var chat = ChatModel()
    @State private var speech = SpeechInput()
    @State private var input = ""
    @State private var markingDone: String?
    /// Foto do bairro de agora, só a que já está no disco (a mesma da capa); sem ela, cor + trama.
    @State private var photo: URL?
    /// Mostra a página de dicas mesmo com conversa (o "↑ dicas" do topo).
    @State private var showDicas = false
    /// Pergunta em curso: cancelada quando a tela fecha (prompt 18 · A.7).
    @State private var asking: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var region: Region { store.region }
    private var useModel: Bool { settingsList.first?.onDeviceAI ?? true }
    private var snapshot: AssistantSnapshot { AssistantSnapshot.make(context: context, region: region, services: services) }
    private var onDicas: Bool { chat.messages.isEmpty || showDicas }

    var body: some View {
        VStack(spacing: 0) {
            band
            CutRule()
            if onDicas { dicas } else { conversation }
            footer
        }
        .background(V8.paper.ignoresSafeArea())
        // Modelo aquecido só agora que o Assistente abre (nunca na abertura do app), e a geração para se a tela fecha.
        .task { chat.warm(snapshot: snapshot, useModel: useModel) }
        .task(id: snapshot.areaName) { photo = await diskPhoto(areaName: snapshot.areaName) }
        .onDisappear { asking?.cancel(); speech.cancel() }
        .onAppear {
            speech.onFinal = { text in ask(text) }
            if let initialQuestion, chat.messages.isEmpty { ask(initialQuestion) }
            #if DEBUG
            if let q = DebugFlags.string("debugAsk"), chat.messages.isEmpty { ask(q) }
            #endif
        }
        .sheet(item: Binding(get: { markingDone.map { IdentifiedString(id: $0) } }, set: { markingDone = $0?.id })) { item in
            ExpenseView(placeId: item.id)
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: Bloco

    private var band: some View {
        let ink = theme.coverInk
        return CutBand(photo: photo) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    V8CornerButton(systemName: "xmark", label: "Fechar", tint: ink) { dismiss() }
                    SpecStack(lines: ["✦ Assistente · no aparelho",
                                      onDicas ? "conhece seus \(places.count) musts e o dia" : "\(region.timeString(AppClock.now)) · \(snapshot.areaName)"],
                              color: ink)
                    Spacer(minLength: 6)
                    if !chat.messages.isEmpty {
                        Button { withAnimation(.snappy(duration: 0.2)) { showDicas.toggle() } } label: {
                            Text(showDicas ? "↓ CONVERSA" : "↑ DICAS")
                                .font(V8Font.mono(11, weight: .bold)).tracking(1)
                                .foregroundStyle(ink)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showDicas ? "Voltar pra conversa" : "Ver as dicas")
                    }
                }
                Spacer(minLength: 8)
                Text(onDicas ? "O que eu sei de hoje" : "Conversa")
                    .font(V8Font.display(onDicas ? 48 : 36))
                    .tracking(-1.6)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(height: onDicas ? 190 : 140)
    }

    // MARK: Página 1 · Dicas

    private var dicas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DicasPage { id in
                    let tab = router.tab
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        router.push(.place(id: id), on: tab)
                    }
                }
                Color.clear.frame(height: 16)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Conversa

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(chat.messages) { message in
                        line(message).id(message.id)
                    }
                    if chat.busy, chat.messages.last?.role == .user {
                        MonoLabel("pensando no aparelho…", size: 10, color: V8.mute)
                    }
                    Color.clear.frame(height: 8).id("end")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: chat.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    @ViewBuilder private func line(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            Text(m.text)
                .font(V8Font.display(30))
                .tracking(-0.9)
                .foregroundStyle(V8.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if !m.text.isEmpty {
                    MoneyText(text: m.text, currencySymbol: region.currencySymbol)
                        .font(V8Font.text(15.5))
                        .foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else if m.isStreaming {
                    MonoLabel("escrevendo…", size: 10, color: V8.mute)
                }
                if !m.actions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(m.actions) { action in actionRow(action, message: m) }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
                }
                if let note = m.note { MonoLabel(note, size: 10, color: V8.mute) }
                if !m.quickReplies.isEmpty {
                    CorteFlow(spacing: 8) {
                        ForEach(m.quickReplies, id: \.self) { reply in
                            Button { quick(reply, from: m) } label: { V8FilterChip(title: reply, on: false) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Mudança do dia como linha de índice: laranja = entra (destaque), papel = o resto.
    private func actionRow(_ action: AssistantAction, message: ChatMessage) -> some View {
        let applied = message.applied.contains(action.id)
        let live = action.highlighted && !applied
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.place.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                Text(action.meta).font(V8Font.text(13)).foregroundStyle(live ? V8.ink.opacity(0.8) : V8.mute).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { run(action, message: message) } label: {
                Text(applied ? "FEITO ✓" : action.buttonTitle.uppercased())
                    .font(V8Font.mono(11, weight: .bold)).tracking(1)
                    .foregroundStyle(live ? V8.paper : V8.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(live ? V8.ink : Color.clear)
                    .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(applied)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(live ? V8.orange : V8.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
    }

    // MARK: Entrada

    private var footer: some View {
        VStack(spacing: 0) {
            if onDicas {
                // Cada sugestão é uma caixa que quebra linha (em letra grande a de uma linha só estourava a largura da tela).
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(FallbackAssistant.suggestions(snapshot).prefix(2)), id: \.self) { suggestion in
                        Button { ask(suggestion) } label: { SuggestionBox(title: suggestion) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
            }
            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: 0) {
            TextField("", text: $input, prompt: Text(chat.messages.isEmpty ? "Pergunte ou peça…" : "Responder…").foregroundStyle(V8.muteDark),
                      axis: .vertical)
                .font(V8Font.text(17))
                .foregroundStyle(V8.white)
                .tint(V8.orange)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { ask(input) }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .accessibilityIdentifier("assistant.input")
                .accessibilityLabel("Pergunte ou peça")
            Button { Task { await speech.toggle() } } label: {
                Image(systemName: speech.isListening ? "waveform" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(speech.isListening ? V8.orange : V8.white)
                    .frame(width: 66, height: 58)
                    .overlay(alignment: .leading) { Rectangle().fill(V8.muteDark.opacity(0.5)).frame(width: 1) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.isListening ? "Parar de ouvir" : "Falar")
            Button { ask(input) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(V8.ink)
                    .frame(width: 84, height: 58)
                    .background(V8.orange)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enviar")
        }
        .frame(minHeight: 58)
        .background(V8.ink.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Ações

    private func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        input = ""
        focused = false
        showDicas = false
        let snap = snapshot
        let clock = DayClock.read(engine: dayEngine, region: region, context: context, at: snap.now, position: snap.here)
        asking = Task { await chat.send(question, snapshot: snap, useModel: useModel, clock: clock) }
    }

    /// A foto do bairro que já está no disco (nunca baixa): Google de um Must do bairro › Commons já escolhida.
    private func diskPhoto(areaName: String) async -> URL? {
        guard let area = AreaCatalog.areas(for: region).first(where: { $0.name == areaName }),
              let (_, candidates) = CapaState.areaCandidates(region: region, areaId: area.id, places: places),
              let found = await CapaState.diskPhoto(region: region, areaId: area.id, candidates: candidates) else { return nil }
        return URL(string: found.largeURL ?? found.url)
    }

    private func run(_ action: AssistantAction, message: ChatMessage) {
        if case .markDone = action.kind {
            markingDone = action.place.id
            return
        }
        if let confirmation = chat.apply(action, in: message.id, context: context, region: region) {
            chat.confirm(confirmation)
        }
    }

    private func quick(_ reply: String, from message: ChatMessage) {
        if reply.hasPrefix("Trocar pelo "), let action = message.actions.first(where: { reply.hasSuffix($0.place.name) }) {
            run(action, message: message)
        } else {
            ask(reply)
        }
    }
}

/// Sugestão de pergunta: caixa de borda 2 pt que cresce em altura em vez de passar da largura.
private struct SuggestionBox: View {
    var title: String

    var body: some View {
        Text(title)
            .font(V8Font.mono(11, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(V8.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 40, alignment: .leading)
            .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: 2))
    }
}

private struct IdentifiedString: Identifiable { var id: String }

/// Texto corrido com os valores de dinheiro em Geist Mono.
struct MoneyText: View {
    var text: String
    var currencySymbol: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var out = AttributedString(text)
        let pattern = "(R\\$|¥)\\s?[0-9][0-9.,]*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: text), let attrRange = Range(range, in: out) else { continue }
            out[attrRange].font = V8Font.mono(15, weight: .bold)
        }
        return out
    }
}

