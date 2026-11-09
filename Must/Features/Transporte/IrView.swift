import CoreLocation
import SwiftData
import SwiftUI

/// Um passo numerado do Ir.
struct IrStep: Hashable, Identifiable {
    var id: Int
    var title: String
    var subtitle: String?
    /// Passo do que tem no caminho (caixa antes de lugar só-cash).
    var onTheWay = false
}

/// Passos do Ir (puro, testável): os do trajeto escolhido, o caixa antes de um lugar só-cash e a chegada com a porta.
enum IrSteps {
    static func build(option: TravelOption?, placeName: String, cashOnly: Bool, doorNote: String?, region: Region,
                      arrives: Date?) -> [IrStep] {
        var steps: [IrStep] = []
        if let option {
            for step in option.steps {
                if step.kind == .transit {
                    let line = (step.lineName ?? step.agency ?? "Transporte").replacingOccurrences(of: " Line", with: "")
                    var sub: [String] = []
                    if let from = step.from?.name { sub.append("embarque em \(from)") }
                    if let count = step.stopCount { sub.append("\(count) parada\(count == 1 ? "" : "s")") }
                    if let to = step.to?.name { sub.append("desça em \(to)") }
                    steps.append(IrStep(id: steps.count + 1, title: line + (step.headsign.map { " · sentido \($0)" } ?? ""),
                                        subtitle: sub.joined(separator: " · ")))
                } else {
                    steps.append(IrStep(id: steps.count + 1, title: step.instruction ?? "Siga a pé",
                                        subtitle: "\(step.minutes) min · \(step.meters) m"))
                }
            }
            if option.steps.isEmpty {
                let title: String = switch option.mode {
                case .walk: "A pé até o \(placeName)"
                case .transit: "Trem e metrô até o \(placeName)"
                case .taxi: "Táxi até o \(placeName)"
                }
                let sub: String = switch option.mode {
                case .walk: "\(option.minutes) min · \(Walk.distanceText(Double(option.meters)))"
                case .transit: "\(option.minutes) min · linhas e plataformas no Apple Maps"
                case .taxi: "\(option.minutes) min" + (option.fare.map { " · \(region.money($0)) estimado" } ?? "")
                }
                steps.append(IrStep(id: steps.count + 1, title: title, subtitle: sub))
            }
        }
        if cashOnly {
            let atm = region.profile.money?.atmLine ?? "Passe num caixa no caminho"
            steps.append(IrStep(id: steps.count + 1, title: atm, subtitle: "saque antes: o \(placeName) é só cash", onTheWay: true))
        }
        let arrival = arrives.map { "chega \(region.timeString($0))" }
        steps.append(IrStep(id: steps.count + 1, title: "\(placeName)" + (doorNote == nil ? "" : ": a porta"),
                            subtitle: [doorNote, arrival].compactMap { $0 }.joined(separator: " · ")))
        return steps
    }

    /// Rótulo do modo nas pílulas: "A pé · 9 min", "Marunouchi · 6 min · ¥ 180", "Táxi · ¥ 900".
    static func pill(_ option: TravelOption, region: Region) -> String {
        switch option.mode {
        case .walk: return "A pé · \(option.minutes) min"
        case .transit:
            let line = option.steps.first { $0.kind == .transit }.flatMap { $0.lineShort ?? $0.lineName }?
                .replacingOccurrences(of: " Line", with: "") ?? "Metrô"
            return ([line, "\(option.minutes) min"] + [option.fare.map { region.money($0) }].compactMap { $0 }).joined(separator: " · ")
        case .taxi:
            return "Táxi · " + (option.fare.map { region.money($0) } ?? "\(option.minutes) min")
        }
    }
}

/// Ir (V9, prompt 32 Fase 2): destino, "saia às"/"saia agora", modo e tempo, passos e os botões do Apple Maps / Google Maps.
/// Lista nativa, fundo do sistema. A lógica (Routes com cache e fake, MapKit, estimativa, deep links) é a do Como chegar
/// (`ComoChegarModel`); a tela desenha o destino na hora (do board, sem rede) e troca a estimativa quando a rota chega.
struct IrView: View {
    var placeId: String

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model: ComoChegarModel?
    @State private var stop: DayStop?
    @State private var leaveAt: Date?

    private var region: Region { store.region }
    private var place: Place? { places.first { $0.id == placeId } }

    var body: some View {
        Group {
            if let place { content(place) } else { ContentUnavailableView("Lugar não encontrado", systemImage: "mappin.slash") }
        }
        .navigationTitle("Ir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { V9OfflineChip() } }
        .v9Screen(grouped: true)
        .task(id: placeId) { await prepare() }
    }

    /// Abre o modelo primeiro (a tela desenha na hora) e só depois lê o dia aceito, que decodifica o plano na main.
    private func prepare() async {
        guard let place, model == nil else { return }
        let now = AppClock.now
        let anchor = ComoChegarView.anchor(for: place, now: now, meeting: false, calendar: region.calendar)
        let m = ComoChegarModel(placeName: place.name, destination: place.coordinate, region: region, anchor: anchor,
                                doorNote: ComoChegarModel.doorLine(place.notes), now: now)
        model = m
        await Task.yield()
        // A parada do dia com este lugar: dá o "saia às" do plano.
        let clock = DayClock.read(engine: engine, region: region, context: context, at: now, position: services.location.current?.coordinate)
        if let plan = clock.plan, let s = plan.stops.first(where: { $0.placeId == placeId }) {
            stop = s
            leaveAt = clock.now.flatMap { $0.current.id == s.id ? ($0.arriveBy ?? $0.leaveAt) : nil }
        }
        await m.load(origin: origin(), routes: services.routes, now: now)
        // Perto (até 15 min a pé), abre em "a pé", como no design.
        if let walk = m.options.first(where: { $0.mode == .walk }), walk.minutes <= 15 { m.selected = .walk }
    }

    private func origin() -> CLLocationCoordinate2D? {
        if let here = services.location.current?.coordinate { return here }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)
        return city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
    }

    /// A pé, metrô, táxi (a ordem do design).
    static func order(_ mode: TravelOption.Mode) -> Int {
        switch mode {
        case .walk: 0
        case .transit: 1
        case .taxi: 2
        }
    }

    private func subline(_ option: TravelOption?) -> String {
        guard let option else { return "calculando…" }
        let source = option.source == .estimate ? "estimativa" : nil
        switch option.mode {
        case .walk: return [Walk.distanceText(Double(option.meters)), "a pé", source].compactMap { $0 }.joined(separator: " · ")
        case .transit:
            return [option.transfers == 0 ? "sem baldeação" : "\(option.transfers) baldeação", source].compactMap { $0 }.joined(separator: " · ")
        case .taxi: return [option.fare.map { "\(region.money($0)) estimado" }, source].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// "Saia às 14:16" / "Saia agora": hora do plano, ou agora + trajeto quando não há dia.
    private func leaveText(_ model: ComoChegarModel) -> (text: String, now: Bool) {
        let at = leaveAt ?? model.departs
        let now = AppClock.now
        return (DayClock.actionText(verb: "Saia", at: at, now: now, region: region), at <= now)
    }

    private func content(_ place: Place) -> some View {
        let option = model?.selectedOption
        let cash = CashOnly.detect(place.notes, stop?.note, stop?.label)
        let steps = model.map {
            IrSteps.build(option: option, placeName: place.name, cashOnly: cash, doorNote: $0.doorNote,
                          region: region, arrives: option == nil ? nil : $0.arrives)
        } ?? []
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(place.name).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    if let local = place.nameLocal, !local.isEmpty, local != place.name {
                        Text("\(local) · mostre ao atendente").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let model {
                        let leave = leaveText(model)
                        Text(leave.text)
                            .font(.title3.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(leave.now ? V9.accent : .primary)
                        Text(([option.map { "\($0.minutes) min" }, "chega \(region.timeString(model.arrives))"]
                              + [place.queueMinutes.map { "fila \($0) min" }]).compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        Text(subline(option)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !place.trust.coordConfirmed {
                        Label("\(PlaceTrust.coordApproximate) · confira no mapa antes de sair", systemImage: "location.slash")
                            .font(.subheadline).foregroundStyle(V9.accent)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            if let model, !model.options.isEmpty {
                Section("Como ir") {
                    ForEach(model.options.sorted { Self.order($0.mode) < Self.order($1.mode) }) { opt in
                        let on = model.selected == opt.mode
                        Button { model.selected = opt.mode } label: {
                            HStack {
                                Text(IrSteps.pill(opt, region: region)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if on { Image(systemName: "checkmark").foregroundStyle(V9.accent).accessibilityHidden(true) }
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            } else if model?.loading ?? true {
                Section { HStack(spacing: 10) { ProgressView(); Text("Calculando o trajeto…").foregroundStyle(.secondary) } }
            }
            if !steps.isEmpty {
                Section("Passo a passo") {
                    ForEach(steps) { step in stepRow(step) }
                }
            }
            if model != nil {
                Section("Aviso de saída") {
                    Label {
                        Text("Live Activity \"saia às\" na tela bloqueada, a partir do dia aceito. Desligar em Ajustes.")
                            .font(.subheadline)
                    } icon: { Image(systemName: "bell").foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if let model { actions(model) } }
    }

    private func stepRow(_ step: IrStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.id)").font(.subheadline.weight(.bold)).monospacedDigit()
                .frame(width: 28, height: 28)
                .background(step.id == 1 ? V9.accent : V9.fill, in: Circle())
                .foregroundStyle(step.id == 1 ? Color.white : Color.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let sub = step.subtitle, !sub.isEmpty {
                    Text(sub).font(.subheadline).foregroundStyle(step.onTheWay ? V9.accent : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func actions(_ model: ComoChegarModel) -> some View {
        let target = model.firstStop
        let mode: MapsLinks.Mode = model.selected == .walk ? .walking : target.walking ? .walking : .transit
        return VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { mapsButtons(model, target: target, mode: mode) }
                VStack(spacing: 10) { mapsButtons(model, target: target, mode: mode) }
            }
            Button {
                // Chegou: o momento passa a ser "no lugar" — o Ir sai da pilha e o Lugar entra.
                var path = router.paths[router.tab] ?? []
                if case .ir = path.last { path.removeLast() }
                path.append(.place(id: placeId))
                router.paths[router.tab] = path
            } label: { Label("Cheguei", systemImage: "checkmark").frame(maxWidth: .infinity) }
                .v9Secondary()
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    @ViewBuilder private func mapsButtons(_ model: ComoChegarModel, target: (coordinate: CLLocationCoordinate2D, walking: Bool),
                                          mode: MapsLinks.Mode) -> some View {
        Button { MapsLinks.openApple(to: target.coordinate, name: model.placeName, mode: mode) } label: {
            Label("Apple Maps", systemImage: "map").frame(maxWidth: .infinity)
        }.v9Primary()
        Button { MapsLinks.openGoogle(to: target.coordinate, mode: mode) } label: {
            Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond").frame(maxWidth: .infinity)
        }.v9Secondary()
    }
}
