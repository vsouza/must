import CoreLocation
import SwiftData
import SwiftUI

/// Início (prompt 18 · B, `Home6.png`): o dia (bairro, agora, progresso), "Amanhã, pra onde?", uma linha de
/// "Por perto" e o "+". O orçamento não está aqui: a Home mostra só "gasto hoje" (meta em Ajustes › Dia).
/// Tudo que aparece sai de `HomeState`, recalculado nos gatilhos (minuto, posição ≥ 50 m, salvar, voltar).
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tripTheme) private var theme

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var days: [PlannedDay]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var state = HomeState()
    /// "Por perto:" da Home (prompt 14 · B): só o cache de 30 min e o board.
    @State private var nearbyHint: NearbyScored?
    @State private var nearbyCheckedAt = Date.distantPast
    @State private var saveRefresh: Task<Void, Never>?

    private var region: Region { store.region }

    /// Célula de ~55 m: o `.onChange` só dispara quando o GPS anda de fato (o filtro de 50 m já está no serviço).
    private var locationCell: String {
        guard let here = services.location.current else { return "" }
        return "\(Int((here.coordinate.latitude * 2000).rounded())),\(Int((here.coordinate.longitude * 2000).rounded()))"
    }

    private var nearbyKey: String {
        services.location.current.map { NearbyCell.key(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, region: region) } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 8)
                if services.connectivity.isOffline {
                    offlineChip.padding(.top, 12)
                }
                dayCard.padding(.top, 16)
                tomorrowSection.padding(.top, 16)
                HStack(spacing: 12) { nearbyRow; addButton }.padding(.top, 14)
                spendLine.padding(.top, 8)
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .tripWash()
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .home)
            }
            .ignoresSafeArea()
        }
        .onAppear { refresh() }
        // Relógio: recalcula a cada minuto (abertos agora, "Agora", fila) — o sono vai até o próximo minuto cheio.
        .task { await clock() }
        .task(id: nearbyKey) { await refreshNearbyHint() }
        .task(id: state.heroKey) { await state.loadHeroes(services: services, region: region, cityName: region.displayName) }
        .onChange(of: locationCell) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refresh()
            // Voltou pra frente depois de 20 min: olha o cache de novo (sem rede).
            if AppClock.now.timeIntervalSince(nearbyCheckedAt) > 20 * 60 {
                Task { await refreshNearbyHint() }
            }
        }
        // Salvou no SwiftData (lugar, dia, gasto): recalcula uma vez, depois de 300 ms de silêncio.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleRefresh() }
    }

    // MARK: Gatilhos

    /// Monta a entrada a partir do que a view já tem (`@Query`, serviços). Só chamado nos gatilhos.
    private func refresh() {
        let now = AppClock.now
        let trip = trips.first
        let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: region.calendar.startOfDay(for: now)) ?? now
        state.refresh(HomeState.Inputs(
            region: region, now: now, trip: trip, places: places, expenses: expenses, days: days,
            location: services.location.current,
            tomorrowWeather: services.sync.weather(on: tomorrow, region: region, trip: trip),
            nowTemp: services.sync.now(region: region, trip: trip)?.temp
        ))
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
            refresh()
            let seconds = 60 - Int(AppClock.now.timeIntervalSince1970) % 60
            try? await Task.sleep(for: .seconds(Double(seconds) + 0.5))
        }
    }

    /// Lê só o cache (até 30 min) e o board. Nunca chama Google, Wikipedia nem Foursquare.
    private func refreshNearbyHint() async {
        let now = AppClock.now
        nearbyCheckedAt = now
        guard settingsList.first?.suggestNearby ?? true, let location = services.location.current else {
            nearbyHint = nil
            return
        }
        let batch = await services.nearby.cached(lat: location.coordinate.latitude, lng: location.coordinate.longitude,
                                                 region: region, now: now)
        nearbyHint = DiscoverBuilder.hint(batch: batch, places: places, origin: location, now: now, region: region)
    }

    // MARK: Topo

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.must.ink)
                Text("済").font(.must.kanji(15)).foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .onLongPressGesture(minimumDuration: 0.6) {
                #if DEBUG
                router.cover = .gallery
                #endif
            }
            .accessibilityLabel("Must")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.dateLine)
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                    TripFlag(theme)
                }
                Text(state.cityLine)
                    .font(.must.mono(10))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(theme.labelColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            IconButton(.calendario, label: "Viagem") { router.push(.trip, on: .inicio) }
            Button { router.push(.settings, on: .inicio) } label: {
                Text("V")
                    .font(.must.archivo(15, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(MustGradient.avatar))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Ajustes")
            IconButton(.adicionar, style: .dark, label: "Assistente") { router.sheet = .assistant }
        }
    }

    /// "sem internet · offline ok" (A.4): o app segue funcionando com o que está no aparelho.
    private var offlineChip: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: 0xFFB020)).frame(width: 8, height: 8)
            Text("sem internet · offline ok")
                .font(.must.archivo(12, .semibold))
                .foregroundStyle(Color(hex: 0x4A2E00))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(hex: 0xFFF1D6)))
        .accessibilityLabel("Sem internet; o app funciona offline")
    }

    // MARK: Card do dia

    @ViewBuilder
    private var dayCard: some View {
        if let day = state.day {
            dayPanel(day)
        } else {
            pickPanel
        }
    }

    /// Card grande com foto do bairro escurecida: "Hoje em <bairro>", selo, bloco Agora e progresso em selos.
    private func dayPanel(_ day: HomeDay) -> some View {
        let photo = day.areaId.flatMap { state.heroes[$0] }
        return ZStack(alignment: .topLeading) {
            HeroBackdrop(photo: photo, fallback: .eat)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Micro("Hoje em", color: .white.opacity(0.7))
                        Text(day.title)
                            .font(.must.archivo(30, .bold))
                            .tracking(-0.6)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(day.subtitle)
                            .font(.must.archivo(13))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    StationStamp(day.seal, sub: day.sealSub, size: 74, rotation: -8)
                }
                Spacer(minLength: 12)
                if let current = day.current {
                    VStack(alignment: .leading, spacing: 4) {
                        Micro("Agora", color: Color.must.green)
                        Text(current.name)
                            .font(.must.archivo(24, .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let detail = day.currentDetail {
                            Text(detail)
                                .font(.must.archivo(13.5))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                } else if day.allDone {
                    Text("Dia feito 済")
                        .font(.must.archivo(20, .semibold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    progress(day.stops)
                    Spacer(minLength: 4)
                    if let placeId = day.currentPlaceId {
                        Button { router.push(.comoChegar(placeId: placeId), on: .inicio) } label: {
                            Text("Ir agora")
                                .font(.must.archivo(14, .semibold))
                                .foregroundStyle(Color.must.greenText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(Color.must.green))
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
                .padding(.top, 14)
                if let photo {
                    Credit(photo.credit, color: Color.must.ink, url: photo.pageURL)
                        .padding(.top, 10)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 296)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.must.ink.opacity(0.22), radius: 25, y: 22)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { router.push(.guia(date: today), on: .inicio) }
        .accessibilityAddTraits(.isButton)
    }

    /// Sem dia montado: "Hoje, pra onde?" com os 3 bairros com mais musts abertos agora.
    private var pickPanel: some View {
        let photo = state.pick.first.flatMap { state.heroes[$0.id] }
        return ZStack(alignment: .topLeading) {
            HeroBackdrop(photo: photo, fallback: .night)
            VStack(alignment: .leading, spacing: 0) {
                Micro("Hoje", color: .white.opacity(0.7))
                Text("Hoje, pra onde?")
                    .font(.must.archivo(28, .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .padding(.top, 2)
                Text(state.pickIsFallback ? "nada aberto agora · os 3 com mais musts" : "os 3 bairros com mais musts abertos agora")
                    .font(.must.archivo(13))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 2)
                VStack(spacing: 8) {
                    ForEach(state.pick) { entry in
                        Button { router.push(.bairros(areaId: entry.id), on: .inicio) } label: { pickRow(entry) }
                            .buttonStyle(MustPressStyle())
                    }
                }
                .padding(.top, 16)
                Spacer(minLength: 14)
                Button { router.push(.bairros(areaId: nil), on: .inicio) } label: {
                    Text("Montar por bairro")
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.greenText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.must.green))
                }
                .buttonStyle(MustPressStyle())
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 296)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.must.ink.opacity(0.22), radius: 25, y: 22)
    }

    private func pickRow(_ entry: AreaEntry) -> some View {
        HStack(spacing: 12) {
            StationStamp(entry.area.seal, size: 36, fillOpacity: 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.area.name)
                    .font(.must.archivo(16, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(entry.openCount) abertos agora · \(entry.count) musts")
                    .font(.must.archivo(12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            MustIconView(.avancar, size: 14)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.14)))
    }

    /// Progresso em selos: 済 feito, número atual (branco), próximos (contorno). Janela de 5 em volta do atual.
    private func progress(_ stops: [HomeStop]) -> some View {
        let current = stops.firstIndex { $0.isCurrent } ?? max(0, stops.count - 1)
        let start = min(max(0, current - 2), max(0, stops.count - 5))
        let window = Array(stops.dropFirst(start).prefix(5))
        return HStack(spacing: 6) {
            ForEach(Array(window.enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 8, height: 2)
                }
                progressSeal(stop)
            }
            if stops.count > window.count + start {
                Text("+\(stops.count - start - window.count)")
                    .font(.must.mono(11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stops.filter(\.done).count) de \(stops.count) feitos")
    }

    private func progressSeal(_ stop: HomeStop) -> some View {
        ZStack {
            if stop.done {
                Circle().fill(Color.must.green)
                Text("済").font(.must.kanji(11)).foregroundStyle(Color.must.greenText)
            } else if stop.isCurrent {
                Circle().fill(.white)
                Text("\(stop.number)").font(.must.archivo(11, .bold)).foregroundStyle(Color.must.ink)
            } else {
                Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                Text("\(stop.number)").font(.must.archivo(11, .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }

    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }

    // MARK: Amanhã

    private var tomorrowSection: some View {
        let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle().fill(theme.tripColor).frame(width: 6, height: 6)
                    Text("Amanhã, pra onde?")
                        .font(.must.archivo(17, .semibold))
                        .foregroundStyle(Color.must.ink)
                }
                Spacer()
                Button { router.push(.bairros(areaId: nil), on: .inicio) } label: {
                    Text("ver todos")
                        .font(.must.mono(11))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(Color.must.ink)
                }
            }
            HStack(spacing: 10) {
                ForEach(state.tomorrow) { card in
                    Button { router.push(.bairros(areaId: card.id), on: .inicio) } label: { areaCard(card) }
                        .buttonStyle(MustPressStyle())
                }
            }
        }
    }

    /// Cartão de bairro: foto escurecida, selo no canto, nome, contagem, chip de contexto e faixa da categoria.
    private func areaCard(_ card: HomeAreaCard) -> some View {
        let entry = card.entry
        let photo = state.heroes[entry.id]
        let dominant = entry.dominant
        return ZStack(alignment: .bottomLeading) {
            AreaPhotoView(photo: photo, fallback: dominant ?? .eat)
            LinearGradient(colors: [.clear, Color.must.ink.opacity(0.82)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.area.name)
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(countLine(entry))
                    .font(.must.archivo(11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if let context = card.context {
                    Text(context)
                        .font(.must.archivo(10, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.22)))
                        .padding(.top, 3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 116)
        .overlay(alignment: .topTrailing) {
            StationStamp(entry.area.seal, size: 34, fillOpacity: 0.5)
                .padding(8)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill((dominant ?? .eat).strong)
                .frame(height: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.must.ink.opacity(0.14), radius: 12, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func countLine(_ entry: AreaEntry) -> String {
        guard let dominant = entry.dominant, let n = entry.mix[dominant] else { return "\(entry.count) musts" }
        return "\(entry.count) musts · \(n) \(dominant.label)"
    }

    // MARK: Por perto · gasto · +

    /// Uma linha: a dica do cache ("Por perto: Golden Gai") ou, sem dica, o mapa dos abertos agora.
    private var nearbyRow: some View {
        Button {
            if nearbyHint != nil {
                router.push(.discover, on: .inicio)
            } else {
                router.mapShowsOpenNow = true
                router.select(.mapa)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.must.surface)
                    MustIconView(.mapa, size: 20)
                        .foregroundStyle(Color.must.ink)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nearbyTitle)
                        .font(.must.archivo(14, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                    Text(nearbySubtitle)
                        .font(.must.archivo(12))
                        .foregroundStyle(Color.must.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                MustIconView(.avancar, size: 14)
                    .foregroundStyle(Color.must.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.must.surface2))
        }
        .buttonStyle(MustPressStyle())
    }

    private var nearbyTitle: String {
        guard let nearbyHint else { return "Perto de você" }
        return "Por perto: \(nearbyHint.candidate.place.name)"
    }

    private var nearbySubtitle: String {
        guard let nearbyHint else {
            let n = state.openNearbyCount
            return n == 0 ? "nada aberto perto agora · no mapa" : "\(n) \(n == 1 ? "must aberto" : "musts abertos") perto · no mapa"
        }
        let c = nearbyHint.candidate
        var parts: [String] = []
        if let rating = c.place.rating { parts.append(rating.formatted(.number.precision(.fractionLength(1)).locale(region.locale))) }
        parts.append(Walk.distanceText(c.distance))
        parts.append("fora do board")
        return parts.joined(separator: " · ")
    }

    /// "gasto hoje ¥ 4.250 · orçamento fica em Ajustes" (o orçamento e a meta estão em Ajustes › Dia).
    private var spendLine: some View {
        let amount = Text(region.money(state.spentToday)).font(.must.mono(12, .semibold)).foregroundStyle(Color.must.ink)
        return Button { router.push(.settings, on: .inicio) } label: {
            Text("gasto hoje \(amount) · orçamento fica em Ajustes")
                .font(.must.archivo(12))
                .foregroundStyle(Color.must.secondary)
        }
        .buttonStyle(.plain)
    }

    /// "+" verde (Adicionar), ao lado do "Por perto" como no Home6: hoje abre Link/Nome; o Texto é a fatia E.
    private var addButton: some View {
        Button { router.sheet = .addLink(url: nil, listId: nil) } label: {
            ZStack {
                Circle().fill(Color.must.green)
                MustIconView(.adicionar, size: 22)
                    .foregroundStyle(Color.must.greenText)
            }
            .frame(width: 54, height: 54)
            .shadow(color: Color.must.ink.opacity(0.2), radius: 14, y: 8)
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("Adicionar")
    }
}

/// Foto do bairro com a escurecida de baixo pra cima (cards grandes da Início). Sem foto: a cor da categoria.
struct HeroBackdrop: View {
    var photo: CCPhoto?
    var fallback: MustColor

    var body: some View {
        ZStack {
            AreaPhotoView(photo: photo, fallback: fallback)
            LinearGradient(
                stops: [
                    // Topo também escuro: o nome do bairro fica legível em foto clara.
                    .init(color: Color(hex: 0x15171C).opacity(0.62), location: 0),
                    .init(color: Color(hex: 0x15171C).opacity(0.45), location: 0.35),
                    .init(color: Color(hex: 0x15171C).opacity(0.6), location: 0.55),
                    .init(color: Color(hex: 0x15171C).opacity(0.96), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .background(Color(hex: 0x15171C))
    }
}

/// Foto de um bairro ou lugar: cache primeiro (`PhotoLoader`), sem spinner. Sem foto, o gradiente da cor.
struct AreaPhotoView: View {
    var photo: CCPhoto?
    var fallback: MustColor
    @State private var image: UIImage?

    private var url: URL? { photo.flatMap { URL(string: $0.largeURL ?? $0.url) } }

    var body: some View {
        fallback.gradient
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().saturation(0.8)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await PhotoLoader.load(url)
            }
    }
}

