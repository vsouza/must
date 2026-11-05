import CoreLocation
import SwiftData
import SwiftUI

/// 09 · Lugar em tela cheia (prompt 23 §2, `LugarFoto.png`, `MuseuFoto.png`; Roma `LugarIT.png`, `MuseuIT.png`; sem foto
/// no disco, `Lugar.png`). Foto grande em cor cheia e, embaixo, a **faixa preta sólida** (`CutBand`) com o nome latino e o
/// nome local "mostre ao atendente" (único lugar com escrita local); ficha 3×2, "Sua nota", pílulas, Ir agora / Feito.
/// Museu e reserva: o bilhete da âncora por cima da foto, "chegar" e "saia de". O v8 substitui as fotos vivas: nada de
/// cor do Must atrás do texto, sem degradê, sem zoom. Foto: uma por lugar, do disco; sem nada no disco, uma `/media` só
/// pro Lugar aberto (o resolvedor decide). `-debugNoPhotos` força o layout sem foto.
struct PlaceView: View {
    let placeId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Query private var matches: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var heroPhoto: CCPhoto?
    /// Galeria do Google (páginas 1…4; a 0 é `heroPhoto`), carregada ao deslizar (prompt 19).
    @State private var galleryPhotos: [Int: CCPhoto] = [:]
    @State private var galleryPage = 0
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
                Text("Esse lugar saiu do board.").font(V8Font.text(16)).foregroundStyle(V8.ink)
                V8Button("Voltar", .line) { dismiss() }.frame(width: 180)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V8.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Estado derivado

    /// Parada do lugar no dia de hoje (motor do dia): número e se é a de agora.
    private func stopInfo(_ place: Place) -> (number: Int, total: Int, isNow: Bool, at: Date)? {
        guard let plan = dayEngine.plan(for: region.calendar.startOfDay(for: now), region: region, context: context),
              let index = plan.stops.firstIndex(where: { $0.placeId == place.id }) else { return nil }
        let current = dayEngine.now(in: plan, at: now)?.current.placeId == place.id
        return (index + 1, plan.stops.count, current, plan.stops[index].start)
    }

    private func photoURL(_ place: Place, page: Int = 0) -> URL? {
        if noPhotos { return nil }
        if page > 0, let photo = galleryPhotos[page] { return URL(string: photo.url) }
        if page == 0, let heroPhoto { return URL(string: heroPhoto.largeURL ?? heroPhoto.url) }
        return page == 0 ? services.photoResolver.cachedHeroURL(refs: place.photoRefs) : nil
    }

    private func pages(_ place: Place) -> Int { place.placeId == nil ? 1 : max(1, min(place.photoRefs.count, 5)) }

    // MARK: Tela

    private func content(_ place: Place) -> some View {
        let hasPhoto = photoURL(place) != nil
        let anchor = PlaceFicha.anchor(place, now: now, calendar: region.calendar)
        let stop = stopInfo(place)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if hasPhoto {
                        photoBlock(place, anchor: anchor, stop: stop)
                        band(place, anchor: anchor, stop: stop)
                        inkExtras(place).background(V8.ink)
                    } else {
                        plainTop(place, anchor: anchor, stop: stop)
                        paperBody(place, anchor: anchor)
                    }
                    lowerSection(place).id("panel")
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background((hasPhoto ? V8.ink : V8.paper).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { actions(place, anchor: anchor, onInk: hasPhoto) }
            #if DEBUG
            .task {
                let screen = DebugFlags.string("debugScreen") ?? ""
                if screen.hasPrefix("museu") { ProximosDemo.ensureTeamLab(context: context, dates: BoardDates(timeZone: region.timeZone)) }
                if screen.hasPrefix("3d") { show3D = true; return }
                if screen.hasPrefix("painel") || screen.hasPrefix("dicas") {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation { proxy.scrollTo(screen.hasPrefix("dicas") ? "tips" : "panel", anchor: .top) }
                }
            }
            #endif
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { services.sync.refreshIfStale(place, region: region) }
        .task(id: place.id) { await loadHero(place) }
        .task(id: "\(place.id)|\(tipsVisible)") { if tipsVisible { await loadTips(place) } }
        .fullScreenCover(isPresented: $show3D) {
            Place3DView(name: place.name, coordinate: place.coordinate, heading: place.extra?.photo?.facing)
        }
        .sheet(isPresented: $editingTickets) {
            TicketsEditor(tickets: Binding(get: { place.tickets }, set: { place.tickets = $0; place.syncBoughtSessions(); try? context.save() }),
                          sessions: place.extra?.sessions ?? [], region: region, placeName: place.name)
        }
    }

    // MARK: Foto

    private func photoBlock(_ place: Place, anchor: PlaceFicha.Anchor?, stop: (number: Int, total: Int, isNow: Bool, at: Date)?) -> some View {
        heroBackground(place)
            .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                Rings(color: V8.white, count: 1, diameter: 560, opacity: 0.5, offset: CGSize(width: 200, height: -230))
                    .clipped()
            }
            .overlay(alignment: .top) { topBar(place, onPhoto: true).padding(.top, 58) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    if let anchor { anchorTicket(anchor, place: place).padding(.bottom, 26) }
                    tags(place, anchor: anchor, stop: stop, photo: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
    }

    @ViewBuilder private func heroBackground(_ place: Place) -> some View {
        let count = pages(place)
        if count > 1 {
            TabView(selection: $galleryPage) {
                ForEach(0..<count, id: \.self) { index in
                    V8Photo(url: photoURL(place, page: index)).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Só a página que está na tela (nada de vizinha pré-carregada): uma `/media` por deslize.
            .task(id: galleryPage) { await loadGalleryPage(place, index: galleryPage) }
        } else {
            V8Photo(url: photoURL(place))
        }
    }

    /// Voltar, galeria e "…"; embaixo, a ficha técnica do canto e o crédito da foto (sempre visível).
    private func topBar(_ place: Place, onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                V8CornerButton(systemName: "chevron.left", label: "Voltar", onInk: !onPhoto, onPhoto: onPhoto) { dismiss() }
                Spacer()
                if onPhoto && pages(place) > 1 {
                    V8CornerButton(systemName: "photo", label: "Próxima foto", onPhoto: true) {
                        withAnimation { galleryPage = (galleryPage + 1) % pages(place) }
                    }
                } else if !onPhoto {
                    V8CornerButton(systemName: place.saveForEnd ? "bookmark.fill" : "bookmark",
                                   label: place.saveForEnd ? "Tirar de fica pro fim" : "Fica pro fim", onInk: true) {
                        place.saveForEnd.toggle()
                        try? context.save()
                    }
                }
                moreMenu(place, onPhoto: onPhoto)
            }
            HStack(alignment: .top) {
                if onPhoto { V8SpecStack(lines: PlaceFicha.specLines(place), color: V8.white) }
                Spacer(minLength: 10)
                if onPhoto {
                    creditPill(place)
                } else {
                    V8SpecStack(lines: [services.connectivity.isOffline ? "sem foto · offline" : "sem foto no aparelho",
                                        PlaceFicha.specLines(place).first ?? ""],
                                color: V8.muteDark, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private func creditPill(_ place: Place) -> some View {
        let photo = galleryPage > 0 ? galleryPhotos[galleryPage] : heroPhoto
        let source = photo?.source ?? (photo == nil ? "Google" : "Wikimedia Commons")
        let text = "\(galleryPage + 1) / \(pages(place)) · \(source)"
        Button {
            if let url = photo?.pageURL { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                SpecLabel(text, color: V8.white)
                if let owner = photo?.owner, !owner.isEmpty {
                    SpecLabel("@\(owner)\(photo?.licenseName.isEmpty == false ? " · \(photo!.licenseName)" : "")", color: V8.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(V8.ink.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo?.credit ?? "foto")
    }

    private func moreMenu(_ place: Place, onPhoto: Bool) -> some View {
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
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(V8.white)
                .frame(width: 44, height: 44)
                .background { if onPhoto { Circle().fill(V8.ink.opacity(0.28)) } }
                .overlay(Circle().strokeBorder(V8.white.opacity(0.85), lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel("Mais")
    }

    /// Etiquetas acima do nome: parada (laranja quando é agora) ou âncora, e fila / horário / duração.
    private func tags(_ place: Place, anchor: PlaceFicha.Anchor?, stop: (number: Int, total: Int, isNow: Bool, at: Date)?, photo: Bool) -> some View {
        HStack(spacing: 8) {
            if let anchor {
                V8Tag(text: "\(Proximos.dayLabel(anchor.at, now: now, calendar: region.calendar)) · âncora", style: .glass)
                if let minutes = anchor.minutes { V8Tag(text: PlaceFicha.durationText(minutes), style: .glass) }
            } else {
                if let stop {
                    if stop.isNow {
                        V8Tag(text: photo ? "agora · parada \(stop.number)" : "agora · \(stop.number) de \(stop.total)", style: .orange)
                    } else {
                        V8Tag(text: "parada \(stop.number) · \(region.timeString(stop.at))", style: .ink)
                    }
                } else if place.isDone, let done = place.done {
                    V8Tag(text: "feito · \(region.shortDay(done.at))", style: .ink)
                }
                if let second = photo ? (PlaceFicha.queueTag(place, region: region) ?? PlaceFicha.openTag(place, region: region, now: now))
                    : (PlaceFicha.openTag(place, region: region, now: now) ?? PlaceFicha.queueTag(place, region: region)) {
                    V8Tag(text: second, style: .glass)
                }
            }
        }
    }

    /// O bilhete da âncora: hora grande, "Reserva · seg 12 · 2 pessoas", nota e o QR (abre o ingresso).
    private func anchorTicket(_ anchor: PlaceFicha.Anchor, place: Place) -> some View {
        Button {
            if let id = anchor.ticketId { router.push(.ticket(placeId: place.id, ticketId: id)) }
        } label: {
            HStack(spacing: 14) {
                Text(region.timeString(anchor.at))
                    .font(V8Font.mono(30).weight(.bold))
                    .foregroundStyle(V8.ink)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    let people = anchor.people.map { " · \($0) \($0 == 1 ? "pessoa" : "pessoas")" } ?? ""
                    Text("\(anchor.kind == .ticket ? "Ingresso" : "Reserva") · \(Proximos.dayLabel(anchor.at, now: now, calendar: region.calendar))\(people)")
                        .font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                    Text(anchorNote(anchor)).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
                }
                Spacer(minLength: 4)
                if anchor.hasQR || anchor.kind == .reservation {
                    Text(anchor.hasQR ? "QR" : "RES")
                        .font(V8Font.mono(11).weight(.bold))
                        .foregroundStyle(V8.white)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(V8.ink))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Capsule().fill(V8.paper))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func anchorNote(_ anchor: PlaceFicha.Anchor) -> String {
        var parts: [String] = []
        if let minutes = anchor.minutes, anchor.kind == .reservation { parts.append("turno de \(PlaceFicha.durationText(minutes)), sem exceção") }
        else if let minutes = anchor.minutes {
            parts.append("entrada \(region.timeString(anchor.at))–\(region.timeString(anchor.at.addingTimeInterval(30 * 60)))")
            _ = minutes
        }
        if anchor.hasQR { parts.append("QR salvo offline") } else if let note = anchor.note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    // MARK: Faixa preta

    private func band(_ place: Place, anchor: PlaceFicha.Anchor?, stop: (number: Int, total: Int, isNow: Bool, at: Date)?) -> some View {
        let numeral = numeral(place, anchor: anchor, stop: stop)
        return CutBand {
            VStack(alignment: .leading, spacing: 0) {
                Text(place.name)
                    .font(V8Font.display(50))
                    .tracking(-1.6)
                    .foregroundStyle(V8.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, numeral == nil ? 0 : 92)
                    .accessibilityAddTraits(.isHeader)
                let local = PlaceFicha.localLine(place)
                if !local.isEmpty {
                    Text(local).font(V8Font.text(15)).foregroundStyle(V8.muteDark).lineLimit(1).padding(.top, 26)
                }
                ficha(anchor != nil ? anchorCells(place, anchor: anchor!) : PlaceFicha.cells(place, region: region, now: now, here: here,
                                                                                             walkMaxKm: walkMax, queueFirst: false),
                      onInk: true)
                    .padding(.top, 22)
            }
        }
        .padding(.top, -4)
        .overlay(alignment: .topTrailing) {
            if let numeral {
                BigNumeral(numeral, size: 150, color: V8.orange)
                    .frame(width: 120, alignment: .trailing)
                    .offset(x: 22, y: -42)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Numeral do Lugar: o número da parada no dia; numa âncora fora de hoje, o dia da viagem.
    private func numeral(_ place: Place, anchor: PlaceFicha.Anchor?, stop: (number: Int, total: Int, isNow: Bool, at: Date)?) -> String? {
        if let stop { return "\(stop.number)" }
        if let anchor, let start = trips.first?.start {
            let days = region.calendar.dateComponents([.day], from: region.calendar.startOfDay(for: start),
                                                      to: region.calendar.startOfDay(for: anchor.at)).day ?? -1
            if days >= 0 { return "\(days + 1)" }
        }
        return nil
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
            let mode = leg.mode == .walk ? "a pé" : (region == .it ? "bus/metrô" : "metrô")
            cells.append(.init(label: "saia de \(origin.name)", value: "\(region.timeString(leave)) · \(mode)"))
        }
        if let price = place.price, price > 0 {
            cells.append(.init(label: "ingresso", value: region.money(price)))
        }
        return cells
    }

    private func ficha(_ cells: [PlaceFicha.Cell], onInk: Bool) -> some View {
        let rows = stride(from: 0, to: cells.count, by: 3).map { Array(cells[$0..<min($0 + 3, cells.count)]) }
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.label) { cell in
                        VStack(alignment: .leading, spacing: 4) {
                            SpecLabel(cell.label, color: onInk ? V8.muteDark : V8.mute)
                            Text(cell.value)
                                .font(V8Font.text(17, weight: .semibold))
                                .foregroundStyle(onInk ? V8.white : V8.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(row.count..<3, id: \.self) { _ in Color.clear.frame(height: 1) }
                }
            }
        }
    }

    // MARK: Nota, pílulas

    private func inkExtras(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            noteCard(place)
            pills(place, onInk: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 26)
    }

    private func noteCard(_ place: Place) -> some View {
        Button { router.sheet = .editPlace(id: place.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                SpecLabel("Sua nota", color: V8.ink)
                Text(place.notes.isEmpty ? "Sem nota ainda — toque pra escrever." : place.notes)
                    .font(V8Font.text(18, weight: .semibold))
                    .foregroundStyle(V8.ink.opacity(place.notes.isEmpty ? 0.6 : 1))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(V8.orange))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityHint("editar a nota")
    }

    private func pills(_ place: Place, onInk: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { tipsVisible = true; scrollToTips = true } label: { V8FilterChip(title: tipsLabel, on: false, onInk: onInk) }
                if PocketRules.cashOnly(notes: place.notes) || region == .jp {
                    Button { router.push(.bolso) } label: {
                        V8FilterChip(title: region == .jp ? "Caixa · 7 Bank" : "Caixa perto", on: false, onInk: onInk)
                    }
                }
                Button { router.push(.montar(date: region.calendar.startOfDay(for: now))) } label: {
                    V8FilterChip(title: "Trocar", on: false, onInk: onInk)
                }
            }
            .buttonStyle(MustPressStyle())
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .scrollClipDisabled()
    }

    @State private var scrollToTips = false

    private var tipsLabel: String {
        tips.tips.isEmpty ? "Dicas de quem foi" : "\(tips.tips.count) dicas de quem foi"
    }

    // MARK: Sem foto (`Lugar.png`)

    private func plainTop(_ place: Place, anchor: PlaceFicha.Anchor?, stop: (number: Int, total: Int, isNow: Bool, at: Date)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar(place, onPhoto: false).padding(.top, 58)
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 10) {
                tags(place, anchor: anchor, stop: stop, photo: false)
                Text(place.name)
                    .font(V8Font.display(50))
                    .tracking(-1.6)
                    .foregroundStyle(V8.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                let local = PlaceFicha.localLine(place)
                if !local.isEmpty {
                    Text(local).font(V8Font.text(15)).foregroundStyle(V8.white.opacity(0.85)).lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .containerRelativeFrame(.vertical) { height, _ in height * 0.47 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Cor sólida no tamanho do bloco; os arcos ficam por cima e são cortados nele (não crescem o fundo).
            V8.graphite
                .overlay { Rings(color: V8.white, count: 2, diameter: 520, opacity: 0.22, offset: CGSize(width: 160, height: -120)) }
                .clipped()
        }
    }

    private func paperBody(_ place: Place, anchor: PlaceFicha.Anchor?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let anchor {
                anchorTicket(anchor, place: place).padding(.bottom, 20)
                ficha(anchorCells(place, anchor: anchor), onInk: false)
            } else {
                ficha(PlaceFicha.cells(place, region: region, now: now, here: here, walkMaxKm: walkMax, queueFirst: true), onInk: false)
            }
            noteCard(place).padding(.top, 34)
            pills(place, onInk: false).padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    // MARK: Depois da dobra (papel): painel do tipo e dicas de quem foi

    private func lowerSection(_ place: Place) -> some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if let panel = kindPanel(place) { panel.padding(.top, 8) }
                // Só busca as dicas quando a seção aparece (Google cobra SKU Atmosphere).
                TipsSection(model: tips, region: region)
                    .padding(.top, 28)
                    .id("tips")
                    .onScrollVisibilityChange(threshold: 0.01) { visible in if visible { tipsVisible = true } }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.paper)
            .onChange(of: scrollToTips) { _, go in
                guard go else { return }
                withAnimation { proxy.scrollTo("tips", anchor: .top) }
                scrollToTips = false
            }
        }
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

    // MARK: Ações

    private func actions(_ place: Place, anchor: PlaceFicha.Anchor?, onInk: Bool) -> some View {
        let minutes = here.map { PlaceFicha.travelMinutes(place, from: $0, walkMaxKm: walkMax) }
        return HStack(spacing: 12) {
            if anchor != nil {
                Button { tipsVisible = true; scrollToTips = true } label: {
                    Text(tipsLabel)
                        .font(V8Font.text(16, weight: .semibold))
                        .foregroundStyle(onInk ? V8.white : V8.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .overlay(Capsule().strokeBorder(onInk ? V8.white : V8.ink, lineWidth: 1.2))
                        .contentShape(Capsule())
                }
                .buttonStyle(MustPressStyle())
                V8Button("Como chegar", .orange, icon: .rota) { router.push(.ir(placeId: place.id)) }
            } else {
                V8Button(minutes.map { "Ir agora · \($0) min" } ?? "Ir agora", .orange, icon: .rota) { router.push(.ir(placeId: place.id)) }
                    .layoutPriority(1)
                    .contextMenu {
                        Button("Apple Maps · a pé") { MapsLinks.openApple(to: place.coordinate, name: place.name) }
                        Button("Apple Maps · transporte") { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) }
                        Button("Google Maps") { MapsLinks.openGoogle(to: place.coordinate, mode: .transit) }
                    }
                doneButton(place, onInk: onInk).frame(width: 128)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        // A barra v8 do RootView fica por cima de tudo: os botões sobem acima dela.
        .padding(.bottom, 24) // Lugar em tela cheia: sem barra de abas (`AppRouter.hidesNavBar`)
        .background {
            // O conteúdo que rola some num fade antes dos botões (nada de corte seco no meio de um card).
            let bg = onInk ? V8.ink : V8.paper
            VStack(spacing: 0) {
                LinearGradient(colors: [bg.opacity(0), bg], startPoint: .top, endPoint: .bottom).frame(height: 36)
                bg
            }
            .padding(.top, -36)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func doneButton(_ place: Place, onInk: Bool) -> some View {
        if place.isDone {
            V8Button("Desfazer", .line) { PlaceActions.undoDone(place, context: context) }
        } else {
            // Sobre tinta: contorno branco; sobre papel: tinta cheia (Lugar.png).
            Button { router.sheet = .expense(placeId: place.id) } label: {
                HStack(spacing: 8) {
                    Text("Feito").font(V8Font.text(16, weight: .semibold))
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(onInk ? V8.white : V8.paper)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(onInk ? Color.clear : V8.ink))
                .overlay(Capsule().strokeBorder(onInk ? V8.white : Color.clear, lineWidth: 1.2))
                .contentShape(Capsule())
            }
            .buttonStyle(MustPressStyle())
        }
    }

    // MARK: Rede (só o Lugar aberto)

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
