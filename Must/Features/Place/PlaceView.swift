import CoreLocation
import SwiftData
import SwiftUI

/// Lugar no corte (rodada 33, sobre o V9 do prompt 32 §5): uma tela só, "chegue por onde chegar". Foto normal em cima (cor cheia, sem texto por cima, crédito
/// embaixo), nome, estado ("aberto até 22h", com a regra de confiança do `PlaceTrust`), ações visíveis Ir · Encaixar hoje ·
/// Guardar · Dicas · Feito (`PlaceActionPlan`) e as seções em cartões do sistema. Nome local "mostre ao atendente" continua
/// sendo o único lugar com escrita local. Foto: uma por lugar, do disco; sem nada no disco, uma `/media` só pro Lugar aberto.
/// `-debugNoPhotos` força o layout sem foto.
struct PlaceView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let placeId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.showEvents) private var showEvents
    @Environment(\.friends) private var friends
    @Query private var matches: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var heroPhoto: CCPhoto?
    /// Galeria do Google (páginas 1…4; a 0 é `heroPhoto`), carregada ao deslizar (prompt 19).
    @State private var galleryPhotos: [Int: CCPhoto] = [:]
    @State private var galleryPage = 0
    /// Foto em tela cheia (toque na foto): a página da galeria em que abriu.
    @State private var viewer: ViewerStart?
    @State private var tips = TipsModel()
    @State private var addedAt: Date?
    @State private var show3D = false
    @State private var editingTickets = false
    /// Dicas: a busca roda como `.task(id:)`, então cancela quando a seção some ou o lugar troca (prompt 18 · A.4).
    @State private var tipsVisible = false

    init(placeId: String) {
        self.placeId = placeId
        _matches = Query(filter: #Predicate<Place> { $0.id == placeId })
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var here: CLLocation? { services.location.current }
    private var walkMax: Double { settingsList.first?.walkMaxKm ?? 1.5 }
    private var noPhotos: Bool { DebugFlags.bool("debugNoPhotos") }

    var body: some View {
        if let place = matches.first {
            content(place)
        } else {
            VStack(spacing: 14) {
                Text("Esse lugar saiu do board.").font(.body)
                Button("Voltar") { dismiss() }.v9Secondary()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v9Screen()
        }
    }

    // MARK: Estado derivado

    /// Parada do lugar no dia de hoje (motor do dia): número e se é a de agora.
    private func stopInfo(_ place: Place) -> (number: Int, total: Int, isNow: Bool, at: Date)? {
        guard let plan = dayEngine.plan(for: region.calendar.startOfDay(for: now), region: region, context: context),
              let index = plan.stops.firstIndex(where: { $0.placeId == place.id }) else { return nil }
        let current = DayClock.read(engine: dayEngine, region: region, context: context, at: now).now?.current.placeId == place.id
        return (index + 1, plan.stops.count, current, plan.stops[index].start)
    }

    private func photoURL(_ place: Place, page: Int = 0) -> URL? {
        if noPhotos { return nil }
        if page > 0, let photo = galleryPhotos[page] { return URL(string: photo.url) }
        if page == 0, let heroPhoto { return URL(string: heroPhoto.largeURL ?? heroPhoto.url) }
        return page == 0 ? services.photoResolver.cachedHeroURL(refs: place.photoRefs) : nil
    }

    /// "Em cartaz" do lugar (museu, casa de show, estádio): vazio some do Lugar.
    private func emCartaz(_ place: Place) -> [ShowEvent] {
        let provider = EmCartazProvider.resolve(showEvents)
        return PlaceEmCartaz.visible(provider.events(placeId: place.id, at: now), now: now, calendar: region.calendar)
    }

    @ViewBuilder private func emCartazBlock(_ place: Place, onInk: Bool) -> some View {
        let events = emCartaz(place)
        if !events.isEmpty {
            EmCartazSection(events: events, region: region, now: now, onInk: onInk,
                            onPaste: { router.sheet = .addLink(url: nil, listId: nil) },
                            // TODO(r23:A): fluxo próprio de foto do cartaz (Vision + EventExtractor); por ora o leitor de ingresso.
                            onPoster: { router.sheet = .ticketImport(inboxId: nil) })
                .padding(.horizontal, 20).padding(.vertical, 16)
        }
    }

    private func pages(_ place: Place) -> Int { place.placeId == nil ? 1 : max(1, min(place.photoRefs.count, 5)) }

    // MARK: Tela (V9)

    private func content(_ place: Place) -> some View {
        let anchor = PlaceFicha.anchor(place, now: now, calendar: region.calendar)
        let stop = stopInfo(place)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band(place, anchor: anchor, stop: stop)
                    CutRule()
                    creditStrip(place)
                    distanceStrip(place, anchor: anchor)
                    fichaBlock(anchor != nil ? anchorCells(place, anchor: anchor!)
                               : PlaceFicha.cells(place, region: region, now: now, here: here, walkMaxKm: walkMax, queueFirst: true))
                    if let anchor { anchorBlock(anchor, place: place) }
                    actionBar(place, anchor: anchor, inDay: stop != nil)
                    notaBlock(place)
                    lowerSection(place)
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            #if DEBUG
            .task {
                let screen = DebugFlags.string("debugScreen") ?? ""
                if screen.hasPrefix("museu") { ProximosDemo.ensureTeamLab(context: context, dates: BoardDates(timeZone: region.timeZone)) }
                if screen.hasPrefix("3d") { show3D = true; return }
                if screen.hasPrefix("fotos-carrossel") {
                    try? await Task.sleep(for: .milliseconds(3500))
                    viewer = ViewerStart(page: 1)
                    return
                }
                if screen.hasPrefix("painel") || screen.hasPrefix("dicas") {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation { proxy.scrollTo(screen.hasPrefix("dicas") ? "tips" : "panel", anchor: .top) }
                }
            }
            #endif
            .onChange(of: scrollToTips) { _, go in
                guard go else { return }
                withAnimation { proxy.scrollTo("tips", anchor: .top) }
                scrollToTips = false
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .v8Legacy()
        .onAppear { services.sync.refreshIfStale(place, region: region) }
        // Marcou "Feito" (folha de gasto): o momento do colecionável (prompt 27 §4, agente D).
        .onChange(of: place.isDone) { was, isDone in
            if isDone, !was { CollectibleCelebration.present(for: place.id) }
        }
        .task(id: place.id) {
            // Seed nunca sincronizado: resolve este lugar no Places antes da foto (e das Dicas de quem foi).
            await services.sync.ensureResolved(place, region: region, cityName: trips.first?.city(id: place.cityId)?.name)
            await loadHero(place)
        }
        .task(id: "\(place.id)|\(tipsVisible)") { if tipsVisible { await loadTips(place) } }
        .task(id: galleryPage) { await loadGalleryPage(place, index: galleryPage) }
        .fullScreenCover(item: $viewer) { start in
            PhotoViewer(pages: viewerPages(place), index: start.page)
        }
        .fullScreenCover(isPresented: $show3D) {
            Place3DView(name: place.name, coordinate: place.coordinate, heading: place.extra?.photo?.facing)
        }
        .sheet(isPresented: $editingTickets) {
            TicketsEditor(tickets: Binding(get: { place.tickets }, set: { place.tickets = $0; place.syncBoughtSessions(); try? context.save() }),
                          sessions: place.extra?.sessions ?? [], region: region, placeName: place.name)
        }
    }

    // MARK: Foto (o corte: P&B x cor do lugar, nome em Bricolage, régua)

    /// Bloco da foto: a foto que já está no disco (tratada) ou só a cor do lugar; cantos fixos ← e ✦ · …; nome grande embaixo.
    /// Toque na foto abre ela inteira, em cor.
    private func band(_ place: Place, anchor: PlaceFicha.Anchor?, stop: (number: Int, total: Int, isNow: Bool, at: Date)?) -> some View {
        let url = photoURL(place, page: galleryPage)
        let local = PlaceFicha.localLine(place)
        var tags: [String] = []
        if let stop { tags.append(stop.isNow ? "agora · parada \(stop.number)/\(stop.total)" : "parada \(stop.number) · \(region.timeString(stop.at))") }
        else if place.isDone, let done = place.done { tags.append("feito · \(region.shortDay(done.at))") }
        let live = PlaceEmCartaz.nowCount(emCartaz(place), now: now, calendar: region.calendar)
        if live > 0 { tags.append("em cartaz · \(live) agora") }
        return CutBand(photo: url) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    CutCornerButton(systemName: "chevron.left", label: "Voltar", tint: V8.white) { dismiss() }
                    Spacer(minLength: 8)
                    SpecStack(lines: PlaceFicha.specLines(place), color: V8.white.opacity(0.9), alignment: .trailing)
                    moreMenu(place)
                    CutCornerButton(systemName: "sparkles", label: "Assistente", tint: V8.white) { router.sheet = .assistant }
                }
                .padding(.top, 58)
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 6) {
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · ").uppercased()).font(V8Font.mono(10, weight: .semibold)).tracking(1)
                            .foregroundStyle(V8.white).lineLimit(2)
                    }
                    Text(place.name)
                        .font(V8Font.display(48)).tracking(-1.5)
                        .lineLimit(3).minimumScaleFactor(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    // Nome local "mostre ao atendente": o único lugar com escrita local na interface.
                    if !local.isEmpty { Text(local).font(V8Font.text(15)).opacity(0.9).lineLimit(2) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(height: typeSize >= .accessibility1 ? 440 : 390)
        .contentShape(Rectangle())
        .onTapGesture { if url != nil { viewer = ViewerStart(page: galleryPage) } }
        .accessibilityElement(children: .contain)
    }

    /// Crédito da foto (sempre visível quando há foto) e "próxima foto".
    @ViewBuilder private func creditStrip(_ place: Place) -> some View {
        if photoURL(place, page: galleryPage) != nil || pages(place) > 1 {
            HStack(spacing: 8) {
                creditLine(place)
                Spacer(minLength: 8)
                if pages(place) > 1 {
                    Button { withAnimation { galleryPage = (galleryPage + 1) % pages(place) } } label: {
                        Text("PRÓXIMA FOTO").font(V8Font.mono(10, weight: .semibold)).tracking(0.8).foregroundStyle(V8.ink)
                            .padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 2)
            .overlay(alignment: .bottom) { IndexRule() }
        }
    }

    @ViewBuilder private func creditLine(_ place: Place) -> some View {
        let photo = galleryPage > 0 ? galleryPhotos[galleryPage] : heroPhoto
        if photo != nil || photoURL(place, page: galleryPage) != nil {
            let source = photo?.source ?? (photo == nil ? "Google" : "Wikimedia Commons")
            let owner = (photo?.owner).flatMap { $0.isEmpty ? nil : "@\($0)" }
            let text = ["\(galleryPage + 1) de \(pages(place))", source, owner, photo?.licenseName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            Button {
                if let url = photo?.pageURL { UIApplication.shared.open(url) }
            } label: {
                Text(text.uppercased()).font(V8Font.mono(8.5)).tracking(0.6).foregroundStyle(V8.mute).lineLimit(1).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo?.credit ?? "foto")
        }
    }

    // MARK: Estado e ações

    /// Numeral de distância (com significado) + "aberto até ..." (regra de confiança do `PlaceTrust`). Sem GPS, só o estado.
    @ViewBuilder private func distanceStrip(_ place: Place, anchor: PlaceFicha.Anchor?) -> some View {
        let status = PlaceFicha.openTag(place, region: region, now: now)
        let distance = here.flatMap { place.distance(from: $0) }
        let kinds = [anchor == nil ? PlaceFicha.queueTag(place, region: region) : nil, PlaceFicha.coordTag(place)].compactMap { $0 }
        if status != nil || distance != nil || !kinds.isEmpty {
            HStack(alignment: .center, spacing: 14) {
                if let distance {
                    let km = distance >= 1000
                    VStack(alignment: .leading, spacing: 2) {
                        Text(km ? (distance / 1000).formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(1)))
                             : "\(max(10, Int((distance / 10).rounded()) * 10))")
                            .font(V8Font.display(44, width: 78, weight: 800)).tracking(-2).foregroundStyle(V8.orange).lineLimit(1)
                        Text(km ? "KM DAQUI" : "METROS DAQUI").font(V8Font.mono(8.5)).tracking(0.8).foregroundStyle(V8.mute)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("a \(Walk.distanceText(distance)) daqui")
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let status { Text(status).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).fixedSize(horizontal: false, vertical: true) }
                    if !kinds.isEmpty { Text(kinds.joined(separator: " · ")).font(V8Font.text(13)).foregroundStyle(V8.mute) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { IndexRule() }
        }
    }

    private var tipsLabel: String {
        tips.tips.isEmpty ? "Dicas de quem foi" : "\(tips.tips.count) dicas de quem foi"
    }

    private func actionPlan(_ place: Place, anchor: PlaceFicha.Anchor?, inDay: Bool) -> PlaceActionPlan {
        PlaceActionPlan.make(travelMinutes: here.map { PlaceFicha.travelMinutes(place, from: $0, walkMaxKm: walkMax) },
                             isAnchor: anchor != nil, inDay: inDay || addedAt != nil, saveForEnd: place.saveForEnd,
                             isDone: place.isDone, tipsCount: tips.tips.count)
    }

    /// Ir (bloco laranja de ponta a ponta) e, em grade de blocos de régua: Encaixar hoje · Guardar · Dicas · Feito. Tudo visível.
    private func actionBar(_ place: Place, anchor: PlaceFicha.Anchor?, inDay: Bool) -> some View {
        let plan = actionPlan(place, anchor: anchor, inDay: inDay)
        return VStack(spacing: 0) {
            Button { router.push(.ir(placeId: place.id)) } label: {
                HStack {
                    Text(plan.goTitle.uppercased()).font(V8Font.mono(14, weight: .semibold)).tracking(1.2)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(V8.ink)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(V8.orange)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plan.goTitle)
            .contextMenu {
                Button("Apple Maps · a pé") { MapsLinks.openApple(to: place.coordinate, name: place.name) }
                Button("Apple Maps · transporte") { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) }
                Button("Google Maps") { MapsLinks.openGoogle(to: place.coordinate, mode: .transit) }
            }
            HStack(spacing: 0) {
                block(plan.fitTitle, enabled: plan.fitEnabled) {
                    let at = DayInsert.suggestedTime(now: now, region: region, place: place)
                    DayInsert.add(place, at: at, region: region, context: context)
                    addedAt = at
                }
                block(plan.saveTitle, filled: plan.saveIsOn) {
                    place.saveForEnd.toggle()
                    try? context.save()
                }
            }
            HStack(spacing: 0) {
                block(plan.tipsTitle) { tipsVisible = true; scrollToTips = true }
                block(plan.doneTitle) {
                    if plan.doneIsUndo { PlaceActions.undoDone(place, context: context) } else { router.sheet = .expense(placeId: place.id) }
                }
            }
        }
        .overlay(alignment: .bottom) { IndexRule() }
    }

    /// Bloco quadrado da grade de ações: borda de régua, mono caixa alta; `filled` = tinta cheia.
    private func block(_ title: String, enabled: Bool = true, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button { if enabled { action() } } label: {
            Text(title.uppercased()).font(V8Font.mono(12, weight: .semibold)).tracking(1)
                .foregroundStyle(filled ? V8.paper : V8.ink)
                .opacity(enabled ? 1 : 0.4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(filled ? V8.ink : Color.clear)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }

    /// O bilhete da âncora (reserva/ingresso): hora grande, quem, nota; com QR abre o ingresso.
    private func anchorBlock(_ anchor: PlaceFicha.Anchor, place: Place) -> some View {
        Button {
            if let id = anchor.ticketId { router.push(.ticket(placeId: place.id, ticketId: id)) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(region.timeString(anchor.at)).font(V8Font.mono(26, weight: .semibold)).foregroundStyle(V8.ink).fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    let people = anchor.people.map { " · \($0) \($0 == 1 ? "pessoa" : "pessoas")" } ?? ""
                    Text("\(anchor.kind == .ticket ? "Ingresso" : "Reserva") · \(Proximos.dayLabel(anchor.at, now: now, calendar: region.calendar))\(people)")
                        .font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                    let note = anchorNote(anchor)
                    if !note.isEmpty { Text(note).font(V8Font.text(13)).foregroundStyle(V8.ink.opacity(0.8)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if anchor.hasQR { Image(systemName: "qrcode").font(.title3).foregroundStyle(V8.ink).accessibilityLabel("QR salvo") }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.orange)
            .overlay(alignment: .bottom) { IndexRule() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func anchorNote(_ anchor: PlaceFicha.Anchor) -> String {
        var parts: [String] = []
        if let minutes = anchor.minutes, anchor.kind == .reservation { parts.append("turno de \(PlaceFicha.durationText(minutes)), sem exceção") }
        else if anchor.minutes != nil {
            parts.append("entrada \(region.timeString(anchor.at))–\(region.timeString(anchor.at.addingTimeInterval(30 * 60)))")
        }
        if anchor.hasQR { parts.append("QR salvo offline") } else if let note = anchor.note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    /// Âncora: chegar 30 min antes, sair de onde você vai estar (casa da viagem ou aqui) e o ingresso.
    private func anchorCells(_ place: Place, anchor: PlaceFicha.Anchor) -> [PlaceFicha.Cell] {
        let arrive = anchor.at.addingTimeInterval(-30 * 60)
        var cells = [PlaceFicha.Cell(label: "chegar", value: region.timeString(arrive))]
        let today = region.calendar.isDate(anchor.at, inSameDayAs: now)
        let homeArea = trips.first?.home.flatMap { name in AreaCatalog.areas(for: region).first { $0.name == name } }
        let origin: (name: String, point: CLLocationCoordinate2D)? = if today, let here {
            ((CurrentAreaService.curated(here, in: AreaCatalog.areas(for: region))?.name ?? "aqui"), here.coordinate)
        } else if let homeArea {
            (homeArea.name, homeArea.centroid.clCoordinate)
        } else {
            nil
        }
        if let origin {
            let leg = DaySolver.leg(origin.point, place.coordinate, walkMax: walkMax)
            let leave = arrive.addingTimeInterval(-Double(leg.minutes) * 60)
            let mode = leg.mode == .walk ? "a pé" : (region.profile.transit?.placeLabel ?? "metrô")
            cells.append(.init(label: "saia de \(origin.name)", value: "\(region.timeString(leave)) · \(mode)"))
        }
        if let cost = PlaceFicha.cost(place, region: region, now: now) {
            cells.append(.init(label: "ingresso", value: cost.value))
        }
        return cells
    }

    // MARK: Ficha e nota

    /// Ficha: rótulo mono à esquerda, valor à direita, uma régua de 2 pt entre as linhas. No Dynamic Type grande o valor desce.
    private func fichaBlock(_ cells: [PlaceFicha.Cell]) -> some View {
        VStack(spacing: 0) {
            ForEach(cells, id: \.label) { cell in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        MonoLabel(cell.label, size: 10, color: V8.mute).fixedSize()
                        Spacer(minLength: 8)
                        Text(cell.value).font(V8Font.mono(13, weight: .semibold)).foregroundStyle(V8.ink).multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        MonoLabel(cell.label, size: 10, color: V8.mute)
                        Text(cell.value).font(V8Font.mono(13, weight: .semibold)).foregroundStyle(V8.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .overlay(alignment: .bottom) { IndexRule() }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "Sua nota": linha de papel, toque edita.
    private func notaBlock(_ place: Place) -> some View {
        Button { router.sheet = .editPlace(id: place.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("sua nota", size: 10, color: V8.mute)
                Text(place.notes.isEmpty ? "Sem nota ainda. Toque pra escrever." : place.notes)
                    .font(V8Font.text(15)).foregroundStyle(place.notes.isEmpty ? V8.mute : V8.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("editar a nota")
    }

    @State private var scrollToTips = false

    // MARK: Seções (painel do tipo, dicas, amigos, filmes)

    /// Painéis (tipo, dicas, amigos, filmes) em faixa de papel com régua embaixo.
    private func legacyCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.paper)
            .overlay(alignment: .bottom) { IndexRule() }
            .environment(\.colorScheme, .light)
    }

    private func linkRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CutRow(title: title) { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(V8.ink) }
        }
        .buttonStyle(.plain)
    }

    private func lowerSection(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            emCartazBlock(place, onInk: false)
            if let panel = kindPanel(place) { legacyCard { panel }.id("panel") }
            if PocketRules.cashOnly(notes: place.notes) || region.profile.money?.cashCommon == true {
                linkRow(region.profile.money?.atmFilter ?? "Caixa perto", systemImage: "yensign.circle") { router.push(.bolso) }
            }
            linkRow("Trocar por outro no dia", systemImage: "arrow.up.arrow.down") { router.push(.montar(date: region.calendar.startOfDay(for: now))) }
            // Só busca as dicas quando a seção aparece (Google cobra SKU Atmosphere).
            legacyCard { TipsSection(model: tips, region: region) }
                .id("tips")
                .onScrollVisibilityChange(threshold: 0.01) { visible in if visible { tipsVisible = true } }
            // Amigos que foram (mock "exemplo" por enquanto) e filmes gravados aqui: somem sem dado.
            let visits = FriendsProvider.visits(friends, placeId: place.id)
            if !visits.isEmpty {
                legacyCard { FriendsSection(visits: visits, isSample: friends.isSample) }
            }
            legacyCard { FilmsSection(place: place, region: region, areaName: place.area) }
            // Grupo: este lugar contra outro, pro grupo votar.
            linkRow("A ou B? Mandar pro grupo", systemImage: "person.2") { router.sheet = .aOuB(placeId: place.id) }
        }
    }


    /// Páginas da galeria que já têm foto (as outras ainda não vieram: não abrem vazias no visualizador).
    /// Todas as fotos do lugar: as que já vieram abrem na hora; as outras baixam só quando a pessoa desliza até elas.
    private func viewerPages(_ place: Place) -> [PhotoViewer.Page] {
        (0..<pages(place)).map { i in
            let photo = i > 0 ? galleryPhotos[i] : heroPhoto
            if let url = photoURL(place, page: i) { return PhotoViewer.Page(id: i, url: url, credit: photo?.credit ?? "foto · Google") }
            return PhotoViewer.Page.google(id: i, placeId: place.placeId, refs: place.photoRefs, resolver: services.photoResolver)
        }
    }

    /// Voltar, galeria e "…"; embaixo, a ficha técnica do canto e o crédito da foto (sempre visível).

    private func moreMenu(_ place: Place) -> some View {
        Menu {
            Button("Editar", systemImage: "pencil") { router.sheet = .editPlace(id: place.id) }
            Button(place.saveForEnd ? "Tirar de fica pro fim" : "Fica pro fim", systemImage: "bookmark") {
                place.saveForEnd.toggle()
                try? context.save()
            }
            if place.kind == .photo {
                Button("Luz de hoje", systemImage: "sun.max") { router.push(.light(date: region.calendar.startOfDay(for: now))) }
            }
            if place.kind == .experience {
                Button("Anexar ingresso", systemImage: "ticket") { editingTickets = true }
                if let info = place.extra?.experience, let url = info.url {
                    Button("Abrir \(info.supplier.label)", systemImage: "arrow.up.right") { UIApplication.shared.open(url) }
                }
            }
            Button(addedAt == nil ? "Pôr no dia" : "Já está no dia", systemImage: "calendar.badge.plus") {
                let at = DayInsert.suggestedTime(now: now, region: region, place: place)
                DayInsert.add(place, at: at, region: region, context: context)
                addedAt = at
            }
            .disabled(addedAt != nil)
            Button("Ver em 3D", systemImage: "view.3d") { show3D = true }.disabled(services.connectivity.isOffline)
            Divider()
            Button("Apple Maps · transporte") { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) }
            Button("Google Maps") { MapsLinks.openGoogle(to: place.coordinate, mode: .transit) }
            if place.isDone {
                Button("Desfazer feito", systemImage: "arrow.uturn.backward") { PlaceActions.undoDone(place, context: context) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.white).frame(width: 44, height: 44).overlay(Rectangle().stroke(V8.white, lineWidth: 2)).contentShape(Rectangle())
        }
        .accessibilityLabel("Mais")
    }

    private var weather: DayWeather? { services.sync.weather(on: now, region: region, trip: trips.first) }

    private func kindPanel(_ place: Place) -> AnyView? {
        let extra = place.extra
        switch place.kind {
        case .photo:
            return AnyView(PhotoPanel(place: place, spot: extra?.photo ?? PhotoSpot(), region: region, now: now, weather: weather,
                                      fetchedAt: services.sync.weatherFetchedAt(on: now, region: region, trip: trips.first)))
        case .art:
            guard let art = extra?.art, !art.sessions.isEmpty || art.runsUntil != nil else { return nil }
            return AnyView(ArtPanel(place: place, art: art, region: region, now: now) { toggleBought($0, place) })
        case .sport:
            guard let spot = extra?.sport else { return nil }
            return AnyView(SportPanel(place: place, spot: spot, region: region, now: now, weather: weather) { toggleBought($0, place) })
        case .experience:
            guard let info = extra?.experience else { return nil }
            return AnyView(ExperiencePanel(place: place, info: info, tickets: place.tickets, region: region, now: now,
                                           onToggleBought: { toggleBought($0, place) },
                                           onOpenTicket: { router.push(.ticket(placeId: place.id, ticketId: $0.id), on: router.tab) }))
        case .place:
            return nil
        }
    }

    private func toggleBought(_ session: EventSession, _ place: Place) {
        var extra = place.extra ?? PlaceExtra()
        if let i = extra.art?.sessions.firstIndex(where: { $0.id == session.id }) { extra.art?.sessions[i].bought.toggle() }
        if let i = extra.sport?.sessions.firstIndex(where: { $0.id == session.id }) { extra.sport?.sessions[i].bought.toggle() }
        if let i = extra.experience?.sessions.firstIndex(where: { $0.id == session.id }) { extra.experience?.sessions[i].bought.toggle() }
        place.extra = extra
        try? context.save()
    }

    // MARK: Rede (só o Lugar aberto)

    private func loadTips(_ place: Place) async {
        // Sem `placeId` o Google não devolve avaliação: espera a resolução (a mesma busca da foto, se já estiver em voo).
        await services.sync.ensureResolved(place, region: region, cityName: trips.first?.city(id: place.cityId)?.name)
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

    /// Foto principal (prompt 19): Google primeiro (disco, depois uma `/media`), Commons só de reserva.
    private func loadHero(_ place: Place) async {
        guard heroPhoto == nil, !noPhotos else { return }
        let city = trips.first?.city(id: place.cityId)?.name ?? region.displayName
        do {
            let photo = try await services.photoResolver.hero(for: place, cityName: city,
                                                              commonsAllowed: settingsList.first?.flickrPhotos ?? true)
            withAnimation(.easeOut(duration: 0.25)) { heroPhoto = photo }
        } catch {
            Log.network.error("hero \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadGalleryPage(_ place: Place, index: Int) async {
        guard index > 0, galleryPhotos[index] == nil else { return }
        do {
            galleryPhotos[index] = try await services.photoResolver.gallery(for: place, index: index)
        } catch {
            Log.network.error("galeria \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Abertura do visualizador de foto (página da galeria).
private struct ViewerStart: Identifiable, Hashable {
    var page: Int
    var id: Int { page }
}
