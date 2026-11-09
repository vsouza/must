import SwiftData
import SwiftUI

/// Assistente V9: sheet nativa com dois tamanhos. **Página 1 = Dicas** ("O que eu sei de hoje": lista com filtro); ao
/// enviar a primeira pergunta a página vira a conversa e "Dicas" no topo volta. Campo, microfone e enviar embaixo.
/// Mudanças do dia aparecem como linhas com botão. Roda no aparelho.
struct AssistantView: View {
    /// Pergunta que já chega digitada (o "Continuar no Assistente" do Quero…).
    var initialQuestion: String?

    init(initialQuestion: String? = nil) { self.initialQuestion = initialQuestion }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var chat = ChatModel()
    @State private var speech = SpeechInput()
    @State private var input = ""
    @State private var markingDone: String?
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
        NavigationStack {
            Group {
                if onDicas { dicas } else { conversation }
            }
            .background(V9.groupedBackground)
            .navigationTitle(onDicas ? "O que eu sei de hoje" : "Conversa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                if !chat.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(showDicas ? "Conversa" : "Dicas") { showDicas.toggle() }
                            .accessibilityLabel(showDicas ? "Voltar pra conversa" : "Ver as dicas")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .v9Screen(grouped: true)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Modelo aquecido só agora que o Assistente abre (nunca na abertura do app), e a geração para se a tela fecha.
        .task { chat.warm(snapshot: snapshot, useModel: useModel) }
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

    // MARK: Página 1 · Dicas

    private var dicas: some View {
        DicasPage { id in
            let tab = router.tab
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                router.push(.place(id: id), on: tab)
            }
        }
    }

    // MARK: Conversa

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("\(region.timeString(AppClock.now)) · \(snapshot.areaName) · roda no aparelho", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(chat.messages) { message in
                        line(message).id(message.id)
                    }
                    if chat.busy, chat.messages.last?.role == .user {
                        Text("Pensando no aparelho…").font(.footnote).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 8).id("end")
                }
                .padding(.horizontal, V9.gutter)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: chat.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    @ViewBuilder private func line(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            Text(m.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(V9.fill, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Você: \(m.text)")
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if !m.text.isEmpty {
                    MoneyText(text: m.text, currencySymbol: region.currencySymbol)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else if m.isStreaming {
                    Text("Escrevendo…").font(.footnote).foregroundStyle(.secondary)
                }
                if !m.actions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(m.actions) { action in
                            actionRow(action, message: m)
                            if action.id != m.actions.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(V9.card, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
                }
                if let note = m.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                if !m.quickReplies.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(m.quickReplies, id: \.self) { reply in
                            Button(reply) { quick(reply, from: m) }
                                .buttonStyle(.bordered).controlSize(.regular)
                        }
                    }
                }
            }
        }
    }

    /// Mudança do dia como linha: o botão com o acento só quando é o destaque.
    private func actionRow(_ action: AssistantAction, message: ChatMessage) -> some View {
        let applied = message.applied.contains(action.id)
        let live = action.highlighted && !applied
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.place.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(action.meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(applied ? "Feito" : action.buttonTitle) { run(action, message: message) }
                .buttonStyle(.bordered)
                .tint(live ? V9.accent : nil)
                .disabled(applied)
        }
        .padding(.vertical, 10)
    }

    // MARK: Entrada

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            if onDicas {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(FallbackAssistant.suggestions(snapshot).prefix(2)), id: \.self) { suggestion in
                            Button(suggestion) { ask(suggestion) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal, V9.gutter)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            inputBar
        }
        .background(.bar)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(chat.messages.isEmpty ? "Pergunte ou peça…" : "Responder…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { ask(input) }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("assistant.input")
                .accessibilityLabel("Pergunte ou peça")
            Button { Task { await speech.toggle() } } label: {
                Image(systemName: speech.isListening ? "waveform" : "mic")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(speech.isListening ? V9.accent : Color.primary)
            }
            .accessibilityLabel(speech.isListening ? "Parar de ouvir" : "Falar")
            Button { ask(input) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : V9.accent)
            }
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 8)
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
            out[attrRange].font = .body.monospacedDigit().weight(.semibold)
        }
        return out
    }
}

