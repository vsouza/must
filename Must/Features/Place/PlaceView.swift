import SwiftData
import SwiftUI

/// Lugar: hero, tags, nome, reserva / horário-distância-preço-fonte / notas, "Ir agora" e "Feito".
struct PlaceView: View {
    let placeId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var matches: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var heroPhoto: CCPhoto?
    @State private var tips = TipsModel()
    /// Header comprimido (nome + "Dicas de quem foi" + horário) quando o título sai da tela.
    @State private var compact = false


    init(placeId: String) {
        self.placeId = placeId
        _matches = Query(filter: #Predicate<Place> { $0.id == placeId })
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    var body: some View {
        if let place = matches.first {
            content(place)
        } else {
            VStack(spacing: 12) {
                Text("Esse lugar saiu do board.").mustBody()
                GhostButton("Voltar") { dismiss() }.frame(width: 160)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func content(_ place: Place) -> some View {
        let color = place.list?.color ?? .drink
        return ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(place, color: color)
                        titleBlock(place).padding(.horizontal, 22).padding(.top, -96)
                            .onScrollVisibilityChange(threshold: 0.95) { visible in
                                withAnimation(.easeOut(duration: 0.2)) { compact = !visible }
                            }
                        cards(place).padding(.horizontal, 22).padding(.top, 40)
                        // Só busca as dicas quando a seção aparece (Google cobra SKU Atmosphere).
                        TipsSection(model: tips, region: region)
                            .padding(.horizontal, 22)
                            .padding(.top, 44)
                            .id("tips")
                            .onScrollVisibilityChange(threshold: 0.01) { visible in
                                if visible { Task { await loadTips(place) } }
                            }
                        Color.clear.frame(height: 240).id("tips-end")
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                #if DEBUG
                .task {
                    // -debugScreen dicas:<id> rola direto pras Dicas (prints).
                    guard UserDefaults.standard.string(forKey: "debugScreen")?.hasPrefix("dicas") == true else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    let toEnd = UserDefaults.standard.string(forKey: "debugScreen")?.hasSuffix(":fim") == true
                    withAnimation { proxy.scrollTo(toEnd ? "tips-end" : "tips", anchor: toEnd ? .bottom : .top) }
                }
                #endif
            }

            if compact { compactHeader(place).frame(maxHeight: .infinity, alignment: .top).transition(.opacity) }

            actions(place)
        }
        .background(Color.must.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { services.sync.refreshIfStale(place, region: region) }
        .task(id: place.id) { await loadHero(place) }
    }

    private func loadTips(_ place: Place) async {
        let query = TipsQuery(id: place.id, name: place.name, nameLocal: place.nameLocal,
                              city: trips.first?.city(id: place.cityId)?.name ?? region.displayName, region: region,
                              lat: place.lat, lng: place.lng, googlePlaceId: place.placeId, fsqId: place.fsqId,
                              sourceKind: place.source?.kind, sourceCaption: place.source?.caption, sourceAuthor: place.source?.author,
                              sourceSavedAt: place.source?.savedAt, sourceURL: place.source?.url)
        tips.onFoursquareMatch = { id in
            place.fsqId = id
            try? context.save()
        }
        await tips.load(query, providers: services.tipsProviders(for: query), enabled: settingsList.first?.peopleTips ?? true)
    }

    /// Nome + "Dicas de quem foi" + tag de horário, fixo no topo quando o título sai da tela.
    private func compactHeader(_ place: Place) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { dismiss() } label: {
                    MustIconView(.voltar, size: 18).foregroundStyle(Color.must.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.must.surface))
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Voltar")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(place.name).font(.must.archivo(18, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                        if let local = place.nameLocal {
                            Text(local).font(.must.kanji(12, bold: false)).foregroundStyle(Color.must.secondary).lineLimit(1)
                        }
                    }
                    Micro("dicas de quem foi")
                }
                Spacer(minLength: 6)
                statusTag(place)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 12)
            RowDivider()
        }
        .background(Color.white.ignoresSafeArea(edges: .top))
    }

    /// Foto do Commons perto do lugar (300 m), senão do bairro.
    private func loadHero(_ place: Place) async {
        let photos = services.photos
        guard photos.isConfigured, settingsList.first?.flickrPhotos ?? true, heroPhoto == nil else { return }
        do {
            var found = try await photos.search(near: place.coordinate, radiusKm: 0.3)
            if found.isEmpty, let area = place.area {
                let city = trips.first?.city(id: place.cityId)?.name ?? region.displayName
                found = try await photos.search(text: "\(area) \(city)")
            }
            heroPhoto = found.first
        } catch {
            Log.network.error("hero \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Hero

    private func photoURL(_ place: Place) -> URL? {
        if let heroPhoto { return URL(string: heroPhoto.largeURL ?? heroPhoto.url) }
        return place.list?.photo?.url.flatMap(URL.init(string:))
    }

    private func credit(_ place: Place) -> (text: String, url: URL?)? {
        if let heroPhoto { return (heroPhoto.credit, heroPhoto.pageURL) }
        guard let photo = place.list?.photo, let text = photo.credit else { return nil }
        return (text, photo.page.flatMap(URL.init(string:)))
    }

    private func hero(_ place: Place, color: MustColor) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let url = photoURL(place) {
                    TintedPhoto(url: url, color: color)
                } else {
                    ZStack {
                        MustGradient.sky(opacity: (1, 0.9))
                        BlobBackground(style: .lugar).ignoresSafeArea(edges: [])
                    }
                }
            }
            .frame(height: 390)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.92), .white], startPoint: .top, endPoint: .bottom)
                    .frame(height: 190)
            }

            HStack {
                glassButton(.voltar, label: "Voltar") { dismiss() }
                Spacer()
                glassButton(.ficaProFim, label: place.saveForEnd ? "Tirar de fica pro fim" : "Fica pro fim", on: place.saveForEnd) {
                    place.saveForEnd.toggle()
                    try? context.save()
                }
                glassButton(.editar, label: "Editar") { router.sheet = .editPlace(id: place.id) }
            }
            .padding(.horizontal, 22)
            .padding(.top, 62)

            if photoURL(place) != nil, let credit = credit(place) {
                Credit(credit.text, color: color.text, url: credit.url)
                    .padding(.trailing, 22)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 182)
            }
        }
    }

    private func glassButton(_ icon: MustIcon, label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MustIconView(icon, size: 18)
                .foregroundStyle(on ? .white : Color.must.ink)
                .frame(width: 40, height: 40)
                .background {
                    if on { Circle().fill(Color.must.ink) } else { Color.clear.glass(cornerRadius: 20) }
                }
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: Título

    private func titleBlock(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let list = place.list {
                    Tag([list.displayName, place.sub].compactMap { $0 }.joined(separator: " · "), style: .dark)
                }
                statusTag(place)
            }
            Text(place.name)
                .font(.must.archivo(32, .semibold))
                .tracking(-0.6)
                .foregroundStyle(Color.must.ink)
                .fixedSize(horizontal: false, vertical: true)
            let local = [place.nameLocal, place.area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !local.isEmpty {
                Text(local).font(.must.kanji(17, bold: false)).foregroundStyle(Color.must.secondary)
            }
            if let line = sourceLine(place) {
                Text(line).mustSerif(19).foregroundStyle(Color.must.ink).padding(.top, 4)
            }
        }
    }

    @ViewBuilder private func statusTag(_ place: Place) -> some View {
        if let done = place.done {
            Tag("済 feito \(region.shortDay(done.at))", style: .green)
        } else {
            switch place.openState(at: now, timeZone: region.timeZone) {
            case .open(let until): Tag(until.map { "aberto até \($0)" } ?? "aberto", dot: Color.must.green)
            case .closed(let day, let time):
                Tag(time.map { t in day.map { "abre \($0) \(t)" } ?? "abre \(t)" } ?? "fechado", dot: Color(hex: 0xC5C9D0))
            case .unknown: Tag("sem horário", dot: Color(hex: 0xC5C9D0))
            }
        }
    }

    private func sourceLine(_ place: Place) -> String? {
        guard let source = place.source, source.kind != .board else { return nil }
        let date = source.savedAt.flatMap { BoardDates(timeZone: region.timeZone).day(from: $0) }
            .map { " em \(region.shortDay($0))" } ?? ""
        switch source.kind {
        case .manual: return "“adicionado à mão\(date)”"
        default: return "“salvo de um \(source.kind.label)\(date)”"
        }
    }

    // MARK: Cards

    private func cards(_ place: Place) -> some View {
        VStack(spacing: -26) {
            if let reservation = place.reservation {
                reservationCard(reservation)
                    .stackCard(color: .drink, rotation: -2)
                    .padding(.leading, 56)
                    .padding(.trailing, -40)
                    .zIndex(0)
            }
            infoCard(place)
                .stackCard(tint: .gray, rotation: place.reservation == nil ? -1.5 : 1.5)
                .padding(.leading, place.reservation == nil ? 30 : 28)
                .padding(.trailing, -20)
                .zIndex(1)
            notesCard(place)
                .stackCard(color: .eat, rotation: 0)
                .zIndex(2)
        }
    }

    private func reservationCard(_ r: Reservation) -> some View {
        let cal = region.calendar
        let day = cal.isDate(r.at, inSameDayAs: now) ? "Hoje"
            : region.shortDay(r.at)
        let party = r.party.map { " · \($0) \($0 == 1 ? "pessoa" : "pessoas")" } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Micro("reserva · âncora do dia", color: Color.must.blueText)
            HStack(spacing: 0) {
                Text("\(day) ").font(.must.archivo(26, .semibold))
                Text(region.timeString(r.at)).font(.must.mono(26, .semibold))
                Text(party).font(.must.archivo(26, .semibold))
            }
            .foregroundStyle(Color.must.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let note = r.note { Text(note).font(.must.archivo(13)).foregroundStyle(Color.must.blueText) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoCard(_ place: Place) -> some View {
        let tz = region.timeZone
        var hours = "sem horário"
        if let h = place.hours, h.hasPeriods {
            hours = [h.todayText(now, timeZone: tz), h.closedDays.isEmpty ? nil : "fecha \(h.closedDays.joined(separator: ", "))"]
                .compactMap { $0 }.joined(separator: " · ")
        }
        var distance = "sem GPS"
        if let d = place.distance(from: services.location.current) {
            distance = d <= 2500 ? "\(Walk.minutes(d)) min a pé · \(Walk.distanceText(d))" : Walk.distanceText(d)
        }
        if place.approx { distance += " ~" }
        var price = "—"
        if let p = place.price {
            let level = place.priceLevel.map { String(repeating: region.currencySymbol == "¥" ? "¥" : "$", count: max(1, $0)) + " · " } ?? ""
            price = "\(level)~\(region.money(p, symbol: false))"
        }
        let source = place.source.map { s in
            s.kind == .board ? "board" : s.kind.label + (s.savedAt.map { " · \($0)" } ?? "")
        } ?? "board"

        return VStack(spacing: 14) {
            infoRow("horário", hours)
            infoRow("distância", distance)
            infoRow("preço", price)
            infoRow("fonte", source)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 48)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Micro(label)
            Spacer(minLength: 12)
            Text(value).font(.must.mono(14)).foregroundStyle(Color.must.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func notesCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Micro("notas do board", color: MustColor.eat.text)
            Text(place.notes.isEmpty ? "Sem notas ainda — toque no lápis pra escrever." : place.notes)
                .font(.must.archivo(16))
                .foregroundStyle(Color.must.ink.opacity(place.notes.isEmpty ? 0.6 : 1))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }

    // MARK: Ações

    private func actions(_ place: Place) -> some View {
        HStack(spacing: 10) {
            Button { MapsLinks.openApple(to: place.coordinate, name: place.name) } label: {
                HStack(spacing: 9) {
                    MustIconView(.rota, size: 18)
                    Text("Ir agora")
                }
                .font(.must.archivo(15, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
            .contextMenu {
                Button("Apple Maps · a pé") { MapsLinks.openApple(to: place.coordinate, name: place.name) }
                Button("Apple Maps · transporte") { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) }
                Button("Google Maps") { MapsLinks.openGoogle(to: place.coordinate, mode: .transit) }
            }

            if place.isDone {
                GhostButton("Desfazer 済") { PlaceActions.undoDone(place, context: context) }
                    .frame(width: 150)
            } else {
                PrimaryButton("Feito", icon: .feito) { router.sheet = .expense(placeId: place.id) }
                .frame(width: 130)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 92)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}
