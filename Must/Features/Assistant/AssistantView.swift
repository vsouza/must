import SwiftData
import SwiftUI

/// Assistente: orb, sugestões do momento e chat com cartões de ação. Roda no aparelho.
struct AssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var chat = ChatModel()
    @State private var input = ""
    @State private var markingDone: String?
    /// Pergunta em curso: cancelada quando a tela fecha (prompt 18 · A.7).
    @State private var asking: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var region: Region { store.region }
    private var useModel: Bool { settingsList.first?.onDeviceAI ?? true }
    private var snapshot: AssistantSnapshot { AssistantSnapshot.make(context: context, region: region, services: services) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if chat.messages.isEmpty { empty } else { conversation }
            inputBar
        }
        .background(Color.must.bg.ignoresSafeArea())
        // Modelo aquecido só agora que o Assistente abre (nunca na abertura do app), e a geração para se a tela fechar.
        .task { chat.warm(snapshot: snapshot, useModel: useModel) }
        .onDisappear { asking?.cancel() }
        #if DEBUG
        .onAppear {
            if let q = DebugFlags.string("debugAsk"), chat.messages.isEmpty { ask(q) }
        }
        #endif
        .sheet(item: Binding(get: { markingDone.map { IdentifiedString(id: $0) } }, set: { markingDone = $0?.id })) { item in
            ExpenseView(placeId: item.id)
        }
    }

    // MARK: Topo

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Must").font(.must.archivo(16)).foregroundStyle(Color.must.secondary)
                Text("Assistente").font(.must.archivo(22, .semibold)).foregroundStyle(Color.must.ink)
            }
            .background(alignment: .topLeading) {
                if !chat.messages.isEmpty {
                    AssistantOrb(dotted: false).frame(width: 160, height: 110).offset(x: -24, y: -6).opacity(0.9)
                }
            }
            Spacer()
            IconButton(.fechar, label: "Fechar") { dismiss() }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    // MARK: Vazio

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 10)
            AssistantOrb(dotted: true).frame(width: 300, height: 230)
            Spacer(minLength: 10)
            Text("Como posso ajudar agora, Vinicius?")
                .font(.must.archivo(26, .semibold)).tracking(-0.4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.must.ink)
            Text(subtitle).mustSerif(18).foregroundStyle(Color.must.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(FallbackAssistant.suggestions(snapshot), id: \.self) { suggestion in
                    Button { ask(suggestion) } label: { Pill(suggestion) }
                        .buttonStyle(MustPressStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var subtitle: String {
        let where_ = OnDeviceAI.isAvailable && useModel ? "no aparelho" : "no aparelho · sem modelo, por palavra-chave"
        return "\(where_) · conhece seus \(places.count) musts e o dia de hoje"
    }

    // MARK: Conversa

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Micro("\(region.timeString(AppClock.now)) · \(snapshot.areaName) · no aparelho")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    ForEach(chat.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if chat.busy, chat.messages.last?.role == .user {
                        ProgressView().padding(.leading, 4)
                    }
                    Color.clear.frame(height: 8).id("end")
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: chat.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            Text(m.text)
                .font(.must.archivo(16))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.must.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if !m.text.isEmpty {
                    MoneyText(text: m.text, currencySymbol: region.currencySymbol)
                        .font(.must.archivo(17))
                        .foregroundStyle(Color.must.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else if m.isStreaming {
                    ProgressView()
                }
                ForEach(m.actions) { action in actionCard(action, message: m) }
                if let note = m.note { Text(note).mustSerif(18).foregroundStyle(Color.must.secondary) }
                if !m.quickReplies.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(m.quickReplies, id: \.self) { reply in
                            Button { quick(reply, from: m) } label: { Pill(reply) }.buttonStyle(MustPressStyle())
                        }
                    }
                }
            }
            .padding(.trailing, 20)
        }
    }

    private func actionCard(_ action: AssistantAction, message: ChatMessage) -> some View {
        let applied = message.applied.contains(action.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.place.name).font(.must.archivo(18, .semibold)).foregroundStyle(Color.must.ink)
                Text(action.meta).font(.must.archivo(14)).foregroundStyle(action.highlighted ? MustColor.eat.text : Color.must.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button { run(action, message: message) } label: {
                Text(applied ? "Feito ✓" : action.buttonTitle)
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(action.highlighted && !applied ? .white : Color.must.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Capsule().fill(action.highlighted && !applied ? Color.must.ink : Color.white.opacity(0.7)))
            }
            .buttonStyle(MustPressStyle())
            .disabled(applied)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(action.highlighted ? AnyShapeStyle(MustColor.eat.gradient) : AnyShapeStyle(Color.must.surface2))
        }
    }

    // MARK: Entrada

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { ask(input) } label: {
                MustIconView(.assistente, size: 18).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MustGradient.avatar))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Enviar")
            TextField(chat.messages.isEmpty ? "Pergunte ou peça uma troca…" : "Responder…", text: $input, axis: .vertical)
                .font(.must.archivo(16))
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { ask(input) }
                .accessibilityIdentifier("assistant.input")
            if chat.messages.isEmpty {
                PasteButton(payloadType: String.self) { strings in
                    guard let link = strings.first else { return }
                    Task { @MainActor in
                        dismiss()
                        try? await Task.sleep(for: .milliseconds(300))
                        router.sheet = .addLink(url: link, listId: nil)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.white)
                .foregroundStyle(Color.must.ink)
                .accessibilityLabel("Colar link")
            }
            Button { focused = true } label: {
                MustIconView(.falar, size: 18).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Ditar (microfone do teclado)")
        }
        .padding(8)
        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    // MARK: Ações

    private func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        input = ""
        let snap = snapshot
        asking = Task { await chat.send(question, snapshot: snap, useModel: useModel) }
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
            out[attrRange].font = .must.mono(17, .semibold)
        }
        return out
    }
}

/// Orb do Assistente: duas elipses (azul/verde) com retícula pontilhada por cima.
struct AssistantOrb: View {
    var dotted: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Blob.Fill.blue.gradient).frame(width: w * 0.68, height: h * 0.78).position(x: w * 0.36, y: h * 0.4)
                Ellipse().fill(Blob.Fill.green.gradient).frame(width: w * 0.66, height: h * 0.76).position(x: w * 0.64, y: h * 0.6)
                if dotted {
                    Canvas { ctx, size in
                        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                        let radius = min(size.width, size.height) * 0.48
                        let step: CGFloat = 7
                        var y: CGFloat = 0
                        while y < size.height {
                            var x: CGFloat = 0
                            while x < size.width {
                                let d = hypot(x - center.x, (y - center.y) * 1.15)
                                if d < radius {
                                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.4, height: 2.4)),
                                             with: .color(Color.must.ink.opacity(0.55)))
                                }
                                x += step
                            }
                            y += step
                        }
                    }
                    .frame(width: w * 0.62, height: h * 0.92)
                    .position(x: w * 0.5, y: h * 0.5)
                    .blendMode(.multiply)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
