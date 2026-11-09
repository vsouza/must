import CoreLocation
import SwiftUI

/// O recorte aberto (B-3): o mapa vivo (único `MLNMapView` do Explorar) numa moldura com a cor do lugar, as quatro camadas em
/// células no pé do mapa e o índice sincronizado ("na tela · N", "pino k de N"). Tocar num pino vira o índice no bloco do
/// lugar; deslizar o bloco vai pro próximo pino.
struct ExplorarMapOpen: View {
    var model: ExplorarModel
    var area: Area
    var region: Region
    var photoURL: URL?
    var quero: () -> Void
    var onClose: () -> Void
    /// Ambiente do dia (plano de hoje, origem) pra calcular o "+ dia" do pino escolhido.
    var makeEnv: () -> QueroEnv
    /// "+ dia": grava a parada no buraco; `true` se encaixou.
    var onFit: (ExplorarItem, DayFit.Slot) -> Bool
    /// "+ board": guarda o de fora no board; devolve o id do Must novo (o pino vira seu).
    var onSave: (ExplorarItem) -> String?

    @Environment(AppRouter.self) private var router
    @Environment(Services.self) private var services
    @Environment(\.tripTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var type

    @State private var command: MapCameraCommand?
    @State private var camera: MapCameraState?
    @State private var mapSize: CGSize = .zero
    @State private var visible: GeoRect?
    @State private var selected: String?
    @State private var pinDay: ExplorarPinActions.Day?
    @State private var notice: String?

    private var layers: Set<ExplorarLayer> { model.layers }
    private var outsideReady: Bool { !model.items.filter { !$0.isOwn }.isEmpty }

    var body: some View {
        let initial = ExplorarProjection(center: area.centroid.clCoordinate, widthMeters: ExplorarSnapshot.widthMeters,
                                         size: mapSize == .zero ? CGSize(width: 340, height: 360) : mapSize)
        let listed = ExplorarLayers.listed(model.items, layers: layers, in: visible ?? initial.rect)
        VStack(spacing: 0) {
            header
            mapFrame(listed: listed)
            CutRule(pullLabel: "↓ quero em \(area.name.lowercased())")
                .onTapGesture { quero() }
                .accessibilityAction(named: "Quero em \(area.name)") { quero() }
            index(listed: listed)
        }
        .background(V8.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .task(id: selected) { await computePinDay() }
        .task {
            command = MapCameraCommand(target: .center(lat: area.centroid.lat, lng: area.centroid.lng,
                                                       widthMeters: ExplorarSnapshot.widthMeters * 1.15), animated: false)
            #if DEBUG
            // Prints: `explorar-recorte-pino` abre o primeiro Must; `-fora` o primeiro de fora (se houver).
            let screen = DebugFlags.string("debugScreen")
            if screen == "explorar-recorte-pino" || screen == "explorar-recorte-fora" {
                try? await Task.sleep(for: .seconds(1.5))
                let wantOwn = screen == "explorar-recorte-pino"
                selected = ExplorarLayers.listed(model.items, layers: layers).first { $0.isOwn == wantOwn }?.id
            }
            #endif
        }
    }

    // MARK: Moldura

    private var header: some View {
        CutBand(photo: nil, arcs: true, alignment: .bottomLeading) {
            HStack(alignment: .center, spacing: 14) {
                Text(area.seal)
                    .font(V8Font.mono(16, weight: .bold)).foregroundStyle(V8.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: 62, height: 62)
                    .overlay(Rectangle().stroke(V8.white, lineWidth: 3))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.name)
                        .font(V8Font.display(42, width: 82, weight: 800)).tracking(-1.4)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                    MonoLabel(captionLine, size: 10, color: V8.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 17)).foregroundStyle(V8.white)
                        .frame(width: 44, height: 44)
                        .overlay(Rectangle().stroke(V8.white, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar o mapa")
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            .padding(.top, 58)
        }
        .frame(height: type.isAccessibilitySize ? 190 : 150)
        .clipped()
    }

    private var captionLine: String {
        var parts: [String] = []
        if let s = model.station { parts.append(s.mark == .here ? "aqui" : "\(s.minutes) min") }
        if !model.lineCodes.isEmpty { parts.append(model.lineCodes.prefix(2).joined(separator: " · ")) }
        if case .today(let time)? = model.station?.mark { parts.append("hoje\(time.map { " \($0)" } ?? "")") }
        return parts.joined(separator: " · ")
    }

    private func mapFrame(listed: [ExplorarItem]) -> some View {
        let numbered = Dictionary(uniqueKeysWithValues: listed.map { ($0.id, $0.number) })
        let pins = ExplorarLayers.filter(model.items, layers: layers).map { item -> MapPin in
            MapPin(id: item.id, coordinate: item.coordinate,
                   kind: .block(number: numbered[item.id] ?? nil, tone: tone(item.tone), selected: item.id == selected),
                   placeId: item.placeId, layer: .search)
        }
        var scene = MapScene(region: region, layers: layers.contains(.trail) ? [.search, .today] : [.search], pins: pins, metro: .empty)
        scene.routeDone = layers.contains(.trail) ? ExplorarLayers.trail(stops: model.trail) : []
        scene.you = model.isHere ? model.youCoordinate : nil
        return Color(hex: theme.coverRGB)
            .overlay {
                MapLibreView(scene: scene, command: command,
                             onCamera: { camera = $0 },
                             onGesture: {},
                             onIdle: { settle() },
                             onSelect: { pin in select(pin.id) },
                             onTapEmpty: { selected = nil })
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 3))
                    .padding(14)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
                    .overlay(alignment: .bottom) { layerCells.padding(.horizontal, 14).padding(.bottom, 14) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: type.isAccessibilitySize ? 340 : 400)
    }

    private func tone(_ t: ExplorarItem.Tone) -> MapPin.BlockTone {
        switch t {
        case .own: .own
        case .paper: .paper
        case .outside: .outside
        }
    }

    /// A câmera parou: a lista passa a ser o que está na tela.
    private func settle() {
        guard let camera, mapSize.width > 0 else { return }
        visible = ExplorarProjection(center: camera.center, widthMeters: camera.widthMeters, size: mapSize).rect
    }

    // MARK: Camadas

    private var layerCells: some View {
        HStack(spacing: 0) {
            ForEach(ExplorarLayer.allCases) { layer in
                let on = layers.contains(layer)
                let disabled = (layer == .trail && model.trail.count < 2)
                // Desligada fica sólida (papel + texto cinza): nada translúcido sobre o mapa.
                Button { if !disabled { toggle(layer) } } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Rectangle().fill(on && !disabled ? V8.ink : Color.clear).frame(width: 9, height: 9)
                            .overlay(Rectangle().stroke(disabled ? V8.mute : V8.ink, lineWidth: 2))
                        Text(cellLabel(layer))
                            .font(V8Font.mono(9, weight: .bold)).tracking(0.6)
                            .foregroundStyle(disabled ? V8.mute : V8.ink)
                            .strikethrough(strike(layer))
                            .lineLimit(3).minimumScaleFactor(0.6)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                    .background(on && !disabled ? V8.orange : V8.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) { if layer != .trail { Rectangle().fill(V8.ink).frame(width: 2) } }
                .accessibilityLabel(layer.label)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    private func strike(_ layer: ExplorarLayer) -> Bool { layer == .outside && services.connectivity.isOffline }

    private func cellLabel(_ layer: ExplorarLayer) -> String {
        if layer == .own { return "\(layer.label) · \(model.items.filter(\.isOwn).count)".uppercased() }
        if layer == .openNow {
            let others = layers.subtracting([.openNow])
            return ExplorarLayers.openSummary(ExplorarLayers.filter(model.items, layers: others)).label.uppercased()
        }
        return layer.label.uppercased()
    }

    private func toggle(_ layer: ExplorarLayer) {
        if layer == .outside, services.connectivity.isOffline { return }
        var next = model.layers
        if next.contains(layer) { next.remove(layer) } else { next.insert(layer) }
        model.layers = next
        if let selected, !ExplorarLayers.filter(model.items, layers: next).contains(where: { $0.id == selected }) { self.selected = nil }
    }

    // MARK: Índice

    private func index(listed: [ExplorarItem]) -> some View {
        VStack(spacing: 0) {
            HStack {
                MonoLabel("na tela · \(listed.count)", size: 11, color: V8.ink)
                Spacer(minLength: 8)
                if let selected, let i = ExplorarLayers.index(ofPin: selected, in: listed) {
                    MonoLabel("pino \(i + 1) de \(listed.count)", size: 11, color: V8.ink)
                } else if let note = model.outsideState.note {
                    MonoLabel(note, size: 10, color: V8.mute).lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if let selected, let item = listed.first(where: { $0.id == selected }) {
                            selectedBlock(item, listed: listed)
                        }
                        ForEach(listed.filter { $0.id != selected }) { item in
                            ExplorarRow(item: item, leftOverride: nil, refs: model.photoRefs[item.id] ?? [], googleId: model.googleIds[item.id],
                                        tint: theme.coverRGB, selected: false, onTap: { select(item.id) })
                                .id(item.id)
                        }
                        if listed.isEmpty {
                            Text("Nada neste pedaço do mapa. Arraste ou ligue outra camada.")
                                .font(V8Font.text(15)).foregroundStyle(V8.mute)
                                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 110)
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: selected) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func select(_ id: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selected = id }
    }

    /// O pino que vira bloco: foto (já no disco), nome grande, meta e as ações. Deslizar = próximo pino.
    private func selectedBlock(_ item: ExplorarItem, listed: [ExplorarItem]) -> some View {
        let ref = model.photoRefs[item.id]?.first
        let url = ref.flatMap { PlacePhotoStore.existing($0) }
        let d = ExplorarTravel.distance(item.meters)
        // Nome e ações em cima, foto embaixo: com a faixa "agora" sobram ~120 pt sob o mapa, e o nome no pé da foto ficava
        // escondido atrás dela (os botões apareciam sem dizer de qual lugar eram).
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.name)
                        .font(V8Font.display(22, width: 85, weight: 800)).tracking(-0.4).foregroundStyle(V8.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    MonoLabel("\(d.value) \(d.unit) · \(ExplorarTravel.caption(item.meters))", size: 10, color: V8.ink).fixedSize()
                }
                Text(item.meta).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(nextPinSwipe(item, listed: listed))
            HStack(spacing: 0) {
                actionButton("Ir", filled: true) { MapsLinks.openApple(to: item.coordinate, name: item.name) }
                dayButton(item)
                if ExplorarPinActions.canSave(item) {
                    actionButton("+ board", filled: false) {
                        if let id = onSave(item) { selected = id } else { notice = "não deu pra guardar agora" }
                    }
                } else if let id = item.placeId {
                    actionButton("Abrir", filled: false) { router.push(.place(id: id), on: router.tab) }
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
            if let notice {
                MonoLabel(notice, size: 10, color: V8.mute).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            CutBand(photo: url, alignment: .topLeading) {
                HStack {
                    if let n = item.number { MonoLabel("pino \(n)", size: 10, color: V8.white) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .frame(height: 120)
            .clipped()
            // Deslizar = próximo pino, só no nome e na foto: no bloco inteiro o arrasto engolia o toque dos botões.
            .contentShape(Rectangle())
            .gesture(nextPinSwipe(item, listed: listed))
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Próximo pino") {
            if let next = ExplorarLayers.neighbor(of: item.id, in: listed, by: 1) { select(next) }
        }
    }

    private func computePinDay() async {
        notice = nil
        guard let selected, let item = model.items.first(where: { $0.id == selected }) else { pinDay = nil; return }
        pinDay = ExplorarPinActions.day(for: item, env: makeEnv())
    }

    /// "+ dia" / "no dia · 15:30" / "não cabe hoje" (nada quando já está feito).
    @ViewBuilder private func dayButton(_ item: ExplorarItem) -> some View {
        switch pinDay {
        case .fit(let slot)?:
            actionButton("+ dia", filled: false) {
                if onFit(item, slot) { notice = "no dia · \(region.timeString(slot.start))"; pinDay = .inDay(time: region.timeString(slot.start)) }
                else { notice = "não deu pra gravar o dia" }
            }
        case .inDay(let time)?:
            staticCell("no dia" + (time.map { " · \($0)" } ?? ""))
        case .noFit?:
            staticCell("não cabe hoje")
        case .none?, nil:
            EmptyView()
        }
    }

    private func staticCell(_ title: String) -> some View {
        Text(title.uppercased())
            .font(V8Font.mono(11, weight: .bold)).tracking(0.8)
            .foregroundStyle(V8.ink.opacity(0.7))
            .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(V8.paper)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .accessibilityLabel(title)
    }

    private func nextPinSwipe(_ item: ExplorarItem, listed: [ExplorarItem]) -> some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            if let next = ExplorarLayers.neighbor(of: item.id, in: listed, by: value.translation.width < 0 ? 1 : -1) { select(next) }
        }
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(V8Font.mono(12, weight: .bold)).tracking(1)
                .foregroundStyle(V8.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(filled ? V8.orange : V8.paper)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
