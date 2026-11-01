import SwiftData
import SwiftUI

/// "Seu dia, proposto": previsto / andar / metrô, paradas com Trocar, explicação, Ajustar / Aceitar.
struct ProposalView: View {
    @Bindable var planner: DayPlanner

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var swapping: ProposedStop?
    @State private var error: String?

    private var region: Region { store.region }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar.padding(.top, 8)
                    if let proposal = planner.proposal {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Seu dia, proposto").mustTitle()
                            Text(subtitle(proposal)).mustSerif(18).foregroundStyle(Color.must.secondary)
                        }
                        .padding(.top, 22)
                        miniCards(proposal).padding(.top, 22)
                        stopsCard(proposal).padding(.top, -14)
                        explanation(proposal).padding(.top, -14).padding(.horizontal, 12)
                        if let error { Text(error).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D)).padding(.top, 8) }
                    }
                    Color.clear.frame(height: 190)
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
            actions
        }
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .custom([
                    Blob(cx: 345, cy: 170, rx: 95, ry: 70, rotation: -20, fill: .green),
                    Blob(cx: 10, cy: 250, rx: 60, ry: 45, rotation: 10, fill: .blue),
                ]))
            }
            .ignoresSafeArea()
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "debugScreen") == "trocar" {
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

    // MARK: Topo

    private var topBar: some View {
        HStack {
            IconButton(.voltar, style: .glass, label: "Voltar") { dismiss() }
            Spacer()
            Micro("\(PlaceHours.weekdayShort[region.calendar.component(.weekday, from: planner.date) - 1]) · \(region.shortDay(planner.date)) · \((planner.intent.kind ?? planner.kind).label)")
            Spacer()
            IconButton(.outraProposta, style: .glass, label: "Outra proposta") {
                withAnimation(.snappy) {
                    planner.reshuffle(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                                      location: services.location.current)
                }
            }
        }
    }

    private func subtitle(_ p: DayProposal) -> String {
        let budget = p.request.intent.budget ?? p.request.budget
        let stops = p.stops.count == 1 ? "1 parada" : "\(p.stops.count) paradas"
        let fit = p.predictedSpend <= budget ? "dentro dos \(region.money(budget))" : "\(region.money(p.predictedSpend - budget)) acima da meta"
        return "\(stops) · \(Walk.kmText(p.walkKm)) a pé · \(fit)"
    }

    private func miniCards(_ p: DayProposal) -> some View {
        HStack(spacing: 10) {
            mini("previsto", region.money(p.predictedSpend), fill: AnyShapeStyle(MustColor.eat.gradient), text: MustColor.eat.text)
            mini("andar", Walk.kmText(p.walkKm), fill: AnyShapeStyle(MustGradient.sky(opacity: (1, 0.95))), text: Color.must.blueText)
            mini("metrô", "\(p.transitLegs)×", fill: AnyShapeStyle(Color.must.surface2), text: Color.must.secondary)
        }
    }

    private func mini(_ label: String, _ value: String, fill: AnyShapeStyle, text: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Micro(label, color: text)
            Text(value).font(.must.mono(20, .semibold)).foregroundStyle(Color.must.ink).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Paradas

    private func stopsCard(_ p: DayProposal) -> some View {
        VStack(spacing: 0) {
            if p.stops.isEmpty {
                Text("Nada coube hoje. Tenta outro tipo de dia, mais orçamento ou ligar mais listas.").mustMeta().padding(.vertical, 24)
            }
            ForEach(Array(p.stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 && !stop.isAnchor && !p.stops[index - 1].isAnchor { RowDivider() }
                row(stop)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
    }

    private func row(_ stop: ProposedStop) -> some View {
        let p = stop.place
        var meta: [String] = []
        if stop.isAnchor {
            meta.append("âncora")
            if stop.isException { meta.append("\(p.cost > 0 ? region.money(p.cost) : "") fora do dia") }
        } else {
            meta.append(listName(p))
            if let sub = p.sub { meta.append(sub) }
            if let q = p.queueMinutes, q > 0 { meta.append("fila ~\(q) min") }
            else if ["só hoje", "antes da multidão", "você pediu"].contains(stop.reason) { meta.append(stop.reason) }
            if p.price != nil { meta.append(region.money(p.cost)) }
            if stop.isException { meta.append("fora da meta") }
        }
        return HStack(alignment: .center, spacing: 14) {
            Text(region.timeString(stop.at))
                .font(.must.mono(15, stop.isAnchor ? .semibold : .regular))
                .foregroundStyle(stop.isAnchor ? Color.must.blueText : Color.must.secondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(p.name).mustPlace().lineLimit(1)
                    if stop.isAnchor {
                        Tag("reserva", style: .dark)
                    } else if p.role == .eat, stop.window.isMeal {
                        Text(stop.window.label).font(.must.archivo(12, .semibold)).foregroundStyle(MustColor.eat.text)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(MustColor.eat.light))
                    }
                }
                Text(meta.joined(separator: " · "))
                    .font(.must.archivo(13))
                    .foregroundStyle(stop.isAnchor ? Color.must.blueText : Color.must.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if stop.isAnchor {
                MustIconView(.reservaAncora, size: 18).foregroundStyle(Color.must.blueText).frame(width: 40)
                    .accessibilityLabel("Reserva fixa")
            } else {
                IconButton(.trocar, label: "Trocar \(p.name)") { swapping = stop }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, stop.isAnchor ? 14 : 0)
        .background {
            if stop.isAnchor {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0xCFE3FF)).padding(.horizontal, -4)
            }
        }
        .padding(.horizontal, stop.isAnchor ? -14 : 0)
        .contentShape(Rectangle())
        .onTapGesture { router.push(.place(id: p.id), on: router.tab) }
    }

    private func listName(_ p: SolverPlace) -> String {
        places.first { $0.id == p.id }?.list?.displayName ?? "Must \(p.listId)"
    }

    private func explanation(_ p: DayProposal) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MustIconView(.assistente, size: 16)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(MustGradient.avatar))
            Text(p.explanation).mustSerif(19).foregroundStyle(Color.must.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 22)
        .rotationEffect(.degrees(1))
    }

    // MARK: Ações

    private var actions: some View {
        HStack(spacing: 10) {
            GhostButton("Ajustar") { dismiss() }.frame(width: 120)
            PrimaryButton("Aceitar o dia", icon: .ok, iconTrailing: true) { accept() }
                .disabled(planner.proposal?.stops.isEmpty ?? true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 92)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
        }
    }

    private func accept() {
        do {
            try planner.accept(context: context)
            router.paths[.hoje] = []
            router.paths[.inicio] = []
            router.tab = .hoje
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
