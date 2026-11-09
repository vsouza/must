import SwiftData
import SwiftUI

/// Proposta do Montar v8: a Linha do dia proposta (papel), com as micro-paradas e os deslocamentos do motor,
/// a explicação do solver e Outra proposta / Aceitar o dia. Tocar num Must do board abre o Trocar.
/// Aceitar grava o dia do motor (`DayEngine.accept`, com micro-paradas e deslocamentos); depois de um Trocar, o dia
/// do motor fica velho e a tela volta pras paradas do solver, gravadas pelo `DayPlanner`.
struct ProposalView: View {
    @Bindable var planner: DayPlanner
    /// Dia do motor (`DayEngine.build`). `nil` = mostra as paradas do solver.
    var plan: DayPlan?
    /// "Outra": o Montar embaralha o solver e remonta o dia do motor com a semente nova (atualiza `plan`).
    /// `nil` (prints, testes) = só o solver.
    var another: (() async -> Void)? = nil
    /// "Ir pra um bairro": os Musts marcados. Os que não couberam aparecem numa faixa com o motivo. Vazio = Montar normal.
    var asked: [SolverPlace] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.tripTheme) private var theme

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var flights: [Flight]

    @State private var swapping: ProposedStop?
    /// Houve Trocar: o `plan` do motor não tem a troca, então a tela e o Aceitar usam o solver.
    @State private var swapped = false
    @Environment(\.dayEngine) private var engine
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "Outra" montando (o motor pode esperar até 2 s pelos tempos reais).
    @State private var rolling = false
    /// Paradas que entraram ou mudaram de lugar na última troca: destacadas por uns segundos.
    @State private var changed: Set<String> = []
    /// "2 trocas · entrou Fuunji · saiu Afuri" (fica até a próxima troca).
    @State private var changeNote: ProposalDiff?
    @State private var highlightGeneration = 0

    private var region: Region { store.region }

    /// O que a tela desenha: o dia do motor ou, sem ele, as paradas do solver no formato v8.
    private var shown: DayPlan? { (swapped ? nil : plan) ?? planner.proposal.map { Self.dayPlan(from: $0, date: planner.date, budget: planner.budget) } }

    var body: some View {
        VStack(spacing: 0) {
            band
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let shown {
                        if let changeNote { ChangeBanner(diff: changeNote).transition(.opacity) }
                        VStack(alignment: .leading, spacing: 0) {
                            if shown.stops.isEmpty {
                                DayStrip { Text("Nada coube nesse pedido: troque o bairro ou o ritmo.").font(V8Font.text(15)).foregroundStyle(V8.mute) }
                            }
                            ForEach(Array(shown.stops.enumerated()), id: \.element.id) { i, stop in
                                VStack(alignment: .leading, spacing: 0) {
                                    DayStopRow(stop: stop, index: i + 1, state: .upcoming, region: region, onTap: swapAction(stop))
                                        .changeHighlight(changed.contains(stop.id))
                                    if let leg = shown.leg(after: stop) { DayLegRow(leg: leg) }
                                }
                                .transition(reduceMotion ? .opacity
                                            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                            }
                            if let last = shown.lastTrain {
                                DayLegRow(leg: DayLeg(mode: .train, minutes: 0, from: "", to: "",
                                                      detail: "último trem \(last.line) \(region.timeString(last.at))"),
                                          color: V8.orangeDeep)
                            }
                        }
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.45), value: shown.stops.map(\.id))
                    }
                    let missing = IrBairro.missing(planner.proposal, asked: asked)
                    if !missing.isEmpty {
                        DayStrip(tone: .ink) {
                            VStack(alignment: .leading, spacing: 4) {
                                MonoLabel("FORA DO TRAJETO", size: 10, color: V8.white.opacity(0.7))
                                ForEach(missing, id: \.name) { m in
                                    Text("\(m.name) — \(m.reason)").font(V8Font.text(14)).foregroundStyle(V8.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if let explanation = planner.proposal?.explanation, !explanation.isEmpty {
                        DayStrip {
                            Text(explanation)
                                .font(V8Font.text(15))
                                .foregroundStyle(V8.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let error { Text(error).font(V8Font.text(13)).foregroundStyle(V8.orangeDeep).padding(.horizontal, 20).padding(.top, 8) }
                    Color.clear.frame(height: 190)
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) { actions }
        }
        .background(V8.paper.ignoresSafeArea())
        .onChange(of: shown?.stops ?? []) { old, new in markChanges(from: old, to: new) }
        #if DEBUG
        .onAppear {
            if DebugFlags.string("debugScreen") == "trocar" {
                swapping = planner.proposal?.stops.first { $0.place.role == .eat && !$0.isAnchor }
            }
            // Prints do "Outra" (o que mudou): aperta sozinho depois de 1,5 s.
            if ["outra", "corte-proposta"].contains(DebugFlags.string("debugScreen")) {
                Task { try? await Task.sleep(for: .seconds(1.5)); anotherDay() }
            }
        }
        #endif
        .sheet(item: $swapping, onDismiss: { if plan != nil { swapped = true } }) { stop in
            SwapSheet(planner: planner, stop: stop, catalog: places.solverCatalog)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
        }
    }

    /// Bloco do bairro do dia: o numeral gigante = quantas paradas tem a proposta.
    private var band: some View {
        DayBand(areaId: shown?.bandArea() ?? planner.focusArea, places: places, height: 250) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    V8CornerButton(systemName: "chevron.left", label: "Voltar ao Montar", tint: theme.coverInk) { dismiss() }
                    Spacer(minLength: 12)
                    if let shown {
                        DayBandCorners(left: [], right: [DayText.dayLine(planner.date, region: region),
                                                         "\(shown.countLine) · previsto \(region.money(shown.plannedCost))"])
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = shown?.title, !title.isEmpty { MonoLabel(title, size: 10, color: theme.coverInk.opacity(0.9)) }
                        Text("Seu dia").font(V8Font.display(46)).foregroundStyle(theme.coverInk).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 8)
                    if let shown { DayBandNumeral(value: "\(shown.stops.count)", caption: shown.stops.count == 1 ? "parada" : "paradas") }
                }
            }
        }
    }

    /// Must do board que está na proposta do solver: abre o Trocar.
    private func swapAction(_ stop: DayStop) -> (() -> Void)? {
        guard let id = stop.placeId, let proposed = planner.proposal?.stops.first(where: { $0.place.id == id }) else { return nil }
        return { swapping = proposed }
    }

    /// Paradas do solver como `DayPlan` (sem micro-paradas; deslocamentos pelo `legFromPrevious`).
    static func dayPlan(from proposal: DayProposal, date: Date, budget: Double) -> DayPlan {
        let stops = proposal.stops.map { s in
            DayStop(id: s.place.id, placeId: s.place.id, kind: s.isAnchor ? .anchor : .must, start: s.at, end: s.end,
                    label: s.place.name, note: [s.place.sub, s.reason].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                    tag: s.isAnchor ? "RES" : nil, area: nil, cost: s.place.cost)
        }
        var legs: [DayLeg] = []
        for (i, s) in proposal.stops.enumerated() where i > 0 {
            guard let leg = s.legFromPrevious else { continue }
            legs.append(DayLeg(mode: leg.mode == .walk ? .walk : .metro, minutes: leg.minutes,
                               from: proposal.stops[i - 1].place.id, to: s.place.id, detail: ""))
        }
        return DayPlan(date: date, title: proposal.stops.compactMap(\.place.area).first ?? "", dayNumber: nil, area: nil,
                       stops: stops, legs: legs, lastTrain: nil, pace: .normal, budget: budget)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            BigButton(title: rolling ? "Montando…" : "Outra", style: .line, systemImage: rolling ? nil : "arrow.triangle.2.circlepath",
                      lineColor: V8.ink, lineFill: V8.paper) { anotherDay() }
            .frame(maxWidth: 140)
            .disabled(rolling)
            BigButton(title: "Aceitar o dia", style: .orange, systemImage: "checkmark") { accept() }
                .disabled(planner.proposal?.stops.isEmpty ?? true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 24) // sem barra de abas nesta tela (`AppRouter.hidesNavBar`)
        .background {
            LinearGradient(colors: [V8.paper.opacity(0), V8.paper], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// "Outra": embaralha e remonta; a troca aparece com a animação das linhas (`markChanges`).
    private func anotherDay() {
        if let another {
            rolling = true
            Task {
                await another()
                swapped = false // o dia novo do motor já é o da semente nova (o solver do planner bate com ele)
                rolling = false
            }
        } else {
            planner.reshuffle(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                              location: services.location.current, flights: FlightRules.dayFlights(flights, on: planner.date, region: region))
            if plan != nil { swapped = true }
        }
    }

    /// Compara as paradas de antes e depois: destaca o que entrou/mudou e escreve o resumo da troca.
    private func markChanges(from old: [DayStop], to new: [DayStop]) {
        guard !old.isEmpty else { return }
        let diff = ProposalDiff(old: old, new: new)
        changed = diff.changedIds
        withAnimation(.easeOut(duration: 0.25)) { changeNote = diff }
        if diff.changedIds.isEmpty { return }
        UIAccessibility.post(notification: .announcement, argument: diff.spoken)
        highlightGeneration += 1
        let generation = highlightGeneration
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard generation == highlightGeneration else { return }
            withAnimation(.easeOut(duration: 0.8)) { changed = [] }
        }
    }

    private func accept() {
        do {
            let origin = services.location.current?.coordinate
            let enginePlan = swapped ? nil : plan
            if let enginePlan {
                try engine.accept(enginePlan, region: planner.region, context: context, origin: origin)
            } else {
                try planner.accept(context: context)
                // Avisos do guia (prompt 18 · C.17): a permissão de notificação é pedida só aqui (o `engine.accept` já pede).
                let region = planner.region
                Task { await GuideNudgeScheduler.refresh(context: context, region: region, origin: origin, askPermission: true) }
            }
            router.tab = .hoje
            // Aceitou: a Linha do dia (ou o Guia, quando veio do "Ajustar" de Bairros).
            router.paths[.hoje] = [planner.focusArea != nil && enginePlan == nil ? .guia(date: planner.date) : .linha(date: planner.date)]
            // Baixa o que o dia pede (só no Wi-Fi; no celular fica "salva no Wi-Fi") (prompt 18 · A.5).
            let date = planner.date, network = services.connectivity.prefetchNetwork
            let region = planner.region
            Task { await services.prefetch.run(date: date, context: context, region: region, network: network) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "No lugar do Fuunji": até 3 alternativas na mesma janela, perto do trajeto.
struct SwapSheet: View {
    @Bindable var planner: DayPlanner
    let stop: ProposedStop
    let catalog: [SolverPlace]

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @State private var filter: SwapFilter = .sameSub

    private var region: Region { store.region }

    var body: some View {
        let proposal = planner.proposal
        let alternatives = proposal.map { DaySolver.alternatives(for: stop.id, in: $0, catalog: catalog, filter: filter) } ?? []
        VStack(alignment: .leading, spacing: 0) {
            SheetHandle().frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Micro("trocar · \(stop.window.label) \(region.timeString(stop.at))")
                        Text("No lugar do \(stop.place.name)").mustTitle()
                        Text(pathLine(proposal)).mustSerif(18).foregroundStyle(Color.must.secondary)
                    }
                    .padding(.top, 22)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SwapFilter.allCases) { f in
                                Button { filter = f } label: { Pill(f.label(sub: stop.place.sub, role: stop.place.role), isOn: filter == f) }
                                    .buttonStyle(MustPressStyle())
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .padding(.vertical, 10)

                    if alternatives.isEmpty {
                        Text("Nada elegível nesse filtro, nessa janela.").mustMeta().padding(.vertical, 10)
                    }
                    ForEach(Array(alternatives.enumerated()), id: \.element.id) { index, alt in
                        Button {
                            planner.swap(stop.id, with: alt.place)
                            dismiss()
                        } label: { alternativeRow(alt, highlighted: index == 0) }
                            .buttonStyle(MustPressStyle())
                    }

                    do {
                        Button {
                            planner.skip(stop.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pular \(stop.window.isMeal ? "o \(stop.window.label)" : stop.place.name) no roteiro")
                                    .font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.secondary)
                                Text(stop.window.isMeal ? "como na regra: uma refeição por janela, decido na hora" : "fica um respiro no dia")
                                    .mustMeta()
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            PrimaryButton("Manter \(stop.place.name)", style: .dark) { dismiss() }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
        }
        .background {
            ZStack(alignment: .topTrailing) {
                Color.must.bg
                Ellipse().fill(Blob.Fill.green.gradient).frame(width: 190, height: 130).rotationEffect(.degrees(-20)).offset(x: 40, y: 10)
            }
            .ignoresSafeArea()
        }
    }

    private func pathLine(_ proposal: DayProposal?) -> String {
        guard let proposal, let i = proposal.stops.firstIndex(where: { $0.id == stop.id }) else { return "" }
        let prev = i > 0 ? proposal.stops[i - 1].place.name : "a saída"
        let next = i + 1 < proposal.stops.count ? proposal.stops[i + 1].place.area ?? proposal.stops[i + 1].place.name : nil
        return "abertos no horário, perto do \(prev)" + (next.map { " → \($0)" } ?? "")
    }

    private func alternativeRow(_ alt: SwapAlternative, highlighted: Bool) -> some View {
        let p = alt.place
        let delta = alt.priceDelta == 0 ? (alt.detourMinutes == 0 ? "0 desvio" : (alt.detourMinutes > 0 ? "+\(alt.detourMinutes) min" : "\(alt.detourMinutes) min"))
            : (alt.priceDelta > 0 ? "+" : "−") + region.money(abs(alt.priceDelta))
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.name).mustPlace().lineLimit(1)
                }
                Text(alt.note).font(.must.archivo(13)).foregroundStyle(highlighted ? MustColor.eat.text : Color.must.secondary).lineLimit(2)
                if p.sourceKind == .instagram || p.sourceKind == .tiktok {
                    Text("o que o \(p.sourceKind!.label) mostrou").mustSerif(16).foregroundStyle(MustColor.eat.text)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(region.money(p.cost)).font(.must.mono(14)).foregroundStyle(Color.must.ink)
                Text(delta).font(.must.mono(13)).foregroundStyle(alt.priceDelta < 0 ? MustColor.eat.text : Color.must.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(highlighted ? Color.clear : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(highlighted ? Color.clear : Color.must.line))
        }
    }

}

/// O que mudou entre duas propostas (o "Outra" ou um Trocar): paradas que entraram, saíram ou trocaram de lugar.
/// Puro, pra teste. Compara por id da linha (`p-<lugar>`, `m-<tipo>`) e pelo lugar dentro dela (o café da manhã pode
/// ser outro café com o mesmo id de micro-parada).
struct ProposalDiff: Equatable, Sendable {
    /// Ids (na proposta nova) das linhas que entraram ou trocaram de lugar.
    var changedIds: Set<String>
    var added: [String]
    var removed: [String]

    init(old: [DayStop], new: [DayStop]) {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Set(new.map(\.id))
        let fresh = new.filter { stop in
            guard let was = before[stop.id] else { return true }
            return was.placeId != stop.placeId || was.label != stop.label
        }
        changedIds = Set(fresh.map(\.id))
        added = fresh.filter { $0.kind != .micro }.map { Self.short($0.label) }
        let replacedMicro = Set(fresh.map(\.id))
        removed = old.filter { stop in
            (!after.contains(stop.id) || replacedMicro.contains(stop.id)) && stop.kind != .micro
        }.map { Self.short($0.label) }
    }

    /// "Fuunji · tsukemen" → "Fuunji".
    static func short(_ label: String) -> String {
        label.components(separatedBy: " · ").first ?? label
    }

    var count: Int { changedIds.count }

    /// "Mesmo dia · nada melhor com esse pedido" / "2 trocas".
    var title: String {
        switch count {
        case 0: "Mesmo dia · nada melhor com esse pedido"
        case 1: "1 troca"
        default: "\(count) trocas"
        }
    }

    /// "entrou Fuunji, Afuri · saiu Ichiran"
    var detail: String? {
        var parts: [String] = []
        if !added.isEmpty { parts.append("entrou " + added.prefix(3).joined(separator: ", ") + (added.count > 3 ? "…" : "")) }
        if !removed.isEmpty { parts.append("saiu " + removed.prefix(3).joined(separator: ", ") + (removed.count > 3 ? "…" : "")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var spoken: String { [title, detail].compactMap { $0 }.joined(separator: ". ") }
}

/// Resumo da troca acima do índice: faixa laranja inteira quando mudou algo, papel quando o dia ficou igual.
private struct ChangeBanner: View {
    var diff: ProposalDiff

    var body: some View {
        DayStrip(tone: diff.count == 0 ? .paper : .orange) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: diff.count == 0 ? "equal" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(V8.ink)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diff.title.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(1.1).foregroundStyle(V8.ink)
                    if let detail = diff.detail {
                        Text(detail).font(V8Font.text(14)).foregroundStyle(V8.ink.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Linha que acabou de entrar: faixa laranja leve de largura total e um filete na esquerda, que somem devagar.
    func changeHighlight(_ on: Bool) -> some View {
        background(alignment: .leading) {
            if on {
                Rectangle()
                    .fill(V8.orange.opacity(0.22))
                    .overlay(alignment: .leading) { Rectangle().fill(V8.orange).frame(width: 6) }
                    .transition(.opacity)
            }
        }
    }
}
