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
    /// "Pôr no dia" já usado (art).
    @State private var addedAt: Date?


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
                        Group {
                            if let panel = kindPanel(place) { panel } else { cards(place) }
                        }
                        .padding(.horizontal, 22).padding(.top, 40)
                        .id("panel")
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
                    let screen = UserDefaults.standard.string(forKey: "debugScreen") ?? ""
                    if screen.hasPrefix("painel") {
                        try? await Task.sleep(for: .milliseconds(600))
                        withAnimation { proxy.scrollTo("panel", anchor: .top) }
                        return
                    }
                    guard screen.hasPrefix("dicas") else { return }
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
                if place.kind == .place || place.kind == .art || place.isDone { statusTag(place) } else { kindTags(place, compact: true) }
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
                    // photo: prata dessaturado; art/sport: tinta mais leve que a das listas.
                    TintedPhoto(url: url, color: color, tintOpacity: place.kind == .photo ? 0.55 : (place.kind == .place ? 0.82 : 0.7))
                        .saturation(place.kind == .photo ? 0.25 : 1)
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
            FlowLayout(spacing: 8) {
                if let list = place.list {
                    Tag([list.displayName, place.sub ?? place.extra?.sport?.activity.label].compactMap { $0 }.joined(separator: " · "), style: .dark)
                }
                kindTags(place)
                if place.kind == .place || place.kind == .art || place.isDone { statusTag(place) }
            }
            Text(place.name)
                .font(.must.archivo(32, .semibold))
                .tracking(-0.6)
                .foregroundStyle(Color.must.ink)
                .fixedSize(horizontal: false, vertical: true)
            let local = subtitle(place)
            if !local.isEmpty {
                Text(local).font(.must.kanji(17, bold: false)).foregroundStyle(Color.must.secondary)
            }
            if let line = place.kind == .place ? sourceLine(place) : (quote(place) ?? sourceLine(place)) {
                Text(line).mustSerif(19).foregroundStyle(Color.must.ink).padding(.top, 4)
            }
        }
    }

    // MARK: Tipos (photo / art / sport)

    private var weather: DayWeather? { services.sync.weather(on: now, region: region, trip: trips.first) }

    private func subtitle(_ place: Place) -> String {
        var parts = [place.nameLocal, place.area]
        if let sport = place.extra?.sport {
            parts.append(sport.distanceKm.map { "\(sport.loop ? "circuito" : "trecho") \(KindLines.km($0)) km" })
            if let e = sport.elevationM { parts.append(e <= 40 ? "plano" : "+\(e) m") }
            parts.append(sport.surface)
        }
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Nota do board como citação (Foto.png: “sol no eixo da rua — …”).
    private func quote(_ place: Place) -> String? {
        let n = place.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let first = n.split(separator: "(").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? n
        let text = first.hasSuffix(".") ? String(first.dropLast()) : first
        return "“\(text.prefix(1).lowercased() + text.dropFirst())”"
    }

    @ViewBuilder private func kindTags(_ place: Place, compact: Bool = false) -> some View {
        switch place.kind {
        case .photo:
            let sun = SunService.day(now, place.coordinate, timeZone: region.timeZone)
            if let tag = KindLines.goldenTag(sun, now: now, region: region) {
                TintTag(tag, bg: MustGradient.goldLight, fg: MustGradient.goldText, icon: .sol)
                    .overlay(Capsule().strokeBorder(MustGradient.goldStrong.opacity(0.6)))
            }
        case .art:
            if let art = place.extra?.art, let left = art.daysLeft(from: now, calendar: region.calendar) {
                if left < 0 {
                    TintTag("temporada acabou", bg: Color.must.surface, fg: Color.must.secondary)
                } else {
                    TintTag(DaySolver.endsText(left), bg: left <= 15 ? KindPalette.warnBg : Color.must.surface,
                            fg: left <= 15 ? KindPalette.warnText : Color.must.ink)
                }
            }
        case .sport:
            if let spot = place.extra?.sport, spot.activity != .watch, let h = weather?.hour(at: now) {
                let good = SportScore.isGood(h, spot: spot)
                let temp = Int(h.temp.rounded())
                TintTag(good ? "bom agora · \(temp)°" : "\(DaySolver.sportRejection(spot, at: now, hourly: weather?.hours ?? []) ?? "evitar")",
                        bg: good ? MustColor.eat.light : KindPalette.warnBg, fg: good ? MustColor.eat.text : KindPalette.warnText)
                if !compact, let uv = h.uv { Tag("UV \(Int(uv.rounded())) · \(KindLines.uvLabel(uv))") }
            }
        case .place:
            EmptyView()
        }
    }

    private func kindPanel(_ place: Place) -> AnyView? {
        let extra = place.extra
        switch place.kind {
        case .photo:
            return AnyView(PhotoPanel(place: place, spot: extra?.photo ?? PhotoSpot(), region: region, now: now, weather: weather,
                                      fetchedAt: services.sync.weatherFetchedAt(on: now, region: region, trip: trips.first)))
        case .art:
            guard let art = extra?.art else { return nil }
            return AnyView(ArtPanel(place: place, art: art, region: region, now: now) { toggleBought($0, place) })
        case .sport:
            guard let spot = extra?.sport else { return nil }
            return AnyView(SportPanel(place: place, spot: spot, region: region, now: now, weather: weather) { toggleBought($0, place) })
        case .place:
            return nil
        }
    }

    private func toggleBought(_ session: EventSession, _ place: Place) {
        var extra = place.extra ?? PlaceExtra()
        if let i = extra.art?.sessions.firstIndex(where: { $0.id == session.id }) { extra.art?.sessions[i].bought.toggle() }
        if let i = extra.sport?.sessions.firstIndex(where: { $0.id == session.id }) { extra.sport?.sessions[i].bought.toggle() }
        place.extra = extra
        try? context.save()
    }

    /// Minutos até o lugar (metrô acima de 1,5 km).
    private func travelMinutes(_ place: Place) -> Int? {
        guard let here = services.location.current?.coordinate else { return nil }
        return DaySolver.leg(here, place.coordinate, walkMax: settingsList.first?.walkMaxKm ?? 1.5).minutes
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

    private func darkButton(_ title: String, icon: MustIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                MustIconView(icon, size: 18)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.must.archivo(15, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Color.must.ink))
        }
        .buttonStyle(MustPressStyle())
    }

    @ViewBuilder private func kindActions(_ place: Place) -> some View {
        switch place.kind {
        case .photo:
            let sun = SunService.day(now, place.coordinate, timeZone: region.timeZone)
            darkButton("Luz de hoje", icon: .sol) { router.push(.light(date: region.calendar.startOfDay(for: now))) }
            if let g = sun.goldenPM, now < g.start {
                let leave = g.start.addingTimeInterval(-Double((travelMinutes(place) ?? 15) + 3) * 60)
                let rounded = Date(timeIntervalSince1970: (leave.timeIntervalSince1970 / 300).rounded(.down) * 300)
                PrimaryButton(rounded > now ? "Sair \(region.timeString(rounded))" : "Sair agora") {
                    MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit)
                }
                .frame(width: 140)
            } else {
                PrimaryButton("Ir agora", icon: .rota) { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) }
                    .frame(width: 140)
            }
        case .art:
            darkButton(travelMinutes(place).map { "Ir agora · \($0) min" } ?? "Ir agora", icon: .rota) {
                MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit)
            }
            let at = addedAt ?? DayInsert.suggestedTime(now: now, region: region, place: place)
            let hour = region.calendar.component(.hour, from: at), minute = region.calendar.component(.minute, from: at)
            let label = minute == 0 ? "\(hour)h" : region.timeString(at)
            if addedAt != nil {
                GhostButton("No dia \(label)") { router.select(.hoje) }.frame(width: 150)
            } else {
                PrimaryButton("Pôr no dia \(label)") {
                    DayInsert.add(place, at: at, region: region, context: context)
                    addedAt = at
                }
                .frame(width: 150)
            }
        case .sport:
            let temp = weather?.hour(at: now).map { " · \(Int($0.temp.rounded()))°" } ?? ""
            darkButton("Começar\(temp)", icon: .aPe) {
                // Strava se estiver instalado; senão, a rota a pé.
                if let strava = URL(string: "strava://record") {
                    UIApplication.shared.open(strava) { ok in
                        if !ok { Task { @MainActor in MapsLinks.openApple(to: place.coordinate, name: place.name) } }
                    }
                }
            }
            if place.isDone {
                GhostButton("Desfazer 済") { PlaceActions.undoDone(place, context: context) }.frame(width: 150)
            } else {
                PrimaryButton("Feito", icon: .feito) { router.sheet = .expense(placeId: place.id) }.frame(width: 130)
            }
        case .place:
            EmptyView()
        }
    }

    private func actions(_ place: Place) -> some View {
        HStack(spacing: 10) {
            if place.kind != .place {
                kindActions(place)
            } else {
                placeActions(place)
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

    @ViewBuilder private func placeActions(_ place: Place) -> some View {
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
}
