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
        GeometryReader { geo in
            ZStack {
                MapLibreView(scene: model.scene, command: command,
                             onCamera: { model.camera = $0 })
                    .ignoresSafeArea()
                edges(in: geo.size)
                bubbles(in: geo.size)
                you(in: geo.size)
                StatusBarScrim()
            }
        }
        .overlay(alignment: .top) { topBar.padding(.horizontal, 16).padding(.top, 6) }
        .overlay(alignment: .bottom) { bottom.padding(.horizontal, 12).padding(.bottom, 100) }
        .tripWash()
        .background(Color.must.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            model.prepare(region: region)
            refresh()
            // Depois do refresh: a câmera enquadra as bolhas já calculadas.
            command = model.initialCommand(areaId: initialArea, near: services.location.current)
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
                    .stroke(Color.must.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    Text("\(edge.minutes)′")
                        .font(.must.mono(11, .bold))
                        .foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 3)
                        .background(Color.white.opacity(0.7))
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

    // MARK: Topo e base

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { circle("chevron.left") }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel("Voltar")
                Text("Pra onde hoje?")
                    .font(.must.archivo(16, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(.white.opacity(0.92)))
                    .shadow(color: Color.must.ink.opacity(0.12), radius: 10, y: 4)
                Spacer(minLength: 0)
            }
            Text("tamanho = musts · cor = o que mais tem")
                .font(.must.archivo(12))
                .foregroundStyle(Color.must.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.92)))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if let sheet = model.sheet {
            BairroSheetView(sheet: sheet,
                            onAdjust: { adjust(sheet.area.id) },
                            onMontar: { montar(sheet.area.id) })
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Text("toque num bairro")
                .font(.must.archivo(13, .semibold))
                .foregroundStyle(Color.must.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(.white.opacity(0.92)))
                .shadow(color: Color.must.ink.opacity(0.12), radius: 10, y: 4)
        }
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.must.ink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(.white.opacity(0.92)))
            .shadow(color: Color.must.ink.opacity(0.12), radius: 10, y: 4)
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
                .shadow(color: Color.must.ink.opacity(0.18), radius: 8, y: 5)
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
                .font(.must.archivo(10, .bold))
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
            Capsule().fill(Color.must.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            HStack(alignment: .center, spacing: 14) {
                StationStamp(sheet.area.seal, sub: sheet.area.stampSub, size: 74, surface: .paper, filled: false,
                             rotation: -8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sheet.area.name)
                        .font(.must.archivo(30, .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(meta)
                        .font(.must.archivo(13))
                        .foregroundStyle(Color.must.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            MixBar(parts: sheet.mix, total: sheet.count)
            if !sheet.neighbors.isEmpty {
                Micro("Junto, a poucos minutos")
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
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MustGradient.avatar))
                    Text(sheet.phrase)
                        .font(.must.serif(18))
                        .foregroundStyle(Color.must.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.must.surface))
            }
            HStack(spacing: 10) {
                Button(action: onAdjust) {
                    Text("Ajustar")
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .frame(width: 120, height: 52)
                        .background(Capsule().fill(Color.must.surface))
                }
                .buttonStyle(MustPressStyle())
                Button(action: onMontar) {
                    Text("Montar \(sheet.area.name)+")
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.must.ink))
                }
                .buttonStyle(MustPressStyle())
                .layoutPriority(1)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white)
                .shadow(color: Color.must.ink.opacity(0.2), radius: 24, y: -6)
        )
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
        .clipShape(Capsule())
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
