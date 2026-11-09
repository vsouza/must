import CoreLocation
import SwiftUI

/// Pinos, área e enquadramento do preview do Adicionar por link. Só lugares com coordenada entram no mapa.
struct LinkMapLayout: Equatable {
    struct Pin: Identifiable, Equatable {
        var id: String
        /// Número do pino (ordem da lista, só entre os que têm ponto).
        var number: Int
        var name: String
        var point: MapCameraCommand.Coordinate
    }

    var pins: [Pin] = []
    /// Elipse da área citada: contém o retângulo dos pontos + 20%.
    var area: [MapCameraCommand.Coordinate]?
    var centroid: MapCameraCommand.Coordinate?
    /// Maior distância entre dois pontos (metros).
    var spreadMeters: Double?
    /// Bairro mais citado, ou a estação de metrô mais próxima do centro.
    var areaName: String?
    var fallback: MapCameraCommand.Coordinate

    func number(for id: String) -> Int? { pins.first { $0.id == id }?.number }

    static func make(matches: [MatchedPlace], region: Region, transit: TransitMap) -> LinkMapLayout {
        let located = matches.filter(\.located)
        let pins = located.enumerated().map { index, match in
            Pin(id: match.id, number: index + 1, name: match.existing?.name ?? match.extracted.name,
                point: .init(CLLocationCoordinate2D(latitude: match.lat, longitude: match.lng)))
        }
        var layout = LinkMapLayout(pins: pins, fallback: .init(region.defaultCenter))
        let points = pins.map(\.point.value)
        guard !points.isEmpty else { return layout }
        let center = centroid(points)
        layout.centroid = .init(center)
        if points.count > 1 {
            layout.spreadMeters = maxSpread(points)
            layout.area = ellipse(points).map { $0.map { MapCameraCommand.Coordinate($0) } }
        }
        // Rótulo sempre em letras latinas (nada de kanji na interface): nome de bairro em CJK cai pra estação mais perto.
        let areas = located.compactMap { $0.existing?.area ?? $0.extracted.area }.filter { !hasCJK($0) }
        layout.areaName = Dictionary(grouping: areas, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            ?? nearestStation(to: center, in: transit).flatMap { AtalhosRules.latinName($0, areas: AreaCatalog.areas(for: region)) }
        return layout
    }

    /// Enquadramento: os pontos com 28 pt de folga; um ponto só, escala de bairro.
    var command: MapCameraCommand {
        if pins.count > 1 {
            return MapCameraCommand(target: .fit(points: pins.map(\.point), top: 28, bottom: 28, sides: 28), animated: false)
        }
        if let pin = pins.first {
            return MapCameraCommand(target: .center(lat: pin.point.lat, lng: pin.point.lng, widthMeters: 900), animated: false)
        }
        return MapCameraCommand(target: .center(lat: fallback.lat, lng: fallback.lng, widthMeters: 6_000), animated: false)
    }

    /// A cena do `MapLibreView` (papel em relevo): pinos pretos numerados, o selecionado com nome, metrô e área.
    @MainActor func scene(selectedId: String?, region: Region) -> MapScene {
        MapScene(region: region, layers: [.today, .metro],
                 pins: pins.map { pin in
                     MapPin(id: pin.id, coordinate: pin.point.value,
                            kind: .preview(number: pin.number, label: pin.id == selectedId ? pin.name : nil),
                            placeId: nil, layer: .today)
                 },
                 metro: TransitLoader.load(region), area: area?.map(\.value))
    }

    /// Projeção simples (sem tiles): os pontos e a área cabem na caixa com `inset`.
    func project(in size: CGSize, inset: CGFloat = 28) -> (MapCameraCommand.Coordinate) -> CGPoint {
        let all = pins.map(\.point) + (area ?? [])
        guard let minLat = all.map(\.lat).min(), let maxLat = all.map(\.lat).max(),
              let minLng = all.map(\.lng).min(), let maxLng = all.map(\.lng).max() else {
            return { _ in CGPoint(x: size.width / 2, y: size.height / 2) }
        }
        let cosLat = cos((minLat + maxLat) / 2 * .pi / 180)
        // Vão mínimo de ~400 m pra um ponto só não estourar a escala.
        let width = max((maxLng - minLng) * cosLat, 0.004), height = max(maxLat - minLat, 0.004)
        let scale = min((size.width - 2 * inset) / width, (size.height - 2 * inset) / height)
        let offsetX = (size.width - width * scale) / 2, offsetY = (size.height - height * scale) / 2
        return { c in
            CGPoint(x: offsetX + (c.lng - minLng) * cosLat * scale, y: offsetY + (maxLat - c.lat) * scale)
        }
    }

    // MARK: Geometria

    static func centroid(_ points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let lat = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let lng = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func maxSpread(_ points: [CLLocationCoordinate2D]) -> Double {
        var best = 0.0
        for i in points.indices {
            for j in points.indices where j > i { best = max(best, meters(points[i], points[j])) }
        }
        return best
    }

    /// Elipse (65 pontos, fecha o anel) com semi-eixos que contêm o retângulo dos pontos + 20%. Mínimo 150 m.
    static func ellipse(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D]? {
        guard let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
              let minLng = points.map(\.longitude).min(), let maxLng = points.map(\.longitude).max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let metersPerLat = 111_320.0, metersPerLng = 111_320.0 * cos(center.latitude * .pi / 180)
        let growth = 1.2 * 2.0.squareRoot()
        let halfWidth = max((maxLng - minLng) * metersPerLng / 2 * growth, 150)
        let halfHeight = max((maxLat - minLat) * metersPerLat / 2 * growth, 150)
        return (0...64).map { i in
            let t = Double(i) / 64 * 2 * .pi
            return CLLocationCoordinate2D(latitude: center.latitude + halfHeight * sin(t) / metersPerLat,
                                          longitude: center.longitude + halfWidth * cos(t) / metersPerLng)
        }
    }

    static func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value) }
    }

    static func nearestStation(to center: CLLocationCoordinate2D, in transit: TransitMap) -> TransitStation? {
        guard let station = transit.stations.min(by: { meters(center, $0.coordinate) < meters(center, $1.coordinate) }),
              meters(center, station.coordinate) <= 1_000 else { return nil }
        return station
    }
}

/// Mapa do preview: papel em relevo, não interativo, pinos numerados. Sem tiles, vira o placeholder.
struct LinkPlacesMap: View {
    let layout: LinkMapLayout
    let selectedId: String?
    let region: Region
    var onSelect: (String) -> Void

    @Environment(Services.self) private var services
    @State private var expanded = false
    @State private var command: MapCameraCommand?

    private var offline: Bool {
        MapTiles.pick(region: region, near: layout.centroid?.value ?? region.defaultCenter) == .none
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if offline {
                LinkMapPlaceholder(layout: layout, selectedId: selectedId, onSelect: onSelect)
            } else {
                MapLibreView(scene: layout.scene(selectedId: selectedId, region: region), command: command,
                             onSelect: { onSelect($0.id) }, interactive: false)
            }
            chip
        }
        .overlay(alignment: .topTrailing) { expandButton }
        .frame(height: 226)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { command = layout.command }
        .onChange(of: layout) { command = layout.command }
        .fullScreenCover(isPresented: $expanded) {
            LinkPlacesFullMap(layout: layout, selectedId: selectedId, region: region, onSelect: onSelect)
        }
    }

    /// "Tsukiji · 380 m entre eles · 34 min de você".
    private var chip: some View {
        Text(chipText)
            .font(J9.font(11, .semibold))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(V9.background)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(uiColor: .separator), lineWidth: 1))
            .padding(10)
    }

    private var chipText: String {
        guard !layout.pins.isEmpty else { return "nenhum lugar no mapa" }
        var parts: [String] = []
        if let name = layout.areaName { parts.append(name) }
        if let spread = layout.spreadMeters { parts.append("\(Walk.distanceText(spread)) entre eles") }
        if let minutes = etaMinutes { parts.append("\(minutes) min de você") }
        if parts.isEmpty { parts.append(layout.pins.count == 1 ? layout.pins[0].name : "\(layout.pins.count) lugares no mapa") }
        return parts.joined(separator: " · ")
    }

    private var etaMinutes: Int? {
        guard let here = services.location.current, let center = layout.centroid?.value else { return nil }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return services.eta.minutes(from: here.coordinate, to: center, transit: here.distance(from: centerLocation) > 1_500)
    }

    private var expandButton: some View {
        Button { expanded = true } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .background(V9.background)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(uiColor: .separator), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Abrir o mapa em tela cheia")
    }
}

/// Sem tiles: fundo #E9EBEF com os pinos na projeção simples (mesmos números e área).
struct LinkMapPlaceholder: View {
    let layout: LinkMapLayout
    let selectedId: String?
    var onSelect: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let project = layout.project(in: geo.size)
            ZStack {
                Color(hex: 0xE9EBEF)
                if let ring = layout.area {
                    let shape = RingShape(points: ring.map(project))
                    shape.fill(V9.accent.opacity(0.08))
                    shape.stroke(V9.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
                ForEach(layout.pins) { pin in
                    let selected = pin.id == selectedId
                    Button { onSelect(pin.id) } label: {
                        Text("\(pin.number)")
                            .font(J9.font(selected ? 14 : 12, .semibold).monospacedDigit())
                            .foregroundStyle(Color.white)
                            .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
                            .background(Circle().fill(selected ? V9.accent : Color.gray))
                    }
                    .buttonStyle(.plain)
                    .position(project(pin.point))
                }
            }
        }
    }
}

/// Anel fechado (a área) em pontos de tela.
struct RingShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// "Abrir o mapa": a mesma tela do Mapa, só com esses pinos.
struct LinkPlacesFullMap: View {
    let layout: LinkMapLayout
    let selectedId: String?
    let region: Region
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var command: MapCameraCommand?

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapLibreView(scene: layout.scene(selectedId: selectedId, region: region), command: command,
                         onSelect: { onSelect($0.id) }, interactive: true)
                .ignoresSafeArea()
            J9IconButton(systemName: "xmark", label: "Fechar") { dismiss() }
                .padding(.top, 8)
                .padding(.leading, 16)
        }
        .onAppear { command = layout.command }
    }
}
