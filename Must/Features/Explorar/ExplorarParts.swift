import CoreLocation
import SwiftUI

// Peças do Explorar (prompt 31 · 8): pino quadrado, recorte do mapa, trilho de estações, painel do trilho e linha do índice.
// Réguas de 2 pt, sem raio, sem sombra, sem degradê.

// MARK: - Pino quadrado

struct ExplorarPinSquare: View {
    var number: Int?
    var tone: ExplorarItem.Tone
    var selected = false

    private var fill: Color {
        switch tone {
        case .own: V8.orange
        case .paper: V8.paper
        case .outside: V8.ink
        }
    }
    private var text: Color { tone == .outside ? V8.white : V8.ink }

    var body: some View {
        if let number {
            Text("\(number)")
                .font(V8Font.mono(selected ? 14 : 12, weight: .bold))
                .foregroundStyle(text)
                .frame(width: selected ? 34 : 26, height: selected ? 34 : 26)
                .background(fill)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        } else {
            Rectangle().fill(fill).frame(width: 9, height: 9).overlay(Rectangle().stroke(V8.ink, lineWidth: 1.5))
        }
    }
}

// MARK: - Você

/// O ícone do app: ponto laranja com dois arcos.
struct ExplorarYou: View {
    var body: some View {
        ZStack {
            Circle().stroke(V8.ink.opacity(0.35), lineWidth: 1).frame(width: 38, height: 38)
            Circle().stroke(V8.ink.opacity(0.6), lineWidth: 1).frame(width: 26, height: 26)
            Circle().fill(V8.orange).frame(width: 12, height: 12).overlay(Circle().stroke(V8.ink, lineWidth: 2))
        }
        .accessibilityLabel("Você está aqui")
    }
}

// MARK: - Recorte

/// O recorte quadrado da página: o snapshot do mapa (ou papel com trama, sem ele), a trilha e os pinos numerados.
struct ExplorarRecorte: View {
    var area: Area
    var items: [ExplorarItem]
    var snapshot: UIImage?
    var you: CLLocationCoordinate2D?
    var trail: [CLLocationCoordinate2D]
    var showsTrail: Bool
    var side: CGFloat = ExplorarSnapshot.side

    var body: some View {
        let projection = ExplorarSnapshot.projection(for: area, side: side)
        ZStack {
            base
            if showsTrail, trail.count >= 2 {
                Path { path in
                    for (i, c) in trail.enumerated() {
                        let p = projection.point(c)
                        i == 0 ? path.move(to: p) : path.addLine(to: p)
                    }
                }
                .stroke(V8.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            ForEach(items.reversed()) { item in
                let p = projection.point(item.coordinate)
                if p.x > 4, p.x < side - 4, p.y > 4, p.y < side - 4 {
                    ExplorarPinSquare(number: item.number, tone: item.tone).position(p)
                }
            }
            if let you {
                let p = projection.point(you)
                if p.x > 0, p.x < side, p.y > 0, p.y < side { ExplorarYou().position(p) }
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mapa de \(area.name), \(items.count) pinos")
        .accessibilityHint("abre o mapa")
        .accessibilityAddTraits(.isButton)
    }

    /// Snapshot do MapLibre; sem ele, papel com quadras e a trama de pontos (estado normal, offline sem pack).
    @ViewBuilder private var base: some View {
        if let snapshot {
            Image(uiImage: snapshot).resizable().scaledToFill().frame(width: side, height: side)
        } else {
            ZStack {
                V8.paper
                Canvas { context, size in
                    let block = Color(hex: 0xE4E0D5)
                    var y: CGFloat = 8
                    var row = 0
                    while y < size.height {
                        var x: CGFloat = row.isMultiple(of: 2) ? 4 : 22
                        while x < size.width {
                            context.fill(Path(CGRect(x: x, y: y, width: 34, height: 24)), with: .color(block))
                            x += 46
                        }
                        y += 34
                        row += 1
                    }
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height * 0.62)); path.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                    context.stroke(path, with: .color(V8.ink), style: StrokeStyle(lineWidth: 4, dash: [10, 3]))
                }
            }
        }
    }
}

// MARK: - Trilho de estações

/// O trilho na borda direita do bloco: uma estação por bairro (sigla + legenda), linha branca de 2 pt, marcas
/// (quadrado laranja = aqui, branco = dia/feito, cor do lugar com borda = os outros). Arrastar troca de bairro.
struct ExplorarRailView: View {
    var stations: [ExplorarStation]
    var currentId: String?
    var tint: Color
    var showsCaptions: Bool
    var onPreview: (Int) -> Void
    var onCommit: (Int) -> Void
    var onEnd: () -> Void

    static let rowHeight: CGFloat = 24
    static let maxRows = 10

    /// As estações visíveis: as mais perto; a atual entra no lugar da última se está além.
    static func window(_ stations: [ExplorarStation], currentId: String?) -> [ExplorarStation] {
        guard stations.count > maxRows else { return stations }
        var out = Array(stations.prefix(maxRows))
        if let current = stations.first(where: { $0.id == currentId }), !out.contains(where: { $0.id == current.id }) {
            out[maxRows - 1] = current
        }
        return out
    }

    var body: some View {
        let rows = Self.window(stations, currentId: currentId)
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(rows) { station in
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Text(station.area.seal)
                            .font(V8Font.mono(11, weight: .bold))
                            .foregroundStyle(V8.white)
                        if showsCaptions {
                            Text(station.caption.uppercased())
                                .font(V8Font.mono(10))
                                .foregroundStyle(V8.white.opacity(station.id == currentId ? 1 : 0.85))
                                .lineLimit(1)
                        }
                    }
                    .lineLimit(1)
                    marker(station)
                }
                .frame(height: Self.rowHeight)
                .scaleEffect(station.id == currentId ? 1.08 : 1, anchor: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(station.area.name), \(station.caption)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(station.id == currentId ? .isSelected : [])
            }
        }
        .background(alignment: .trailing) {
            Rectangle().fill(V8.white).frame(width: 2).padding(.trailing, 12).padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in onPreview(index(forY: value.location.y, rows: rows.count)) }
                .onEnded { value in
                    onCommit(index(forY: value.location.y, rows: rows.count))
                    onEnd()
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trilho de bairros")
        .accessibilityAdjustableAction { direction in
            guard let i = stations.firstIndex(where: { $0.id == currentId }) else { return }
            let next = direction == .increment ? min(i + 1, stations.count - 1) : max(i - 1, 0)
            onCommit(next)
        }
    }

    /// A posição do dedo na janela do trilho vira o índice na lista inteira (o trilho curto cobre todos os bairros).
    private func index(forY y: CGFloat, rows: Int) -> Int {
        let fraction = Double(y / (CGFloat(max(rows, 1)) * Self.rowHeight))
        return ExplorarRail.station(atFraction: fraction, count: stations.count)
    }

    @ViewBuilder private func marker(_ station: ExplorarStation) -> some View {
        switch station.mark {
        case .here:
            Rectangle().fill(V8.orange).frame(width: 24, height: 16).overlay(Rectangle().stroke(V8.white, lineWidth: 2))
        case .today, .done:
            Rectangle().fill(V8.white).frame(width: 24, height: 16)
        case .other:
            Rectangle().fill(tint).frame(width: 24, height: 16).overlay(Rectangle().stroke(V8.white, lineWidth: 2))
        }
    }
}

/// O painel de tinta do trilho (B-2): os bairros em ordem de tempo; a linha sob o dedo fica laranja e grande.
struct ExplorarRailPanel: View {
    var stations: [ExplorarStation]
    var selectedId: String?
    var cityName: String
    var rows: [ExplorarStation]

    static let maxRows = 9

    /// Janela de linhas ao redor da selecionada (com 23 bairros não cabe tudo na tela).
    static func window(_ stations: [ExplorarStation], around id: String?) -> [ExplorarStation] {
        guard stations.count > maxRows else { return stations }
        let i = stations.firstIndex { $0.id == id } ?? 0
        let lo = min(max(i - maxRows / 2, 0), stations.count - maxRows)
        return Array(stations[lo..<(lo + maxRows)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("trilho · \(cityName) · \(stations.count) bairros", size: 11, color: V8.white)
                MonoLabel("ordem: tempo de trem de você · solte pra ir", size: 10, color: V8.muteDark)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.top, 62).padding(.bottom, 14)
            Rectangle().fill(V8.graphite).frame(height: 3)
            ForEach(rows) { station in
                let selected = station.id == selectedId
                HStack(alignment: .center, spacing: 12) {
                    Text(station.area.seal)
                        .font(V8Font.mono(11, weight: .bold))
                        .foregroundStyle(selected ? V8.ink : V8.white)
                        .frame(width: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.area.name)
                            .font(V8Font.display(selected ? 38 : 24, width: 85, weight: 800))
                            .tracking(selected ? -1.2 : -0.4)
                            .foregroundStyle(selected ? V8.ink : (station.mark == .here ? V8.muteDark : V8.white))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if selected {
                            MonoLabel(detail(station), size: 10, color: V8.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    if !selected {
                        if station.mark == .done {
                            Text("FEITO").font(V8Font.mono(10, weight: .bold)).foregroundStyle(V8.white)
                                .padding(.horizontal, 6).padding(.vertical, 3).overlay(Rectangle().stroke(V8.white, lineWidth: 2))
                        } else {
                            MonoLabel(station.mark == .here ? "aqui" : station.caption, size: 10, color: V8.muteDark)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, selected ? 14 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? V8.orange : Color.clear)
                .overlay(alignment: .bottom) { Rectangle().fill(V8.graphite).frame(height: 1) }
                .overlay(alignment: .leading) {
                    if station.mark == .done || station.mark.isToday { Rectangle().fill(V8.paper).frame(width: 6) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(V8.ink)
        .accessibilityHidden(true)
    }

    private func detail(_ s: ExplorarStation) -> String {
        var parts = [s.mark == .here ? "aqui" : "\(s.minutes) min"]
        if case .today(let time) = s.mark { parts.append(time.map { "hoje \($0)" } ?? "hoje") }
        if s.mark == .done { parts.append("feito") }
        return parts.joined(separator: " · ")
    }
}

extension ExplorarStation.Mark {
    var isToday: Bool { if case .today = self { true } else { false } }
}

// MARK: - Miniatura do índice

/// Miniatura de 54 pt: só foto que já está no disco (nunca baixa), P&B × cor do lugar; sem foto, a cor com o número.
struct ExplorarThumb: View {
    var number: Int?
    var tone: ExplorarItem.Tone
    var refs: [PlacePhotoRef]
    var placeId: String?
    var tint: UInt32
    var showsPhoto: Bool

    @Environment(Services.self) private var services: Services?
    @State private var url: URL?
    @State private var carousel: PhotoCarousel?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsPhoto {
                V8Photo(url: url, placeholder: Color(hex: tint))
                    .saturation(url == nil ? 1 : 0)
                    .contrast(url == nil ? 1 : 1.35)
                    .colorMultiply(url == nil ? .white : Color(hex: tint).opacity(0.9))
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard url != nil else { return }
                        carousel = .place(placeId: placeId, refs: refs, resolver: services?.photoResolver)
                    }
                    .photoCarousel($carousel)
            }
            if let number {
                Text("\(number)")
                    .font(V8Font.mono(11, weight: .bold))
                    .foregroundStyle(tone == .paper ? V8.ink : V8.white)
                    .frame(width: 22, height: 22)
                    .background(tone == .paper ? V8.paper : V8.ink)
            }
        }
        .frame(width: 54, height: 54)
        .task(id: refs.first?.name ?? "") {
            guard showsPhoto, let first = refs.first else { url = nil; return }
            url = PlacePhotoStore.existingThumb(first) ?? PlacePhotoStore.existing(first)
        }
    }
}

// MARK: - Linha do índice

struct ExplorarRow: View {
    var item: ExplorarItem
    /// "dia 7" na coluna esquerda (outra cidade) em vez da distância.
    var leftOverride: (big: String, small: String)?
    var refs: [PlacePhotoRef]
    var googleId: String?
    var tint: UInt32
    var selected = false
    var onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var type

    private var background: Color {
        switch item.tone {
        case .own: V8.orange
        case .paper: V8.paper
        case .outside: V8.ink
        }
    }
    private var main: Color { item.tone == .outside ? V8.white : V8.ink }
    private var sub: Color { item.tone == .outside ? V8.muteDark : (item.tone == .own ? V8.ink.opacity(0.75) : V8.mute) }

    var body: some View {
        let dist = ExplorarTravel.distance(item.meters)
        let left = leftOverride ?? ("\(dist.value) \(dist.unit)", ExplorarTravel.caption(item.meters))
        let content = Group {
            if type.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { leftColumn(left); middle }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    leftColumn(left).frame(width: 84, alignment: .leading)
                    middle
                    if item.isOwn || item.number != nil {
                        ExplorarThumb(number: item.number, tone: item.tone, refs: refs, placeId: googleId, tint: tint, showsPhoto: item.isOwn)
                    }
                }
            }
        }
        Button(action: onTap) {
            content
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(background)
                .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.number.map { "pino \($0), " } ?? "")\(item.name). \(left.big), \(left.small). \(item.meta)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func leftColumn(_ left: (big: String, small: String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(left.big)
                .font(V8Font.mono(21, weight: .bold))
                .foregroundStyle(main)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(left.small.uppercased())
                .font(V8Font.mono(8.5)).tracking(0.6).foregroundStyle(sub)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var middle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(V8Font.display(20, width: 88, weight: 800))
                .tracking(-0.3)
                .foregroundStyle(main)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(item.meta)
                .font(V8Font.text(13))
                .foregroundStyle(sub)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Micro-rótulo mono em caixa alta que quebra linha em vez de truncar (Dynamic Type até XXXL).
struct ExplorarMono: View {
    var text: String
    var size: CGFloat = 10
    var color: Color

    init(_ text: String, size: CGFloat = 10, color: Color) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(size))
            .tracking(size * 0.1)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
