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
    var makeEnv: () -> QueroEnv
    var actions: Actions

    /// O que a capa pede pra fora (rota, Lugar, board, dia).
    struct Actions {
        var trips: () -> Void
        var dicas: () -> Void
        var openSuggestion: (Suggestion) -> Void
        var openPlace: (String) -> Void
        var route: (CorteRow) -> Void
        var addToBoard: (CorteRow) -> Void
        var fitToday: (CorteRow) -> Void
    }

    @Environment(\.tripTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var upcoming: Bool { content.lead == "Primeiro dia" && content.agora == nil }
    private var placeName: String { upcoming ? content.area : areaName }

    var body: some View {
        GeometryReader { geo in
            let rest = max(200, geo.size.height * 0.46)
            let pullNow = state.pull.offset + (state.pull.phase == .closed ? state.nudge : 0)
            let h = CorteLayout.heights(stage: state.stage, pull: pullNow, rest: rest)
            ZStack(alignment: .topLeading) {
                V8.paper.ignoresSafeArea()
                VStack(spacing: 0) {
                    band(progress: min(pullNow / CutPull.limit, 1))
                        .frame(height: h.band)
                        .walkDim(state.walk == .pull)
                    slit
                        .frame(height: h.slit, alignment: .bottom)
                        .clipped()
                        .walkDim(state.walk == .pull)
                    rule
                    paper
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .walkDim(state.walk == .pull)
                }
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.82), value: state.stage)
                if state.walk == .pull { walkOne(rest: rest) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in state.touched = true })
        .onAppear { state.touched = false }
        .onChange(of: state.stage) { _, stage in focused = stage == .asking }
        .onChange(of: state.quero.phase) { _, _ in state.resultArrived() }
        .onChange(of: state.walk) { _, step in
            if step != nil { AccessibilityNotification.Announcement("Passo a passo: puxe a faixa preta pra baixo, ou use a ação Abrir quero.").post() }
        }
        .task(id: state.stage == .rest) { await nudgeWhenIdle() }
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
                CutRule(pullLabel: CutPull.label(phase: state.pull.phase, offset: state.pull.offset, uses: state.coach.uses))
                    .cutPull(state.pull, reduceMotion: reduceMotion, onOpen: { state.open() }, onClose: { state.close() })
                    .accessibilityAction(named: state.stage == .rest ? "Abrir quero" : "Fechar quero") {
                        if state.stage == .rest { state.open() } else { state.close() }
                    }
            }
        }
        .overlay { if state.walk == .pull { Rectangle().stroke(V8.orange, lineWidth: 2).allowsHitTesting(false) } }
    }

    private func nudgeWhenIdle() async {
        guard state.stage == .rest, !upcoming, state.coach.nudges, !reduceMotion, state.walk == nil else { return }
        try? await Task.sleep(for: .seconds(CutCoach.idleSeconds))
        guard !Task.isCancelled, !state.touched, state.stage == .rest, state.pull.phase == .closed else { return }
        withAnimation(.easeOut(duration: 0.3)) { state.nudge = CutCoach.nudgeDistance }
        try? await Task.sleep(for: .milliseconds(420))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { state.nudge = 0 }
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
            RoundButton(systemImage: "arrow.left.arrow.right", label: "Minhas viagens", style: .line, tint: ink, size: 40, action: actions.trips)
            SpecStack(lines: content.topLeft, color: ink)
            Spacer(minLength: 6)
            SpecStack(lines: content.topRight, color: ink, alignment: .trailing)
            RoundButton(systemImage: "sparkle", label: "Dicas", style: .line, tint: ink, size: 40, action: actions.dicas)
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

    private var lines: [CorteIndexLine] { suggest.cards.map(CorteIndexLine.init) }

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
            .padding(.bottom, 96)
            Spacer(minLength: 0)
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
            } else if lines.isEmpty {
                Text("Nada aberto por perto agora. Puxe a régua e diga o que você quer.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(lines.prefix(n)) { line in
                    CorteIndexRow(line: line) { actions.openSuggestion(line.card) }
                }
            }
        }
    }

    // MARK: Pedindo (vontades de agora)

    private var askingPaper: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.walk == .write { walkTwo }
            CorteWishChips(state: state, makeEnv: makeEnv)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: Resultado

    private var resultPaper: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if state.walk == .done { walkDone }
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
                                        fitToday: actions.fitToday))
    }

    // MARK: Passo a passo (§5)

    /// Passo 1: tela tinta a 93 %, só a régua acesa, o dedo fantasma e a linha tracejada "até aqui".
    private func walkOne(rest: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                Text("1 de 2 · novo")
                    .font(V8Font.mono(10, weight: .semibold)).tracking(1)
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(V8.orange)
                Text("Mudou\no plano?")
                    .font(V8Font.display(44)).tracking(-1.4).foregroundStyle(V8.paper)
                Text("Puxe a faixa preta pra baixo e diga o que vocês querem agora. O app junta seus Musts e o que tem perto.")
                    .font(V8Font.text(15)).foregroundStyle(V8.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .frame(maxWidth: 330, alignment: .leading)
            .allowsHitTesting(false)
            // "Até aqui": onde a régua precisa chegar.
            let lineY = rest + CutRule.pullHeight + CutPull.limit
            VStack(alignment: .leading, spacing: 6) {
                DashedLine().stroke(V8.orange, style: StrokeStyle(lineWidth: 2, dash: [7, 5])).frame(height: 2)
                MonoLabel("até aqui", size: 10, color: V8.orange)
                HStack {
                    MonoLabel("faça você mesmo pra continuar", size: 9, color: V8.muteDark)
                    Spacer(minLength: 12)
                    Button { state.skipWalk() } label: {
                        Text("PULAR").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.paper)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .overlay(Rectangle().stroke(V8.paper, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pular o passo a passo")
                }
            }
            .padding(.horizontal, 20)
            .offset(y: lineY)
            GhostFinger(from: rest + CutRule.pullHeight / 2, distance: CutPull.limit, still: reduceMotion)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Abrir quero") { state.open() }
    }

    private var walkTwo: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("2 de 2")
                        .font(V8Font.mono(10, weight: .semibold)).tracking(1)
                        .foregroundStyle(V8.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(V8.orange)
                    Spacer(minLength: 8)
                    Button { state.skipWalk() } label: {
                        Text("PULAR").font(V8Font.mono(10, weight: .semibold)).tracking(1).foregroundStyle(V8.paper)
                            .padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Escreva ou fale. O \"café\" já está aí: envie.")
                    .font(V8Font.text(14)).foregroundStyle(V8.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { state.submit(makeEnv()) } label: {
                Text("ENVIAR").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                    .padding(.horizontal, 14).padding(.vertical, 12).background(V8.orange)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.ink)
    }

    private var walkDone: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Pronto. É só puxar a faixa preta quando o plano mudar.")
                .font(V8Font.text(14, weight: .semibold)).foregroundStyle(V8.paper)
                .fixedSize(horizontal: false, vertical: true)
            Button { state.finishWalk() } label: {
                Text("PRONTO").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10).background(V8.orange)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.ink)
    }
}

// MARK: - Peças

private extension View {
    /// Passo 1 do passo a passo: tudo menos a régua fica tinta a 93 %.
    @ViewBuilder func walkDim(_ on: Bool) -> some View {
        overlay { if on { V8.ink.opacity(0.93).ignoresSafeArea(edges: .top).allowsHitTesting(false) } }
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// O dedo fantasma: desce da régua até a linha tracejada e volta, em laço. Reduzir movimento: seta parada.
private struct GhostFinger: View {
    var from: CGFloat
    var distance: CGFloat
    var still: Bool
    @State private var down = false

    var body: some View {
        GeometryReader { geo in finger.position(x: geo.size.width / 2, y: from + (down && !still ? distance : 0)) }
            .onAppear {
                guard !still else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { down = true }
            }
            .accessibilityHidden(true)
    }

    private var finger: some View {
        Group {
            if still {
                Image(systemName: "arrow.down").font(.system(size: 22, weight: .bold)).foregroundStyle(V8.orange)
                    .frame(width: 44, height: 44)
            } else {
                Circle().fill(V8.paper.opacity(0.4)).overlay(Circle().stroke(V8.orange, lineWidth: 2))
                    .frame(width: 44, height: 44)
            }
        }
    }
}

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
