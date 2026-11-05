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
            let atm = region == .jp ? "Caixa 7 Bank no 7-Eleven do caminho" : "Passe num caixa no caminho"
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

/// 13 · Ir (prompt 23 §2, `Transporte.png`). Tinta. Numeral "N minutos", modos (a pé/metrô/táxi), passos numerados
/// com o que tem no caminho, "saia às" e Apple Maps / Cheguei. A lógica (Routes com cache e fake, MapKit, estimativa,
/// deep links) é a do Como chegar (`ComoChegarModel`); abre com a estimativa e troca quando a rota chega.
struct IrView: View {
    var placeId: String

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model: ComoChegarModel?
    @State private var stop: DayStop?
    @State private var leaveAt: Date?

    private var region: Region { store.region }
    private var place: Place? { places.first { $0.id == placeId } }

    var body: some View {
        Group {
            if let model, let place { content(model, place: place) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                V8.ink
                Rings(color: V8.white, count: 1, diameter: 560, opacity: 0.28, offset: CGSize(width: -60, height: -120))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: placeId) { await prepare() }
    }

    private func prepare() async {
        guard let place, model == nil else { return }
        let now = AppClock.now
        // A parada do dia com este lugar: dá o "saia às" do plano.
        if let plan = engine.plan(for: region.calendar.startOfDay(for: now), region: region, context: context),
           let s = plan.stops.first(where: { $0.placeId == placeId }) {
            stop = s
            leaveAt = engine.now(in: plan, at: now).flatMap { $0.current.id == s.id ? ($0.arriveBy ?? $0.leaveAt) : nil }
        }
        let anchor = ComoChegarView.anchor(for: place, now: now, meeting: false, calendar: region.calendar)
        let m = ComoChegarModel(placeName: place.name, destination: place.coordinate, region: region, anchor: anchor,
                                doorNote: ComoChegarModel.doorLine(place.notes), now: now)
        model = m
        await m.load(origin: origin(), routes: services.routes, now: now)
        // Perto (até 15 min a pé), abre em "a pé", como no design.
        if let walk = m.options.first(where: { $0.mode == .walk }), walk.minutes <= 15 { m.selected = .walk }
    }

    private func origin() -> CLLocationCoordinate2D? {
        if let here = services.location.current?.coordinate { return here }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)
        return city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
    }

    private func content(_ model: ComoChegarModel, place: Place) -> some View {
        let option = model.selectedOption
        let minutes = option?.minutes ?? 0
        let cash = CashOnly.detect(place.notes, stop?.note, stop?.label)
        let steps = IrSteps.build(option: option, placeName: place.name, cashOnly: cash, doorNote: model.doorNote,
                                  region: region, arrives: option == nil ? nil : model.arrives)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    RoundButton(systemImage: "chevron.left", label: "Voltar", style: .line, tint: V8.white) { dismiss() }
                    Spacer(minLength: 12)
                    SpecStack(lines: ["Ir · \(modeWord(option?.mode))",
                                      (["chega \(region.timeString(model.arrives))"]
                                       + [place.queueMinutes.map { "fila \($0) min" }].compactMap { $0 }).joined(separator: " · ")],
                              color: V8.muteDark, alignment: .trailing)
                        .padding(.top, 4)
                }
                .padding(.top, 10)

                HStack(alignment: .center, spacing: 12) {
                    BigNumeral("\(minutes)", size: minutes < 10 ? 190 : minutes < 100 ? 130 : 96, color: V8.orange)
                        .fixedSize()
                        .padding(.leading, -8)
                        .redacted(reason: model.loading && model.options.isEmpty ? .placeholder : [])
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel(minutes == 1 ? "minuto" : "minutos", size: 10.5, color: V8.orange)
                        Text("até o \(place.name)")
                            .font(V8Font.display(30))
                            .foregroundStyle(V8.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        Text(subline(option))
                            .font(V8Font.text(14))
                            .foregroundStyle(V8.muteDark)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(minutes) minutos até o \(place.name)")

                modes(model).padding(.top, 26)

                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        if i > 0 { Rectangle().fill(V8.white.opacity(0.12)).frame(height: 1) }
                        stepRow(step, first: i == 0)
                    }
                }
                .padding(.top, 22)

                leaveCard(model).padding(.top, 26)
                Color.clear.frame(height: 200)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { actions(model, place: place) }
    }

    /// A pé, metrô, táxi (a ordem do design).
    static func order(_ mode: TravelOption.Mode) -> Int {
        switch mode {
        case .walk: 0
        case .transit: 1
        case .taxi: 2
        }
    }

    private func modeWord(_ mode: TravelOption.Mode?) -> String {
        switch mode {
        case .walk, nil: "a pé"
        case .transit: "metrô"
        case .taxi: "táxi"
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

    private func modes(_ model: ComoChegarModel) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.options.sorted { Self.order($0.mode) < Self.order($1.mode) }) { option in
                    let on = model.selected == option.mode
                    Button { model.selected = option.mode } label: {
                        Text(IrSteps.pill(option, region: region))
                            .font(V8Font.text(14, weight: .semibold))
                            .foregroundStyle(on ? V8.ink : V8.white)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Capsule().fill(on ? V8.orange : .clear))
                            .overlay(Capsule().strokeBorder(on ? .clear : V8.white.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(MustPressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func stepRow(_ step: IrStep, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(step.id)")
                .font(V8Font.text(15, weight: .bold))
                .foregroundStyle(first ? V8.ink : V8.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(first ? V8.orange : .clear))
                .overlay(Circle().strokeBorder(first ? .clear : V8.white.opacity(0.6), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(V8Font.text(16, weight: .semibold))
                    .foregroundStyle(V8.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = step.subtitle, !sub.isEmpty {
                    Text(sub).font(V8Font.text(13)).foregroundStyle(step.onTheWay ? V8.orange : V8.muteDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// "Aviso quando for hora de sair": o "saia às" do plano (ou agora + o trajeto, sem plano).
    private func leaveCard(_ model: ComoChegarModel) -> some View {
        HStack(spacing: 14) {
            Text(region.timeString(leaveAt ?? model.departs))
                .font(V8Font.mono(22)).fontWeight(.semibold)
                .foregroundStyle(V8.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aviso quando for hora de sair").font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.white)
                // TODO(v8:B): Live Activity "saia às" (o motor/LiveActivity do B liga este cartão).
                Text("Live Activity na tela bloqueada · desligar em Ajustes").font(V8Font.text(12.5)).foregroundStyle(V8.muteDark)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(V8.graphite))
    }

    private func actions(_ model: ComoChegarModel, place: Place) -> some View {
        HStack(spacing: 10) {
            BigButton(title: "Apple Maps", style: .line, lineColor: V8.white) {
                let target = model.firstStop
                MapsLinks.openApple(to: target.coordinate, name: model.placeName,
                                    mode: model.selected == .walk ? .walking : target.walking ? .walking : .transit)
            }
            BigButton(title: "Cheguei", style: .orange, systemImage: "checkmark") {
                // Chegou: o momento passa a ser "no lugar" — o Ir sai da pilha e o Lugar entra.
                var path = router.paths[router.tab] ?? []
                if case .ir = path.last { path.removeLast() }
                path.append(.place(id: placeId))
                router.paths[router.tab] = path
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 92)
        .background {
            LinearGradient(colors: [V8.ink.opacity(0), V8.ink], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
