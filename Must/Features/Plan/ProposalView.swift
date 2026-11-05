import SwiftData
import SwiftUI

/// Proposta do Montar v8: a Linha do dia proposta (papel), com as micro-paradas e os deslocamentos do motor,
/// a explicação do solver e Outra proposta / Aceitar o dia. Tocar num Must do board abre o Trocar.
/// Aceitar grava pelo `DayPlanner` (solver).
// TODO(v8:B): o Aceitar grava só as paradas do solver; quando o `DayPlanner` aceitar o `DayPlan` do motor (micro-paradas
// e deslocamentos), trocar `planner.accept` por essa API — hoje o motor reconstrói o resto a partir do dia aceito.
struct ProposalView: View {
    @Bindable var planner: DayPlanner
    /// Dia do motor (`DayEngine.build`). `nil` = mostra as paradas do solver.
    var plan: DayPlan?

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
    @State private var error: String?

    private var region: Region { store.region }

    /// O que a tela desenha: o dia do motor ou, sem ele, as paradas do solver no formato v8.
    private var shown: DayPlan? { plan ?? planner.proposal.map { Self.dayPlan(from: $0, date: planner.date, budget: planner.budget) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    RoundButton(systemImage: "chevron.left", label: "Voltar ao Montar", style: .line, tint: V8.ink) { dismiss() }
                    Spacer(minLength: 12)
                    if let shown {
                        SpecStack(lines: [DayText.dayLine(planner.date, region: region),
                                          "\(shown.countLine) · previsto \(region.money(shown.plannedCost))"],
                                  color: V8.mute, alignment: .trailing)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 10)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("Seu dia").font(V8Font.display(44)).foregroundStyle(V8.ink)
                    if let shown { BigNumeral("\(shown.stops.count)", size: 84, color: V8.orange).fixedSize() }
                }
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                if let shown {
                    Text(shown.title).font(V8Font.text(15)).foregroundStyle(V8.mute).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        if shown.stops.isEmpty {
                            Text("Nada coube nesse pedido: troque o bairro ou o ritmo.").font(V8Font.text(15)).foregroundStyle(V8.mute)
                        }
                        ForEach(Array(shown.stops.enumerated()), id: \.element.id) { i, stop in
                            DayStopRow(stop: stop, index: i + 1, state: .upcoming, region: region, onTap: swapAction(stop))
                            if let leg = shown.leg(after: stop) { DayLegRow(leg: leg) }
                        }
                        if let last = shown.lastTrain {
                            DayLegRow(leg: DayLeg(mode: .train, minutes: 0, from: "", to: "",
                                                  detail: "último trem \(last.line) \(region.timeString(last.at))"),
                                      color: V8.orangeDeep)
                        }
                    }
                    .padding(.top, 22)
                }
                if let explanation = planner.proposal?.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(V8Font.text(15))
                        .foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(V8.ink.opacity(0.14)))
                        .padding(.top, 18)
                }
                if let error { Text(error).font(V8Font.text(13)).foregroundStyle(V8.orangeDeep).padding(.top, 8) }
                Color.clear.frame(height: 190)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { actions }
        .background(V8.paper.ignoresSafeArea())
        #if DEBUG
        .onAppear {
            if DebugFlags.string("debugScreen") == "trocar" {
                swapping = planner.proposal?.stops.first { $0.place.role == .eat && !$0.isAnchor }
            }
        }
        #endif
        .sheet(item: $swapping) { stop in
            SwapSheet(planner: planner, stop: stop, catalog: places.solverCatalog)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
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
            BigButton(title: "Outra", style: .line, systemImage: "arrow.triangle.2.circlepath", lineColor: V8.ink, lineFill: V8.paper) {
                withAnimation(.snappy) {
                    planner.reshuffle(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                                      location: services.location.current, flights: FlightRules.dayFlights(flights, on: planner.date, region: region))
                }
            }
            .frame(maxWidth: 140)
            BigButton(title: "Aceitar o dia", style: .orange, systemImage: "checkmark") { accept() }
                .disabled(planner.proposal?.stops.isEmpty ?? true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 92)
        .background {
            LinearGradient(colors: [V8.paper.opacity(0), V8.paper], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func accept() {
        do {
            try planner.accept(context: context)
            router.tab = .hoje
            // Aceitou: a Linha do dia (ou o Guia, quando veio do "Ajustar" de Bairros).
            router.paths[.hoje] = [planner.focusArea != nil && plan == nil ? .guia(date: planner.date) : .linha(date: planner.date)]
            // Baixa o que o dia pede (só no Wi-Fi; no celular fica "salva no Wi-Fi") (prompt 18 · A.5).
            let date = planner.date, network = services.connectivity.prefetchNetwork
            let region = planner.region
            Task { await services.prefetch.run(date: date, context: context, region: region, network: network) }
            // Avisos do guia (prompt 18 · C.17): a permissão de notificação é pedida só aqui.
            let origin = services.location.current?.coordinate
            Task { await GuideNudgeScheduler.refresh(context: context, region: region, origin: origin, askPermission: true) }
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
                    if let local = placeLocal(p) { Text(local).font(.must.kanji(12, bold: false)).foregroundStyle(Color.must.secondary).lineLimit(1) }
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

    private func placeLocal(_ p: SolverPlace) -> String? { p.nameLocal }
}
