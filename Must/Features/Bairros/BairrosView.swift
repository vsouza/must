import CoreLocation
import SwiftData
import SwiftUI

/// Bairros (prompt 18 · C.14, `Bairros.png`): mapa papel em relevo com uma bolha por bairro (raio ∝ √musts, cor = o
/// que mais tem, kanji no maior), tempos entre vizinhos, você e a sheet do bairro escolhido (selo, mistura, vizinhos,
/// frase do solver e "Montar <bairro>+"). Só o cache e o board: nada de rede pra abrir.
struct BairrosView: View {
    /// Bairro que abre já escolhido (`-debugScreen bairros:<id>` e prints).
    var initialArea: String?

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var model = BairrosModel(region: .jp)
    @State private var command: MapCameraCommand?
    @State private var saveRefresh: Task<Void, Never>?

    private var region: Region { store.region }

    /// Célula de ~55 m: a tela só recalcula quando o GPS anda de fato.
    private var locationCell: String {
        guard let here = services.location.current else { return "" }
        return "\(Int((here.coordinate.latitude * 2000).rounded())),\(Int((here.coordinate.longitude * 2000).rounded()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            CutScreenHeader(title: "Bairros", corner: ["pra onde hoje?", "tamanho = musts"],
                            subtitle: "\(model.bubbles.count) bairros · toque num pra ver", height: 170, onBack: { dismiss() })
            GeometryReader { geo in
                ZStack {
                    MapLibreView(scene: model.scene, command: command,
                                 onCamera: { model.camera = $0 })
                    edges(in: geo.size)
                    bubbles(in: geo.size)
                    you(in: geo.size)
                }
                .clipped()
            }
            .frame(height: 300)
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let sheet = model.sheet {
                        BairroSheetView(sheet: sheet,
                                        onAdjust: { adjust(sheet.area.id) },
                                        onMontar: { montar(sheet.area.id) })
                    }
                    ForEach(model.bubbles.sorted { ($0.count, $1.name) > ($1.count, $0.name) }) { bubble in
                        index(bubble)
                    }
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            model.prepare(region: region)
            refresh()
            // Depois do refresh: a câmera enquadra as bolhas já calculadas.
            command = model.initialCommand(areaId: initialArea, near: services.location.current, compact: true)
            if let initialArea { model.select(initialArea) }
        }
        .task { await clock() }
        .onChange(of: places.count) { _, _ in refresh() }
        .onChange(of: locationCell) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleRefresh() }
    }

    // MARK: Gatilhos

    private func refresh() {
        model.refresh(places: places, now: AppClock.now, location: services.location.current, trip: trips.first,
                      settings: settingsList.first)
    }

    private func scheduleRefresh() {
        saveRefresh?.cancel()
        saveRefresh = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    /// Relógio: abertos agora mudam a cada minuto.
    private func clock() async {
        while !Task.isCancelled {
            let seconds = 60 - Int(AppClock.now.timeIntervalSince1970) % 60
            try? await Task.sleep(for: .seconds(Double(seconds) + 0.5))
            refresh()
        }
    }

    // MARK: Camadas sobre o mapa

    private func edges(in size: CGSize) -> some View {
        ZStack {
            ForEach(model.edges) { edge in
                if let a = model.point(lat: edge.aLat, lng: edge.aLng, in: size),
                   let b = model.point(lat: edge.bLat, lng: edge.bLng, in: size) {
                    Path { path in
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                    .stroke(V8.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    Text("\(edge.minutes)′")
                        .font(V8Font.mono(11, weight: .bold))
                        .foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 3)
                        .background(V8.paper.opacity(0.9))
                        .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func bubbles(in size: CGSize) -> some View {
        ZStack {
            ForEach(model.bubbles) { bubble in
                if let p = model.point(lat: bubble.lat, lng: bubble.lng, in: size) {
                    AreaBubbleView(bubble: bubble, selected: model.selectedId == bubble.id)
                        .position(p)
                        .onTapGesture { model.select(model.selectedId == bubble.id ? nil : bubble.id) }
                }
            }
        }
    }

    @ViewBuilder
    private func you(in size: CGSize) -> some View {
        if let here = model.scene.you, let p = model.point(lat: here.latitude, lng: here.longitude, in: size) {
            Circle()
                .fill(Color(hex: 0x2B7BFF))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .frame(width: 14, height: 14)
                .position(p)
                .allowsHitTesting(false)
        }
    }

    // MARK: Índice

    /// Uma linha do índice: a contagem grande, o nome e quantos estão abertos agora.
    private func index(_ bubble: AreaBubble) -> some View {
        let selected = model.selectedId == bubble.id
        return Button { model.select(selected ? nil : bubble.id) } label: {
            HStack(alignment: .center, spacing: 14) {
                Text("\(bubble.count)")
                    .font(V8Font.numeral(44)).tracking(-1)
                    .foregroundStyle(selected ? V8.ink : V8.orange)
                    .frame(width: 76, alignment: .leading)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bubble.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(selected ? V8.ink : V8.white).lineLimit(2)
                    Text("\(bubble.count == 1 ? "1 must" : "\(bubble.count) musts") · \(bubble.openCount) abertos agora")
                        .font(V8Font.text(13)).foregroundStyle(selected ? V8.ink.opacity(0.75) : V8.muteDark).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "xmark" : "chevron.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? V8.ink : V8.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(selected ? V8.orange : V8.ink)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.paper).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bubble.name), \(bubble.count) musts, \(bubble.openCount) abertos agora")
    }

    /// "Ajustar": abre a montagem do dia de hoje já com o bairro (e vizinhos) como foco; nada é gravado ainda.
    private func adjust(_ areaId: String) {
        router.push(.montar(date: region.calendar.startOfDay(for: AppClock.now), focusArea: areaId))
    }

    /// "Montar <bairro>+": grava o dia de hoje no bairro (com vizinhos) e abre o Guia.
    private func montar(_ areaId: String) {
        let date = region.calendar.startOfDay(for: AppClock.now)
        let flights = FlightRules.dayFlights(context.flights(), on: date, region: region)
        do {
            if try model.montar(areaId: areaId, context: context, flights: flights) {
                router.push(.guia(date: date))
            }
        } catch {
            Log.solver.error("montar por bairro falhou: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Uma bolha: círculo com a cor do que mais tem, contagem em mono (kanji no maior) e o nome embaixo.
struct AreaBubbleView: View {
    var bubble: AreaBubble
    var selected: Bool

    var body: some View {
        let d = bubble.diameter
        ZStack {
            Circle()
                .fill(bubble.color.strong)
            if selected {
                Circle().strokeBorder(Color.must.ink, lineWidth: 2.5).padding(-5)
            }
            // v8: a bolha é tinta (`strong`); a contagem vai em papel. Sem kanji (nada em japonês na interface).
            Text("\(bubble.count)")
                .font(.must.mono(d * 0.24, .bold))
                .foregroundStyle(V8.paper)
        }
        .frame(width: d, height: d)
        .overlay(alignment: .bottom) {
            Text(bubble.name.uppercased())
                .font(V8Font.text(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.must.ink)
                .lineLimit(1)
                .fixedSize()
                .offset(y: 20)
        }
        .contentShape(Circle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bubble.name), \(bubble.count) musts, \(bubble.openCount) abertos agora")
    }
}

/// Sheet do bairro (C.14): selo, nome, musts/abertos/tempo, barra de mistura, "Junto, a poucos minutos", frase e botões.
struct BairroSheetView: View {
    var sheet: BairroSheet
    var onAdjust: () -> Void
    var onMontar: () -> Void

    private var meta: String {
        var parts = ["\(sheet.count) musts", "\(sheet.openCount) abertos"]
        if let travelText = sheet.travelText { parts.append(travelText) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                StationStamp(sheet.area.seal, sub: sheet.area.stampSub, size: 74, surface: .paper, filled: false,
                             rotation: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sheet.area.name)
                        .font(V8Font.display(30))
                        .foregroundStyle(V8.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(meta)
                        .font(V8Font.text(13))
                        .foregroundStyle(V8.mute)
                        .lineLimit(2)
                }
            }
            MixBar(parts: sheet.mix, total: sheet.count)
            if !sheet.neighbors.isEmpty {
                MonoLabel("junto, a poucos minutos", color: V8.mute)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(sheet.neighbors) { neighbor in
                            NeighborChipView(neighbor: neighbor)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if !sheet.phrase.isEmpty {
                Text(sheet.phrase)
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            }
            HStack(spacing: 10) {
                CutButton(title: "Ajustar", action: onAdjust)
                Button(action: onMontar) {
                    Text("Montar \(sheet.area.name)+".uppercased())
                        .font(V8Font.mono(12, weight: .semibold)).tracking(1)
                        .foregroundStyle(V8.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(V8.orange)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
    }
}

/// Barra de mistura: uma fatia por categoria do bairro, na cor forte.
struct MixBar: View {
    var parts: [MixPart]
    var total: Int

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(part.color.strong)
                        .frame(width: geo.size.width * CGFloat(part.count) / CGFloat(max(total, 1)))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Rectangle())
    }
}

/// Vizinho na sheet: chip da linha (código e cor oficial) com o nome e o tempo; a pé, um chip neutro.
struct NeighborChipView: View {
    var neighbor: NeighborChip

    var body: some View {
        if let line = neighbor.line {
            LineChip(code: line.code, name: "\(neighbor.name) · \(neighbor.minutes) min", color: line.rgb)
        } else {
            LineChip(code: "PÉ", name: "\(neighbor.name) · \(neighbor.minutes) min", color: 0xEEF0F3)
        }
    }
}
