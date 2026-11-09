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
        List {
            if let shown {
                if let changeNote {
                    Section { ChangeBanner(diff: changeNote).transition(.opacity) }
                }
                Section {
                    if shown.stops.isEmpty {
                        Text("Nada coube nesse pedido: troque o bairro ou o ritmo.").foregroundStyle(.secondary)
                    }
                    ForEach(shown.stops) { stop in
                        VStack(alignment: .leading, spacing: 8) {
                            V9StopRow(stop: stop, state: .upcoming, region: region, onTap: swapAction(stop))
                            if let leg = shown.leg(after: stop) { V9LegRow(leg: leg) }
                        }
                        .listRowBackground(changed.contains(stop.id) ? V9.accent.opacity(0.16) : nil)
                    }
                    if let last = shown.lastTrain {
                        V9LegRow(leg: DayLeg(mode: .train, minutes: 0, from: "", to: "",
                                             detail: "último trem \(last.line) \(region.timeString(last.at))"))
                    }
                } header: {
                    Text(shown.title.isEmpty ? shown.countLine : "\(shown.title) · \(shown.countLine)")
                } footer: {
                    if swappable { Text("Toque numa parada do seu board pra trocar por outra.") }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.45), value: shown.stops.map(\.id))
            }
            let missing = IrBairro.missing(planner.proposal, asked: asked)
            if !missing.isEmpty {
                Section("Fora do trajeto") {
                    ForEach(missing, id: \.name) { m in
                        Text("\(m.name) — \(m.reason)").fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let explanation = planner.proposal?.explanation, !explanation.isEmpty {
                Section("Por que assim") {
                    Text(explanation).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(V9.alert) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Seu dia")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(subtitle)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .v9Screen(grouped: true)
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
                .presentationDetents([.medium, .large])
        }
    }

    private var swappable: Bool { shown?.stops.contains { swapAction($0) != nil } ?? false }

    private var subtitle: String {
        guard let shown else { return DayText.dayLine(planner.date, region: region) }
        return "\(DayText.dayLine(planner.date, region: region)) · previsto \(region.money(shown.plannedCost))"
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
        HStack(spacing: 12) {
            Button { anotherDay() } label: {
                Label(rolling ? "Montando…" : "Outra", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
            }
            .v9Secondary()
            .disabled(rolling)
            Button { accept() } label: {
                Label("Aceitar o dia", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .v9Primary()
            .disabled(planner.proposal?.stops.isEmpty ?? true)
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 10)
        .background(.bar)
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
        NavigationStack {
            List {
                Section {
                    Picker("Filtro", selection: $filter) {
                        ForEach(SwapFilter.allCases) { f in Text(f.label(sub: stop.place.sub, role: stop.place.role)).tag(f) }
                    }
                } footer: {
                    Text(pathLine(proposal))
                }
                Section {
                    if alternatives.isEmpty {
                        Text("Nada elegível nesse filtro, nessa janela.").foregroundStyle(.secondary)
                    }
                    ForEach(alternatives) { alt in
                        Button {
                            planner.swap(stop.id, with: alt.place)
                            dismiss()
                        } label: { alternativeRow(alt) }
                            .buttonStyle(.plain)
                    }
                }
                Section {
                    Button {
                        planner.skip(stop.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pular \(stop.window.isMeal ? "o \(stop.window.label)" : stop.place.name) no roteiro")
                            Text(stop.window.isMeal ? "Uma refeição por janela: decido na hora." : "Fica um respiro no dia.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("No lugar do \(stop.place.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Manter \(stop.place.name)") { dismiss() } }
            }
            .v9Screen(grouped: true)
        }
    }

    private func pathLine(_ proposal: DayProposal?) -> String {
        guard let proposal, let i = proposal.stops.firstIndex(where: { $0.id == stop.id }) else { return "" }
        let prev = i > 0 ? proposal.stops[i - 1].place.name : "a saída"
        let next = i + 1 < proposal.stops.count ? proposal.stops[i + 1].place.area ?? proposal.stops[i + 1].place.name : nil
        return "\(stop.window.label.capitalizedFirst) das \(region.timeString(stop.at)) · abertos no horário, perto do \(prev)" + (next.map { " → \($0)" } ?? "")
    }

    private func alternativeRow(_ alt: SwapAlternative) -> some View {
        let p = alt.place
        let delta = alt.priceDelta == 0 ? (alt.detourMinutes == 0 ? "0 desvio" : (alt.detourMinutes > 0 ? "+\(alt.detourMinutes) min" : "\(alt.detourMinutes) min"))
            : (alt.priceDelta > 0 ? "+" : "−") + region.money(abs(alt.priceDelta))
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(alt.note).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if let kind = p.sourceKind, kind == .instagram || kind == .tiktok {
                    Text("o que o \(kind.label) mostrou").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(region.money(p.cost)).monospacedDigit()
                Text(delta).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

/// Resumo da troca acima das paradas: o que entrou e saiu, ou "mesmo dia" quando nada melhor coube.
private struct ChangeBanner: View {
    var diff: ProposalDiff

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: diff.count == 0 ? "equal" : "arrow.triangle.2.circlepath")
                .foregroundStyle(diff.count == 0 ? Color.secondary : V9.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(diff.title).font(.subheadline.weight(.semibold))
                if let detail = diff.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
