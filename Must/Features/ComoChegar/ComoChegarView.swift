import CoreLocation
import SwiftData
import SwiftUI

/// Como chegar (V9, prompt 32 Fase 2): origem → destino, "sai/chega", alternativas, passos com a cor da linha e a porta
/// (Street View). Lista nativa; abre pelo "Ir agora" do Lugar, pelo Ingresso ("Ir ao encontro") e pelo Hoje.
struct ComoChegarView: View {
    var placeId: String
    var meeting = false

    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model: ComoChegarModel?

    private var region: Region { store.region }
    private var place: Place? { places.first { $0.id == placeId } }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                List { Section { HStack(spacing: 10) { ProgressView(); Text("Calculando o trajeto…").foregroundStyle(.secondary) } } }
            }
        }
        .navigationTitle("Como chegar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { V9OfflineChip() }
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.swapEnds(routes: services.routes) } } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("Inverter origem e destino")
                }
            }
        }
        .v9Screen(grouped: true)
        .task(id: placeId) { await prepare() }
    }

    private func prepare() async {
        guard let place, model == nil else { return }
        let now = AppClock.now
        let anchor = Self.anchor(for: place, now: now, meeting: meeting, calendar: region.calendar)
        let destination = meeting ? (place.extra?.experience?.meetingCoordinate.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? place.coordinate) : place.coordinate
        let m = ComoChegarModel(placeName: place.name, destination: destination, region: region, anchor: anchor,
                                doorNote: ComoChegarModel.doorLine(place.notes), now: now)
        model = m
        await m.load(origin: origin(), routes: services.routes, now: now)
    }

    /// Onde estou (GPS ou a posição simulada); sem GPS, o centro da cidade do dia.
    private func origin() -> CLLocationCoordinate2D? {
        if let here = services.location.current?.coordinate { return here }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)
        return city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
    }

    /// Reserva futura do lugar, ou o ingresso que vem (o do encontro, quando for "Ir ao encontro").
    static func anchor(for place: Place, now: Date, meeting: Bool, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: now)
        if let reservation = place.reservation, reservation.at >= start { return reservation.at }
        return place.tickets.filter { $0.at >= start }.min { $0.at < $1.at }?.at
    }

    // MARK: Conteúdo

    private func content(_ model: ComoChegarModel) -> some View {
        let option = model.selectedOption
        let from = ComoChegarModel.originLabel(hasGPS: services.location.current != nil, cityName: nil)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.reversed ? "\(model.placeName) → \(from)" : "\(from) → \(model.placeName)")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(region.timeString(model.departs))
                        Image(systemName: "arrow.right").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(region.timeString(model.arrives))
                    }
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
                    .redacted(reason: model.loading && model.options.isEmpty ? .placeholder : [])
                    Text(chips(model, option)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let place, !place.trust.coordConfirmed {
                        Label("\(PlaceTrust.coordApproximate) · confira no mapa antes de sair", systemImage: "location.slash")
                            .font(.subheadline).foregroundStyle(V9.accent)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            if !model.options.isEmpty {
                Section("Como ir") {
                    ForEach(model.options) { opt in
                        let on = model.selected == opt.mode
                        Button { model.selected = opt.mode } label: {
                            HStack {
                                Text(Self.altLabel(opt, region: region)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text("\(opt.minutes) min").monospacedDigit().foregroundStyle(.secondary)
                                if on { Image(systemName: "checkmark").foregroundStyle(V9.accent).accessibilityHidden(true) }
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if let option {
                Section("Passo a passo · \(Self.sourceLabel(option.source))") {
                    ForEach(Array(option.steps.enumerated()), id: \.offset) { index, step in
                        StepRow(step: step, first: index == 0, region: region, departs: model.departs)
                    }
                    if option.mode == .transit, option.steps.isEmpty {
                        StepRow(transitMinutes: option.minutes, region: region, departs: model.departs)
                    }
                    if option.mode == .taxi {
                        StepRow(step: TravelStep(id: 0, kind: .walk, instruction: "Táxi até o lugar · \(option.minutes) min",
                                                 minutes: option.minutes, meters: option.meters), first: true, region: region,
                                taxiFare: option.fare.map { region.money($0) + " estimado" })
                    }
                    StepRow(end: model.placeName, time: model.arrives, region: region, source: option.source, mode: option.mode)
                }
            }
            if let card = model.card {
                Section("A porta · Street View") { StreetViewCardView(card: card, placeName: model.placeName) }
            }
        }
        .safeAreaInset(edge: .bottom) { actions(model) }
    }

    private func chips(_ model: ComoChegarModel, _ option: TravelOption?) -> String {
        var parts = ["\(option?.minutes ?? 0) min"]
        if let option, option.mode == .transit, option.source == .routes {
            parts.append(option.transfers == 0 ? "sem baldeação" : "\(option.transfers) baldeação\(option.transfers > 1 ? "ões" : "")")
            if let fare = option.fare, let currency = option.fareCurrency {
                parts.append("\(region.money(fare)) · \(currency == "JPY" ? "Suica" : "tarifa")")
            }
        }
        if let slack = model.slackMinutes { parts.append("\(slack) min antes da reserva") }
        return parts.joined(separator: " · ")
    }

    static func altLabel(_ option: TravelOption, region: Region) -> String {
        switch option.mode {
        case .transit: "Metrô"
        case .walk: "A pé"
        case .taxi: option.fare != nil ? "Táxi · \(region.money(option.fare ?? 0))" : "Táxi"
        }
    }

    /// De onde veio o tempo da alternativa escolhida (no Japão o transporte é sempre Apple Maps).
    static func sourceLabel(_ source: TravelOption.Source?) -> String {
        switch source {
        case .mapKit: "apple maps"
        case .estimate: "estimativa"
        default: "routes"
        }
    }

    private func actions(_ model: ComoChegarModel) -> some View {
        let target = model.firstStop
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons(model, target: target) }
            VStack(spacing: 10) { buttons(model, target: target) }
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    @ViewBuilder private func buttons(_ model: ComoChegarModel, target: (coordinate: CLLocationCoordinate2D, walking: Bool)) -> some View {
        Button { MapsLinks.openApple(to: target.coordinate, name: model.placeName, mode: target.walking ? .walking : .transit) } label: {
            Label("Começar", systemImage: "arrow.triangle.turn.up.right.diamond").frame(maxWidth: .infinity)
        }
        .v9Primary()
        Menu {
            Button("Apple Maps · transporte") { MapsLinks.openApple(to: model.end, name: model.placeName, mode: .transit) }
            Button("Apple Maps · a pé") { MapsLinks.openApple(to: model.end, name: model.placeName) }
            Button("Google Maps") { MapsLinks.openGoogle(to: model.end, mode: .transit) }
        } label: {
            Label("Outros mapas", systemImage: "ellipsis.circle").frame(maxWidth: .infinity)
        }
        .v9Secondary()
    }
}

// MARK: - Passos

private struct StepRow: View {
    var time: Date?
    var title: String
    var subtitle: String?
    var kind: TravelStep.Kind
    var color: Color
    var lineShort: String?
    var textColor: Color
    var last: Bool
    var region: Region?
    var extraTag: String?

    init(step: TravelStep, first: Bool, region: Region, departs: Date? = nil, taxiFare: String? = nil) {
        let stops = step.from
        time = stops?.departs ?? (step.kind == .walk && first ? departs : nil)
        kind = step.kind
        lineShort = step.lineShort
        last = false
        self.region = region
        if step.kind == .transit {
            let headsign = step.headsign.map { " · sentido \($0)" } ?? ""
            title = "\(Self.lineTitle(step))\(headsign)"
            var parts: [String] = []
            if let from = step.from, let departs = from.departs { parts.append(region.timeString(departs)) }
            if let to = step.to, let arrives = to.arrives { parts.append(region.timeString(arrives)) }
            if let count = step.stopCount { parts.append("\(count) parada\(count == 1 ? "" : "s")") }
            subtitle = parts.joined(separator: " · ")
            extraTag = nil
        } else {
            title = step.instruction ?? "A pé · \(step.minutes) min"
            subtitle = "\(step.minutes) min a pé · \(step.meters) m"
            extraTag = taxiFare
        }
        color = step.colorHex.flatMap(Color.fromRoutesHex) ?? Color.secondary
        textColor = step.textColorHex.flatMap(Color.fromRoutesHex) ?? .white
    }

    /// Transporte só com o tempo (MapKit; no Japão é sempre assim): linhas e plataformas ficam no Apple Maps.
    init(transitMinutes: Int, region: Region, departs: Date) {
        time = departs
        title = "Trem e metrô · \(transitMinutes) min"
        subtitle = "linhas e plataformas no Apple Maps (Começar)"
        kind = .transit
        color = Color.secondary
        textColor = .white
        lineShort = nil
        last = false
        self.region = region
        extraTag = nil
    }

    /// Chegada: o lugar, com a frase da porta.
    init(end: String, time: Date, region: Region, source: TravelOption.Source, mode: TravelOption.Mode) {
        self.time = time
        title = end
        subtitle = switch (source, mode) {
        case (.estimate, _): "estimativa · sem horário de trem"
        case (.mapKit, .transit): "chegada aproximada"
        default: "chegada"
        }
        kind = .walk
        color = Color.secondary
        textColor = .white
        lineShort = nil
        last = true
        self.region = region
        extraTag = nil
    }

    private static func lineTitle(_ step: TravelStep) -> String {
        let name = step.lineName ?? step.agency ?? "Transporte"
        return name.replacingOccurrences(of: " Line", with: "").replacingOccurrences(of: " line", with: "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time.flatMap { region?.timeString($0) } ?? "")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .lineLimit(1).fixedSize()
                .frame(minWidth: 48, alignment: .leading)
            marker
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let extraTag { Text(extraTag).font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var marker: some View {
        if kind == .transit, let lineShort {
            Text(lineShort).font(.caption2.weight(.bold)).foregroundStyle(textColor)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 26, height: 26).background(Circle().fill(color))
        } else {
            Image(systemName: last ? "mappin.circle.fill" : kind == .transit ? "tram.fill" : "figure.walk")
                .font(.title3).foregroundStyle(last ? V9.accent : .secondary).frame(width: 26, height: 26)
        }
    }
}

// MARK: - Porta (Street View)

private struct StreetViewCardView: View {
    var card: StreetViewCard
    var placeName: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = UIImage(contentsOfFile: card.imageFile.path()) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Foto da porta de \(placeName)")
            }
            if let caption = card.caption { Text(caption).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }
            Text("Foto de \(card.date ?? "") · \(card.copyright)").font(.footnote).foregroundStyle(.secondary)
            Button { openURL(card.viewURL) } label: { Label("Ver 360°", systemImage: "view.3d") }.buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

extension Color {
    /// "#b5b5ac" (cor da linha, Routes) → cor. Inválido → nil.
    static func fromRoutesHex(_ text: String) -> Color? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return Color(hex: value)
    }
}
