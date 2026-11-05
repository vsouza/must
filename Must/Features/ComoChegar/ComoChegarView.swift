import CoreLocation
import SwiftData
import SwiftUI

/// Como chegar (prompt 17 · A): origem → destino, horários grandes, alternativas, passos com a cor da linha e a porta (Street View).
/// Abre pelo "Ir agora" do Lugar, pelo Ingresso ("Ir ao encontro") e pelo Hoje.
struct ComoChegarView: View {
    var placeId: String
    var meeting = false

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model: ComoChegarModel?

    private var region: Region { store.region }
    private var place: Place? { places.first { $0.id == placeId } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 360, cy: 150, rx: 80, ry: 46, rotation: -12, fill: .green, opacity: 0.7),
                Blob(cx: 30, cy: 720, rx: 66, ry: 56, rotation: 10, fill: .blue, opacity: 0.6),
            ]))
            if let model {
                content(model)
            } else {
                Micro("calculando o trajeto…").padding(.top, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar(model)
                route(model)
                times(model)
                chips(model)
                alternatives(model)
                StepsCard(model: model, region: region)
                if let card = model.card {
                    StreetViewCardView(card: card, placeName: model.placeName)
                }
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { actions(model) }
    }

    /// De onde veio o tempo da alternativa escolhida (no Japão o transporte é sempre Apple Maps).
    static func sourceLabel(_ source: TravelOption.Source?) -> String {
        switch source {
        case .mapKit: "apple maps"
        case .estimate: "estimativa"
        default: "routes"
        }
    }

    private func topBar(_ model: ComoChegarModel) -> some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("como chegar · " + Self.sourceLabel(model.selectedOption?.source))
            Spacer()
            Button {
                Task { await model.swapEnds(routes: services.routes) }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.must.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.must.surface2))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Inverter origem e destino")
        }
        .padding(.top, 8)
    }

    private func route(_ model: ComoChegarModel) -> some View {
        let from = ComoChegarModel.originLabel(hasGPS: services.location.current != nil, cityName: nil)
        let to = model.placeName
        return Text(model.reversed ? "\(to) → \(from)" : "\(from) → \(to)")
            .mustSerif(20)
            .foregroundStyle(Color.must.secondary)
            .lineLimit(1)
            .padding(.top, 10)
    }

    private func times(_ model: ComoChegarModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(region.timeString(model.departs)).font(.must.mono(40, .bold))
            Text("→").font(.must.mono(20)).foregroundStyle(Color.must.secondary)
            Text(region.timeString(model.arrives)).font(.must.mono(40, .bold))
        }
        .foregroundStyle(Color.must.ink)
        .monospacedDigit()
        .redacted(reason: model.loading && model.options.isEmpty ? .placeholder : [])
    }

    private func chips(_ model: ComoChegarModel) -> some View {
        let option = model.selectedOption
        return FlowLayout(spacing: 8) {
            Tag("\(option?.minutes ?? 0) min", style: .dark)
            if let option, option.mode == .transit, option.source == .routes {
                Tag(option.transfers == 0 ? "sem baldeação" : "\(option.transfers) baldeação\(option.transfers > 1 ? "ões" : "")")
                if let fare = option.fare, let currency = option.fareCurrency {
                    Tag("\(region.money(fare)) · \(currency == "JPY" ? "Suica" : "tarifa")")
                }
            }
            if let slack = model.slackMinutes {
                Tag("\(slack) min antes da reserva", style: .green)
            }
        }
    }

    private func alternatives(_ model: ComoChegarModel) -> some View {
        HStack(spacing: 8) {
            ForEach(model.options) { option in
                AlternativeTile(option: option, selected: model.selected == option.mode, region: region) {
                    model.selected = option.mode
                }
            }
        }
    }

    @ViewBuilder private func actions(_ model: ComoChegarModel) -> some View {
        HStack(spacing: 10) {
            PrimaryButton("Começar", icon: .rota, style: .dark) {
                let target = model.firstStop
                MapsLinks.openApple(to: target.coordinate, name: model.placeName, mode: target.walking ? .walking : .transit)
            }
            .frame(maxWidth: .infinity)
            Menu {
                Button("Apple Maps · transporte") { MapsLinks.openApple(to: model.end, name: model.placeName, mode: .transit) }
                Button("Apple Maps · a pé") { MapsLinks.openApple(to: model.end, name: model.placeName) }
                Button("Google Maps") { MapsLinks.openGoogle(to: model.end, mode: .transit) }
            } label: {
                Text("Maps ↗")
                    .font(.must.archivo(16, .bold))
                    .foregroundStyle(Color.must.ink)
                    .frame(width: 120, height: 56)
                    .overlay(Capsule().stroke(Color.must.lineStrong, lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 24) // sem barra de abas nesta tela (`AppRouter.hidesNavBar`)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Alternativas

private struct AlternativeTile: View {
    var option: TravelOption
    var selected: Bool
    var region: Region
    var action: () -> Void

    private var label: String {
        switch option.mode {
        case .transit: "metrô"
        case .walk: "a pé"
        case .taxi: "táxi"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.mode == .taxi && option.fare != nil ? "\(label) · \(region.money(option.fare ?? 0))" : label)
                    .font(.must.meta)
                    .lineLimit(1)
                Text("\(option.minutes) min").font(.must.mono(18, .bold)).monospacedDigit()
            }
            .foregroundStyle(selected ? Color.white : Color.must.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(selected ? Color.must.ink : Color.must.surface2))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Passos

/// Passos com trilho vertical: a pé (pontilhado), transporte (cor oficial da linha + selo).
private struct StepsCard: View {
    var model: ComoChegarModel
    var region: Region

    var body: some View {
        VStack(spacing: 0) {
            if let option = model.selectedOption {
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
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.must.line, lineWidth: 1))
    }
}

private struct StepRow: View {
    var time: Date?
    var title: String
    var subtitle: String?
    var kind: TravelStep.Kind
    var color: Color
    var lineShort: String?
    var textColor: Color
    var first: Bool
    var last: Bool
    var region: Region?
    var extraTag: String?

    init(step: TravelStep, first: Bool, region: Region, departs: Date? = nil, taxiFare: String? = nil) {
        let stops = step.from
        time = stops?.departs ?? (step.kind == .walk && first ? departs : nil)
        kind = step.kind
        lineShort = step.lineShort
        self.first = first
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
        color = step.colorHex.flatMap(Color.fromRoutesHex) ?? Color.must.ink
        textColor = step.textColorHex.flatMap(Color.fromRoutesHex) ?? .white
    }

    /// Transporte só com o tempo (MapKit; no Japão é sempre assim): linhas e plataformas ficam no Apple Maps.
    init(transitMinutes: Int, region: Region, departs: Date) {
        time = departs
        title = "Trem e metrô · \(transitMinutes) min"
        subtitle = "linhas e plataformas no Apple Maps (Começar)"
        kind = .transit
        color = Color.must.ink
        textColor = .white
        lineShort = nil
        first = true
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
        color = Color.must.ink
        textColor = .white
        lineShort = nil
        first = false
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
                .font(.must.mono(14, .semibold))
                .lineLimit(1).fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            rail
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.must.archivo(16, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.must.meta).foregroundStyle(Color.must.secondary)
                }
                if let extraTag {
                    Tag(extraTag)
                }
            }
            .padding(.bottom, 18)
            Spacer(minLength: 0)
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            ZStack {
                if kind == .transit, let lineShort {
                    Circle().fill(color).frame(width: 24, height: 24)
                    Text(lineShort).font(.must.mono(11, .bold)).foregroundStyle(textColor)
                } else {
                    Circle().stroke(last ? Color.must.ink : Color.must.secondary, lineWidth: 2).background(Circle().fill(last ? Color.must.ink : Color.white))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 24, height: 24)
            if !last {
                Rectangle()
                    .fill(kind == .transit ? color : Color.clear)
                    .overlay {
                        if kind == .walk { Rectangle().stroke(Color.must.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 2) }
                    }
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 24)
    }
}

// MARK: - Porta (Street View)

private struct StreetViewCardView: View {
    var card: StreetViewCard
    var placeName: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(contentsOfFile: card.imageFile.path()) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.must.surface
            }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Micro("street view · a porta").foregroundStyle(.white.opacity(0.9))
                if let caption = card.caption {
                    Text(caption).font(.must.archivo(17, .semibold)).foregroundStyle(.white)
                }
                HStack {
                    Text("foto de \(card.date ?? "") · \(card.copyright)")
                        .font(.must.mono(11))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button { openURL(card.viewURL) } label: {
                        Text("Ver 360°").font(.must.archivo(13, .bold)).foregroundStyle(Color.must.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(.white.opacity(0.9)))
                    }
                    .buttonStyle(MustPressStyle())
                }
            }
            .padding(16)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .rotationEffect(.degrees(-1))
        .accessibilityElement(children: .contain)
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
