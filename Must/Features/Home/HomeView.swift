import CoreLocation
import SwiftData
import SwiftUI

/// 01 · Hoje, a capa do dia (prompt 23 §2, `CapaJP/BR/IT.png`; com foto: `CapaFoto.png`).
/// Cor do lugar, ficha técnica nos cantos, "Hoje é <bairro> / e <noite>", numeral do dia sangrando e o card "Agora".
/// Gestos: pra cima = Linha do dia; pra baixo = Bom dia (antes das 10h) / Boa noite (depois das 21h);
/// pra esquerda = Dicas; pra direita (ou o toque na alça da borda) = Atalhos, com o Bolso dentro (prompt 25 · D). Tudo sai de `CapaState`, recalculado nos gatilhos.
/// Saíram da Home (v8): "Por perto" (fica em Guia/Lista), orçamento (Ajustes) e os cards v7.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tripTheme) private var theme
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var trips: [TripInfo]

    @State private var state = CapaState()
    @State private var currentArea: Area?
    @State private var saveRefresh: Task<Void, Never>?
    @State private var showAtalhos = false
    /// O que o toque nos Atalhos pediu: roda quando o painel termina de fechar.
    @State private var atalhoAction: AtalhosAction?
    @Environment(\.openURL) private var openURL

    private var region: Region { store.region }
    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }
    private var ink: Color { theme.coverInk }

    private var forcePhoto: Bool { DebugFlags.has("-capaFoto") }
    private var usesPhoto: Bool {
        CapaPhotoPolicy.usesPhoto(hasDiskPhoto: state.photo != nil, forced: forcePhoto,
                                  debugScreen: DebugFlags.string("debugScreen") != nil) && state.photo != nil
    }

    private var locationCell: String {
        guard let here = services.location.current else { return "" }
        return "\(Int((here.coordinate.latitude * 2000).rounded())),\(Int((here.coordinate.longitude * 2000).rounded()))"
    }

    var body: some View {
        Group {
            if let content = state.content {
                if usesPhoto { photoCover(content) } else { colorCover(content) }
            } else {
                theme.cover.ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard let swipe = CapaSwipe.from(value.translation) else { return }
            go(swipe)
        })
        .accessibilityAction(named: "Linha do dia") { go(.up) }
        .accessibilityAction(named: "Dicas") { go(.left) }
        .accessibilityAction(named: "Atalhos") { go(.right) }
        .overlay(alignment: .trailing) { atalhosHandle }
        .fullScreenCover(isPresented: $showAtalhos, onDismiss: runAtalhoAction) {
            AtalhosPanel { action in
                atalhoAction = action
                withoutAnimation { showAtalhos = false }
            }
            .presentationBackground(.clear)
        }
        .onAppear {
            refresh()
            // `-debugScreen atalhos` (prints): abre o painel em cima da capa.
            if DebugFlags.string("debugScreen") == "atalhos", !showAtalhos { openAtalhos() }
        }
        .task { await clock() }
        .task(id: locationCell) { await resolveCurrentArea() }
        .task(id: state.areaId) {
            await state.loadPhoto(region: region, places: places, services: services, forced: forcePhoto)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleRefresh() }
    }

    // MARK: Gatilhos

    private func refresh() {
        let now = AppClock.now
        let trip = trips.first
        state.refresh(.init(region: region, now: now, engine: engine, context: context, trip: trip, expenses: expenses,
                            currentArea: currentArea, nowWeather: services.sync.now(region: region, trip: trip),
                            todayWeather: services.sync.weather(on: now, region: region, trip: trip)))
    }

    private func scheduleRefresh() {
        saveRefresh?.cancel()
        saveRefresh = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    private func clock() async {
        while !Task.isCancelled {
            let seconds = 60 - Int(AppClock.now.timeIntervalSince1970) % 60
            try? await Task.sleep(for: .seconds(Double(seconds) + 0.5))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    private func resolveCurrentArea() async {
        guard let here = services.location.current else { return }
        let area = await services.currentArea.area(at: here, region: region)
        guard area != currentArea else { return }
        currentArea = area
        refresh()
    }

    private func go(_ swipe: CapaSwipe) {
        switch CapaSwipe.action(for: swipe, now: AppClock.now, region: region) {
        case .atalhos: openAtalhos()
        case .route(let route): router.push(route, on: .hoje)
        case nil: break
        }
    }

    // MARK: Atalhos (prompt 25 · D)

    /// O painel anima sozinho (entra pela direita); a apresentação em si não tem animação (abre na hora).
    private func openAtalhos() {
        atalhoAction = nil
        withoutAnimation { showAtalhos = true }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    private func runAtalhoAction() {
        guard let action = atalhoAction else { return }
        atalhoAction = nil
        switch action {
        case .route(let route): router.push(route, on: .hoje)
        case .sheet(let sheet): router.sheet = sheet
        case .selectTab(let tab): router.select(tab)
        case .url(let url): openURL(url)
        }
    }

    /// Alça na borda direita da capa: o "toque no canto" que abre os Atalhos sem deslizar.
    private var atalhosHandle: some View {
        Button(action: openAtalhos) {
            Capsule()
                .fill(ink.opacity(0.35))
                .frame(width: 5, height: 46)
                .frame(width: 28, height: 96)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Atalhos")
        .accessibilityHint("Suica, ingressos, mapa offline, SOS e linhas perto")
    }

    private func openAgora(_ content: CapaContent) {
        if content.agora?.dayOver == true {
            router.push(.boaNoite, on: .hoje)
        } else if content.hasPlan {
            router.push(.agora, on: .hoje)
        } else {
            router.push(.montar(date: today), on: .hoje)
        }
    }

    // MARK: Capa com a cor do lugar (01)

    private func colorCover(_ content: CapaContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow(content).padding(.top, 10)
            Spacer(minLength: 20).frame(maxHeight: 170)
            HStack(alignment: .top) {
                SpecStack(lines: content.midLeft, color: ink)
                Spacer(minLength: 12)
                SpecStack(lines: content.midRight, color: ink, alignment: .trailing)
            }
            Spacer(minLength: 16).frame(maxHeight: 64)
            title(content)
            Spacer(minLength: 16)
            HStack {
                Spacer(minLength: 0)
                agoraCard(content).frame(maxWidth: 236)
            }
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Texturas no fundo: não entram na conta do layout (o numeral e os arcos sangram a tela).
        .background {
            ZStack {
                theme.cover
                Rings(color: ink, count: 3, diameter: 420, opacity: 0.55, offset: CGSize(width: 60, height: 40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                BigNumeral(content.numeral, size: 430, color: ink)
                    .fixedSize()
                    .offset(x: -12, y: 96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    private func topRow(_ content: CapaContent, onPhoto: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SpecStack(lines: content.topLeft, color: ink).modifier(PhotoChip(on: onPhoto))
            Spacer(minLength: 8)
            SpecStack(lines: content.topRight, color: ink, alignment: .trailing).modifier(PhotoChip(on: onPhoto)).padding(.top, 2)
            RoundButton(systemImage: "sparkle", label: "Dicas", style: .line, tint: ink) { router.push(.dicas, on: .hoje) }
                .padding(.top, -8)
        }
    }

    private func title(_ content: CapaContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            countryLine(content, suffix: nil)
            MonoLabel("Hoje é", size: 10, color: ink.opacity(0.85))
            Text(content.area)
                .font(V8Font.display(54))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let evening = content.evening {
                Text(evening)
                    .font(V8Font.display(28, weight: 500))
                    .foregroundStyle(ink.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dia \(content.numeral). Hoje é \(content.area)\(content.evening.map { ", \($0)" } ?? "")")
    }

    private func countryLine(_ content: CapaContent, suffix: String?) -> some View {
        HStack(spacing: 8) {
            theme.flag.frame(width: 22, height: 22)
            SpecLabel([content.country, suffix].compactMap { $0 }.joined(separator: " · "), color: ink)
        }
    }

    /// Card preto "Agora · k de n" com ↗ (abre o Agora). Sem dia: "Hoje, pra onde?" → Montar.
    private func agoraCard(_ content: CapaContent) -> some View {
        Button { openAgora(content) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(content.agora?.title ?? "Hoje, pra onde?", size: 10, color: V8.orange)
                    Text(content.agora?.line ?? "Montar o dia")
                        .font(V8Font.text(15, weight: .bold))
                        .foregroundStyle(V8.white)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V8.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(V8.white))
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 14)
            .frame(minHeight: 70)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(V8.ink))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("\(content.agora?.title ?? "Hoje, pra onde?"): \(content.agora?.line ?? "montar o dia")")
    }

    // MARK: Capa com foto (01b/01c)

    /// Foto do bairro em cor cheia em cima; embaixo, faixa sólida na cor do lugar com o texto (sem degradê, sem foto
    /// atrás do texto). A ficha técnica de cima fica sobre a foto, como no design.
    private func photoCover(_ content: CapaContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow(content, onPhoto: true)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            Spacer(minLength: 24)
            if let photo = state.photo {
                Text("\(content.area) · \(photo.source ?? "Wikimedia Commons")".uppercased())
                    .font(V8Font.mono(8))
                    .tracking(0.8)
                    .foregroundStyle(V8.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(V8.ink.opacity(0.6)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .accessibilityLabel(photo.credit)
            }
            // Faixa sólida na cor do lugar: o texto nunca fica em cima da foto.
            VStack(alignment: .leading, spacing: 8) {
                countryLine(content, suffix: "hoje é")
                Text(content.area)
                    .font(V8Font.display(48))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let evening = content.evening {
                    Text(evening).font(V8Font.display(24, weight: 500)).foregroundStyle(ink.opacity(0.9))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                agoraCard(content).frame(maxWidth: 236).padding(.top, 22)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    theme.cover
                    BigNumeral(content.numeral, size: 300, color: ink)
                        .fixedSize()
                        .offset(x: 40, y: 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .clipped()
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A foto em cor cheia ocupa a tela toda por trás; a faixa de baixo a cobre.
        .background {
            CapaPhoto(photo: state.photo, placeholder: theme.cover)
                .ignoresSafeArea()
        }
    }
}

/// Ficha técnica sobre a foto: num retângulo de tinta sólido (sem degradê), pra ler em qualquer foto.
private struct PhotoChip: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on {
            content.padding(.horizontal, 7).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(V8.ink.opacity(0.6)))
        } else {
            content
        }
    }
}

/// Foto da capa: só o que já está no aparelho (arquivo do Google ou cópia do Commons no `DiskCache`). Enquanto lê,
/// a cor do lugar (placeholder). Sem rede, nada muda.
private struct CapaPhoto: View {
    var photo: CCPhoto?
    var placeholder: Color
    @State private var image: UIImage?

    private var url: URL? { photo.flatMap { URL(string: $0.largeURL ?? $0.url) } }

    var body: some View {
        placeholder
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await PhotoLoader.load(url)
            }
    }
}
