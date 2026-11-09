import CoreLocation
import SwiftUI

/// A capa do corte (prompt 30 §2–§5, `CorteFluxo.png`, `CorteGesto.png`): foto tratada em cima, régua preta puxável, papel
/// embaixo. Puxar a régua abre a fenda laranja do "quero…"; o resultado vem em duas faixas (seus Musts · o que tem perto).
/// Tudo o que a tela mostra vem pronto (`CapaContent`, `CapaSuggestState`, `CorteState`); o `body` só desenha.
struct CapaCorteView: View {
    var content: CapaContent
    /// Bairro por GPS/célula (sem GPS, a cidade do dia).
    var areaName: String
    /// Foto que o app já tem (nunca baixa).
    var photoURL: URL?
    var suggest: CapaSuggestState
    var state: CorteState
    var tripId: String
    /// Há dia aceito pra hoje? Sem ele a capa mostra a linha "Montar o dia".
    var hasPlan = true
    var makeEnv: () -> QueroEnv
    var actions: Actions

    /// O que a capa pede pra fora (rota, Lugar, board, dia).
    struct Actions {
        var trips: () -> Void
        var assistente: () -> Void
        /// "Continuar no Assistente" da faixa de pergunta (v9): leva o texto.
        var continueInAssistant: (String) -> Void
        var openSuggestion: (Suggestion) -> Void
        var openPlace: (String) -> Void
        var route: (CorteRow) -> Void
        var addToBoard: (CorteRow) -> Void
        var fitToday: (CorteRow) -> Void
        var openShows: () -> Void
        /// Botão visível pro Bolso (antes só deslizando →).
        var bolso: () -> Void
        /// Montar o dia de hoje (linha da capa quando não há dia).
        var montar: () -> Void
        /// "Ir pra um bairro": marca os Musts do bairro e monta o trajeto.
        var irBairro: () -> Void
    }

    @Environment(\.tripTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var upcoming: Bool { content.lead == "Primeiro dia" && content.agora == nil }
    private var placeName: String { upcoming ? content.area : areaName }

    var body: some View {
        GeometryReader { geo in
            let rest = max(200, geo.size.height * 0.46)
            let pullNow = state.pull.offset
            let h = CorteLayout.heights(stage: state.stage, pull: pullNow, rest: rest)
            ZStack(alignment: .topLeading) {
                V8.paper.ignoresSafeArea()
                VStack(spacing: 0) {
                    band(progress: min(pullNow / CutPull.limit, 1))
                        .frame(height: h.band)
                    slit
                        .frame(height: h.slit, alignment: .bottom)
                        .clipped()
                    rule
                    paper
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.82), value: state.stage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: state.stage) { _, stage in focused = stage == .asking }
        .onChange(of: state.quero.phase) { _, _ in state.resultArrived() }
        .task {
            state.speech.onFinal = { text in
                state.quero.text = text
                state.submit(makeEnv())
            }
        }
    }

    // MARK: Régua

    private var rule: some View {
        Group {
            if upcoming {
                CutRule()
            } else {
                CutRule(pullLabel: CutPull.label(phase: state.pull.phase, offset: state.pull.offset))
                    .cutPull(state.pull, reduceMotion: reduceMotion, onOpen: { state.open() }, onClose: { state.close() })
                    .accessibilityAction(named: state.stage == .rest ? "Abrir quero" : "Fechar quero") {
                        if state.stage == .rest { state.open() } else { state.close() }
                    }
            }
        }
    }

    // MARK: Bloco da foto

    private func band(progress: CGFloat) -> some View {
        CutBand(photo: photoURL) {
            switch state.stage {
            case .rest: restBand(progress: progress)
            case .asking: askingBand
            case .result: resultBand
            }
        }
    }

    private func restBand(progress: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 8)
            if progress > 0.25 {
                phrase(size: 44)
                    .transition(.opacity)
            } else {
                titleBlock
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var topRow: some View {
        let ink = theme.coverInk
        return HStack(alignment: .top, spacing: 10) {
            V8CornerButton(systemName: "arrow.left.arrow.right", label: "Minhas viagens", tint: ink, action: actions.trips)
            SpecStack(lines: content.topLeft, color: ink)
            Spacer(minLength: 6)
            SpecStack(lines: content.topRight, color: ink, alignment: .trailing)
            V8CornerButton(systemName: "sparkle", label: "Assistente", tint: ink, action: actions.assistente)
        }
    }

    /// "JAPÃO · VOCÊS ESTÃO EM" e o nome do bairro gigante (toque = puxar o quero…). Viagem futura: "Faltam N dias" e
    /// "Primeiro dia · <cidade>".
    private var titleBlock: some View {
        let ink = theme.coverInk
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                theme.flag.frame(width: 22, height: 22)
                SpecLabel(upcoming ? "\(content.country) · a viagem começa em" : "\(content.country) · você está em", color: ink)
            }
            Button { if !upcoming { state.open() } } label: {
                Text(upcoming ? (content.topLeft.first ?? content.area) : placeName)
                    .font(V8Font.display(64))
                    .tracking(-2)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(upcoming ? "\(content.topLeft.first ?? "")" : "\(placeName). Toque pra dizer o que você quer")
            .accessibilityAddTraits(.isHeader)
            if upcoming { MonoLabel("Primeiro dia · \(content.area)", size: 10, color: ink) }
            // Sem foto o bloco não fica vazio: a próxima ação ("saia às 15:46 · Gyoen", "pouso 15:40").
            if !upcoming, photoURL == nil, let action = suggest.heroAction {
                Text(action).font(V8Font.text(18, weight: .semibold)).foregroundStyle(ink).lineLimit(2)
            }
        }
    }

    private func phrase(size: CGFloat) -> some View {
        Text("\(placeName),\nquero")
            .font(V8Font.display(size))
            .tracking(-1.4)
            .lineSpacing(-10)
            .foregroundStyle(theme.coverInk)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(placeName), quero")
    }

    private var askingBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            phrase(size: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var resultBand: some View {
        let count = state.split.board.count + state.split.outside.count
        return Button { state.askAgain() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    MonoLabel("quero · \(placeName)", size: 10, color: theme.coverInk)
                    Spacer(minLength: 8)
                    if state.quero.phase == .done { MonoLabel(count == 1 ? "1 achado" : "\(count) achados", size: 10, color: theme.coverInk) }
                }
                Spacer(minLength: 4)
                Text(state.quero.intent?.display ?? state.quero.text)
                    .font(V8Font.display(52))
                    .tracking(-1.6)
                    .foregroundStyle(theme.coverInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("toque pra pedir outra coisa")
    }

    // MARK: Fenda laranja

    @ViewBuilder private var slit: some View {
        if state.stage == .asking || state.pull.progress > 0.05 {
            CorteSlit(model: state.quero, focused: $focused, speech: state.speech,
                      onSubmit: { state.submit(makeEnv()) })
                .opacity(state.stage == .asking ? 1 : Double(state.pull.progress))
        } else {
            Color.clear
        }
    }

    // MARK: Papel

    @ViewBuilder private var paper: some View {
        switch state.stage {
        case .rest: restPaper
        case .asking: askingPaper
        case .result: resultPaper
        }
    }


    private var restPaper: some View {
        VStack(alignment: .leading, spacing: 0) {
            restHeader
            Rectangle().fill(V8.ink).frame(height: 2)
            ViewThatFits(in: .vertical) {
                indexRows(4)
                indexRows(3)
                indexRows(2)
                indexRows(1)
                indexRows(0)
            }
            shortcutRows
            Spacer(minLength: 0)
        }
    }

    /// Caminhos que antes só existiam por gesto: Bolso (→) e Montar o dia (segurar o `+`).
    private var shortcutRows: some View {
        VStack(spacing: 0) {
            if !hasPlan && !upcoming { shortcutRow("Montar o dia de hoje", sub: "roteiro pelo que está aberto e perto", action: actions.montar) }
            shortcutRow("Ir pra um bairro", sub: "marque os Musts e eu monto o trajeto", action: actions.irBairro)
            shortcutRow("Bolso", sub: "Suica, ingressos, mapa offline, SOS", action: actions.bolso)
        }
        .padding(.bottom, 12)
    }

    private func shortcutRow(_ title: String, sub: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(V8.ink).frame(height: 2)
            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                        Text(sub).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.orange)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var restHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(upcoming ? "a viagem" : "aberto agora · a 10 min", size: 10, color: V8.mute)
                Text(upcoming ? content.midLeft.joined(separator: " · ") : suggest.stateLine)
                    .font(V8Font.text(15, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let n = upcoming ? Int(content.numeral) ?? 0 : suggest.openNearby
            Text(n > 99 ? "99+" : "\(n)")
                .font(V8Font.numeral(84))
                .tracking(-4)
                .foregroundStyle(V8.orange)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(upcoming ? "Faltam \(content.numeral) dias" : "Aberto agora a 10 minutos: \(suggest.openNearby). \(suggest.stateLine)")
    }

    private func indexRows(_ n: Int) -> some View {
        VStack(spacing: 0) {
            if upcoming {
                Text("Puxe a régua só na cidade onde você estiver. Até lá, o dia a dia fica no Bolso e nas Listas.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if suggest.cards.isEmpty && suggest.showLine == nil {
                Text(suggest.emptyLine.isEmpty ? "Nada aberto por perto agora. Puxe a régua e diga o que você quer." : suggest.emptyLine)
                    .font(V8Font.text(14)).foregroundStyle(V8.mute)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(CorteIndexLine.index(cards: suggest.cards, show: suggest.showLine, limit: n)) { line in
                    CorteIndexRow(line: line) {
                        if let card = line.card { actions.openSuggestion(card) } else { actions.openShows() }
                    }
                }
            }
        }
    }

    // MARK: Pedindo (vontades de agora)

    private var askingPaper: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let question = state.quero.question {
                QueroQuestionSlab(question: question) { actions.continueInAssistant(question.text) }
            }
            CorteWishChips(state: state, makeEnv: makeEnv,
                           label: state.quero.question == nil ? "vontades de agora" : "ou um lugar agora")
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(.top, state.quero.question == nil ? 0 : 0)
    }

    // MARK: Resultado

    private var resultPaper: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                resultBands
                Color.clear.frame(height: 110)
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { BottomFade(color: V8.paper, height: 90) }
    }

    private var resultBands: some View {
        CorteResultBands(state: state, placeName: placeName,
                         actions: .init(openPlace: actions.openPlace, route: actions.route, addToBoard: actions.addToBoard,
                                        fitToday: actions.fitToday),
                         makeEnv: makeEnv)
    }
}

// MARK: - Peças

/// Chips que quebram de linha.
struct CorteFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
