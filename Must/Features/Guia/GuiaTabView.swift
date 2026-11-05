import CoreLocation
import SwiftData
import SwiftUI

/// Raiz da aba Guia (prompt 23 §2 · 06, `Guia.png`): o bairro do dia (motor do dia, ou o foco do dia aceito) ou onde
/// você está (tabela curada, sem rede). Os vizinhos trocam o bairro na mesma tela.
struct GuiaTabView: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Query private var days: [PlannedDay]

    var body: some View {
        GuiaAreaView(initialArea: initialArea(), showsBack: false)
            .id(store.region)
    }

    private func initialArea() -> String? {
        let region = store.region
        let today = region.calendar.startOfDay(for: AppClock.now)
        if let area = dayEngine.plan(for: today, region: region, context: context)?.area { return area }
        if let focus = days.first(where: { $0.date == today && $0.accepted })?.focusAreaId { return focus }
        let areas = AreaCatalog.areas(for: region)
        if let here = services.location.current, let area = CurrentAreaService.curated(here, in: areas) { return area.id }
        return areas.first?.id
    }
}

/// O Guia de um bairro: faixa preta com o percurso, nome, texto, vizinhos e capítulos por período.
struct GuiaAreaView: View {
    var initialArea: String?
    var showsBack = true

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var areaId: String?
    @State private var openNow = OpenNowIndex()

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var areas: [Area] { AreaCatalog.areas(for: region) }
    private var area: Area? { areas.first { $0.id == (areaId ?? initialArea) } ?? areas.first }

    var body: some View {
        let area = area
        let plan = dayEngine.plan(for: region.calendar.startOfDay(for: now), region: region, context: context)
        let assigner = AreaAssigner(areas: areas)
        let inArea = places.filter { p in
            assigner.areaId(name: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng) == area?.id
        }
        let snapshot = openNow.snapshot(for: inArea, now: now, timeZone: region.timeZone, location: services.location.current)
        let open = inArea.filter { snapshot.isOpen($0.id) }.count
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let stops = (plan?.stops ?? []).filter { stop in
            if let a = stop.area { return a == area?.id }
            guard let p = stop.placeId.flatMap({ byId[$0] }) else { return false }
            return assigner.areaId(name: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng) == area?.id
        }
        let nowStop = plan.flatMap { dayEngine.now(in: $0, at: now) }?.current
        let chapters = GuiaChapters.build(
            stops: stops, nowStopId: nowStop?.id,
            extras: inArea.sorted { ($0.isDone ? 1 : 0, $0.order) < ($1.isDone ? 1 : 0, $1.order) }.map { p in
                GuiaChapters.Extra(placeId: p.id, title: p.name, meta: GuiaAreaView.meta(p, region: region), windows: p.windows, done: p.isDone)
            },
            calendar: region.calendar, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GuiaRouteBand(points: routePoints(plan: plan, stops: stops, area: area, inArea: inArea, byId: byId, nowStopId: nowStop?.id),
                              lines: ["Guia · \(area?.name ?? region.shortName)", "\(inArea.count) musts · \(open) \(open == 1 ? "aberto" : "abertos")"],
                              showsBack: showsBack, onBack: { dismiss() }, onMap: { router.push(.mapa) })
                VStack(alignment: .leading, spacing: 0) {
                    titleRow(area).padding(.top, 22)
                    Text(GuiaBlurbs.blurb(areaId: area?.id ?? "", name: area?.name ?? "", musts: inArea.count, open: open))
                        .font(V8Font.text(17))
                        .foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    if let area, !area.neighbors.isEmpty { neighbors(area).padding(.top, 18) }
                    ForEach(chapters) { chapter in chapterView(chapter).padding(.top, 34) }
                    if chapters.isEmpty {
                        Text("Nada seu neste bairro ainda. Cole um link no + ou veja os vizinhos.")
                            .font(V8Font.text(15)).foregroundStyle(V8.mute).padding(.top, 30)
                    }
                    V8BarSpacer()
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Cabeçalho

    private func titleRow(_ area: Area?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(area?.name ?? region.displayName)
                .font(V8Font.display(50))
                .tracking(-1.6)
                .foregroundStyle(V8.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            V8SpecStack(lines: rightSpec(area), alignment: .trailing).padding(.top, 10)
        }
    }

    /// "18° · sol" / "22 min de você" (sem rede: tempo do cache e distância em linha reta).
    private func rightSpec(_ area: Area?) -> [String] {
        var lines: [String] = []
        if let h = services.sync.weather(on: now, region: region, trip: trips.first)?.hour(at: now) {
            let sky = (h.precipProb ?? 0) >= 50 ? "chuva" : ((h.cloud ?? 0) > 60 ? "nublado" : "sol")
            lines.append("\(Int(h.temp.rounded()))° \(sky)")
        }
        if let area, let here = services.location.current {
            if CurrentAreaService.curated(here, in: areas)?.id == area.id {
                lines.append("você está aqui")
            } else {
                let leg = DaySolver.leg(here.coordinate, area.centroid.clCoordinate, walkMax: 1.5)
                lines.append("\(leg.minutes) min de você")
            }
        }
        return lines
    }

    private func neighbors(_ area: Area) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(area.neighbors, id: \.areaId) { edge in
                    if let other = areas.first(where: { $0.id == edge.areaId }) {
                        Button { withAnimation(.easeOut(duration: 0.2)) { areaId = other.id } } label: {
                            HStack(spacing: 8) {
                                Text(edge.line?.code ?? "a pé")
                                    .font(V8Font.mono(10).weight(.bold))
                                    .foregroundStyle(V8.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(V8.ink))
                                Text("\(other.name) · \(edge.minutes) min")
                                    .font(V8Font.text(15, weight: .semibold))
                                    .foregroundStyle(V8.ink)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 14)
                            .frame(minHeight: 38)
                            .background(Capsule().fill(V8.white))
                            .overlay(Capsule().strokeBorder(V8.ink.opacity(0.14), lineWidth: 1))
                        }
                        .buttonStyle(MustPressStyle())
                        .accessibilityLabel("\(other.name), \(edge.minutes) minutos\(edge.line.map { " pela \($0.name)" } ?? " a pé")")
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .scrollClipDisabled()
    }

    // MARK: Capítulos

    private func chapterView(_ chapter: GuiaChapters.Chapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(chapter.period.title)
                    .font(V8Font.display(34, width: 82))
                    .tracking(-1)
                    .foregroundStyle(V8.orangeDeep)
                SpecLabel(GuiaChapters.rangeText(chapter, time: region.timeString))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(chapter.items) { item in
                    Button { if let id = item.placeId { router.push(.place(id: id)) } } label: { row(item) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(item.placeId == nil ? [] : .isButton)
                }
            }
        }
    }

    private func row(_ item: GuiaChapters.Item) -> some View {
        let place = item.placeId.flatMap { id in places.first { $0.id == id } }
        return HStack(spacing: 14) {
            if item.micro {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(V8.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 44, height: 44)
            } else {
                V8Thumb(placeId: place?.placeId, refs: place?.photoRefs ?? [], size: 44, dimmed: item.done)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                Text(item.meta).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.isNow {
                V8Tag(text: "agora", style: .orange)
            } else if let at = item.at {
                Text(region.timeString(at)).font(V8Font.mono(14).weight(.bold)).foregroundStyle(V8.ink).fixedSize()
            } else if item.done {
                SpecLabel("feito")
            }
        }
        .padding(.vertical, 9)
        .opacity(item.done ? 0.55 : 1)
        .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.12)).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Dados

    static func meta(_ place: Place, region: Region) -> String {
        var parts: [String] = []
        if let list = place.list { parts.append(list.displayName) }
        if let sub = place.sub, !sub.isEmpty { parts.append(sub.lowercased()) }
        if let q = place.queueMinutes, q > 0 { parts.append("fila ~\(q) min") }
        if let p = place.price, p > 0 { parts.append(region.money(p)) }
        return parts.prefix(3).joined(separator: " · ")
    }

    /// Pontos do percurso na faixa: as paradas do dia perto do bairro (até 3 km); sem dia, os Musts do bairro.
    private func routePoints(plan: DayPlan?, stops: [DayStop], area: Area?, inArea: [Place], byId: [String: Place],
                             nowStopId: String?) -> [GuiaRouteBand.Point] {
        guard let area else { return [] }
        let center = CLLocation(latitude: area.centroid.lat, longitude: area.centroid.lng)
        let dayPoints: [GuiaRouteBand.Point] = (plan?.stops ?? []).compactMap { stop in
            guard let p = stop.placeId.flatMap({ byId[$0] }), p.location.distance(from: center) < 3_000 else { return nil }
            return .init(id: stop.id, coordinate: p.coordinate, label: GuiaRouteBand.short(stop.label), isNow: stop.id == nowStopId,
                         small: stop.kind == .micro)
        }
        if dayPoints.count >= 2 {
            var points = dayPoints
            // Entrada do bairro vizinho (de onde se chega) quando o dia vem de fora: o primeiro vizinho no caminho.
            if let first = area.neighbors.first, let other = areas.first(where: { $0.id == first.areaId }) {
                points.insert(.init(id: "from-\(other.id)", coordinate: other.centroid.clCoordinate, label: other.name, isNow: false, small: false), at: 0)
            }
            return points
        }
        _ = stops
        return inArea.prefix(6).map { p in
            .init(id: p.id, coordinate: p.coordinate, label: GuiaRouteBand.short(p.name), isNow: false, small: false)
        }
    }
}

/// A faixa preta do topo do Guia: o percurso em laranja com as paradas (brancas; a de agora maior, laranja), a grade e
/// um arco. Desenho esquemático, offline e sem custo.
/// TODO(v8:A): com o tema escuro do mapa papel em relevo (`Must/DesignSystem/MapStyle/`), trocar este esquema pelo
/// `MapLibreView` com o percurso; até lá, "Abrir o mapa" leva ao mapa de verdade.
struct GuiaRouteBand: View {
    struct Point: Identifiable, Hashable {
        var id: String
        var coordinate: CLLocationCoordinate2D
        var label: String
        var isNow: Bool
        var small: Bool

        static func == (a: Point, b: Point) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var points: [Point]
    var lines: [String]
    var showsBack: Bool
    var onBack: () -> Void
    var onMap: () -> Void

    static func short(_ label: String) -> String {
        String(label.split(separator: "·").first ?? Substring(label)).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let projected = project(size: size)
            ZStack(alignment: .topLeading) {
                V8.ink
                grid(size: size)
                Circle()
                    .stroke(V8.white.opacity(0.28), lineWidth: 1)
                    .frame(width: size.width * 1.15, height: size.width * 1.15)
                    .position(x: size.width * 0.82, y: size.height * 0.55)
                Path { path in
                    guard let first = projected.first else { return }
                    path.move(to: first.1)
                    for p in projected.dropFirst() { path.addLine(to: p.1) }
                }
                .stroke(V8.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                ForEach(Array(projected.enumerated()), id: \.offset) { index, entry in
                    let (point, at) = entry
                    Circle()
                        .fill(point.isNow ? V8.orange : V8.paper)
                        .frame(width: point.isNow ? 26 : (point.small ? 12 : 22), height: point.isNow ? 26 : (point.small ? 12 : 22))
                        .position(at)
                    if !point.small {
                        SpecLabel(point.label, color: V8.paper)
                            .fixedSize()
                            .position(x: min(max(at.x, 50), size.width - 50), y: at.y + (index.isMultiple(of: 2) ? 28 : -26))
                    }
                }
            }
            .clipped()
        }
        .frame(height: 290)
        .overlay(alignment: .topLeading) {
            HStack(alignment: .top) {
                if showsBack { V8CornerButton(systemName: "chevron.left", label: "Voltar", onInk: true, action: onBack) }
                Spacer(minLength: 12)
                V8SpecStack(lines: lines, color: V8.paper, alignment: .trailing).padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: onMap) {
                Text("Abrir o mapa")
                    .font(V8Font.text(15, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(V8.paper))
            }
            .buttonStyle(MustPressStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Percurso: \(points.map(\.label).joined(separator: ", "))")
    }

    private func grid(size: CGSize) -> some View {
        Path { path in
            for x in stride(from: size.width * 0.15, to: size.width, by: size.width * 0.27) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: size.height * 0.28, to: size.height, by: size.height * 0.3) {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(V8.white.opacity(0.16), lineWidth: 1)
    }

    /// Projeção simples (equiretangular com cos da latitude) no retângulo útil da faixa (abaixo dos rótulos do topo).
    private func project(size: CGSize) -> [(Point, CGPoint)] {
        guard !points.isEmpty else { return [] }
        let lats = points.map(\.coordinate.latitude), lngs = points.map(\.coordinate.longitude)
        let midLat = (lats.min()! + lats.max()!) / 2
        let k = cos(midLat * .pi / 180)
        let xs = lngs.map { $0 * k }, ys = lats
        let spanX = max(xs.max()! - xs.min()!, 0.002), spanY = max(ys.max()! - ys.min()!, 0.002)
        let rect = CGRect(x: 50, y: 120, width: size.width - 100, height: size.height - 205)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let offX = rect.minX + (rect.width - spanX * scale) / 2, offY = rect.minY + (rect.height - spanY * scale) / 2
        return points.enumerated().map { i, p in
            (p, CGPoint(x: offX + (xs[i] - xs.min()!) * scale, y: offY + (ys.max()! - ys[i]) * scale))
        }
    }
}
