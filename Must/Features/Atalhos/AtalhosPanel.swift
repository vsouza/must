import CoreLocation
import SwiftData
import SwiftUI

/// Para onde um toque nos Atalhos leva. Roda depois que o painel fecha (o painel é uma apresentação própria por cima da
/// capa, e o `router` não abre sheet por cima dela).
enum AtalhosAction: Equatable {
    case route(Route)
    case sheet(AppRouter.Sheet)
    case selectTab(MustTab)
    case url(URL)
}

/// Atalhos (prompt 25 · D, `Atalhos.png`): painel de papel sobre a capa (a capa fica atrás, deslocada: só a faixa da cor do
/// lugar aparece à esquerda). Grade 2×2 (Suica/Carteira, ingressos de hoje, mapa offline, SOS), Linhas perto, Indicados por
/// perto, Bolso, e os botões Quero… e Mandar. Tudo do aparelho, montado na hora: abre sem esperar nada.
struct AtalhosPanel: View {
    var onClose: (AtalhosAction?) -> Void

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine
    @Environment(\.tripTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \WalletItem.order) private var wallet: [WalletItem]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var shown = false
    @State private var picks: [AtalhoPick] = []
    @State private var picksLoaded = false

    private let strip: CGFloat = 60
    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // A capa deslocada: só a cor dela, à esquerda. Toque fecha.
                theme.cover
                    .frame(width: strip + 40)
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .onTapGesture { close(nil) }
                    .accessibilityLabel("Voltar pra capa")
                    .accessibilityAddTraits(.isButton)
                panel
                    .frame(width: geo.size.width - strip)
                    .background {
                        Rectangle()
                            .fill(V8.paper)
                            .overlay(alignment: .leading) { Rectangle().fill(V8.ink).frame(width: 6) }
                            .ignoresSafeArea()
                    }
                    .offset(x: shown ? strip : geo.size.width + 20)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width > 80, abs(value.translation.width) > abs(value.translation.height) { close(nil) }
        })
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) { shown = true }
        }
        .task { await loadPicks() }
        .accessibilityAction(.escape) { close(nil) }
    }

    // MARK: Painel

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    V8SpecStack(lines: ["Atalhos", "deslize a capa pra direita"]).padding(.top, 14)
                    Spacer(minLength: 12)
                    V8CornerButton(systemName: "xmark", label: "Fechar") { close(nil) }
                }
                .padding(.top, 8)
                Text("Na mão")
                    .font(V8Font.display(36))
                    .tracking(-1)
                    .foregroundStyle(V8.ink)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                grid.padding(.top, 18)
                linesSection.padding(.top, 26)
                picksSection.padding(.top, 24)
                bolsoRow.padding(.top, 14)
                HStack(spacing: 10) {
                    BigButton(title: "Quero…", style: .orange) { close(.sheet(.quero(text: nil))) }
                    BigButton(title: "Mandar o dia", style: .line) { close(.sheet(.mandar(date: today))) }
                }
                .padding(.top, 22)
                Color.clear.frame(height: 24)
            }
            .padding(.leading, 22)
            .padding(.trailing, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Grade 2×2

    private var cards: [AtalhoCard] {
        [walletCard, todayCard, mapCard, AtalhosRules.sosCard(region: region)]
    }

    private var grid: some View {
        let columns = AtalhosRules.columns(for: typeSize)
        let rows = stride(from: 0, to: cards.count, by: columns).map { Array(cards[$0..<min($0 + columns, cards.count)]) }
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { card in
                        Button { tap(card) } label: { AtalhoCardView(card: card) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }
        }
    }

    private var transitCard: WalletItem? {
        wallet.first { $0.kind == .transitCard && $0.balance != nil } ?? wallet.first { $0.kind == .transitCard }
    }

    private var walletCard: AtalhoCard {
        let card = transitCard
        let noted = card?.balanceNotedAt.map { WalletRules.balanceNote(noted: $0, now: now, region: region) }
        return AtalhosRules.walletCard(region: region, transitName: card?.name, balance: card?.balance, notedNote: noted,
                                       walletCount: wallet.count)
    }

    /// Reservas e ingressos com hora hoje (do board), em ordem.
    private var todayItems: [(name: String, at: Date, placeId: String, ticketId: String?)] {
        let cal = region.calendar
        var out: [(name: String, at: Date, placeId: String, ticketId: String?)] = []
        for p in places {
            if let r = p.reservation, cal.isDate(r.at, inSameDayAs: now) { out.append((p.name, r.at, p.id, nil)) }
            for t in p.tickets where cal.isDate(t.at, inSameDayAs: now) { out.append((p.name, t.at, p.id, t.id)) }
        }
        return out.sorted { $0.at < $1.at }
    }

    private var todayCard: AtalhoCard {
        AtalhosRules.todayCard(todayItems.map { (short($0.name), region.timeString($0.at)) })
    }

    private var mapPack: MapPack? {
        let here = services.location.current?.coordinate ?? cityCenter
        return MapPack.catalog.first { $0.region == region && $0.contains(here) } ?? MapPack.catalog.first { $0.region == region }
    }

    private var mapCard: AtalhoCard {
        guard let pack = mapPack else { return AtalhosRules.mapCard(title: nil, bytes: nil, installed: false) }
        return AtalhosRules.mapCard(title: pack.title, bytes: services.maps.bytes(pack.id), installed: services.maps.isInstalled(pack.id))
    }

    private func tap(_ card: AtalhoCard) {
        switch card.kind {
        case .wallet:
            if region.profile.transit?.storedValueCard != nil, transitCard?.balance != nil { close(.url(WalletRules.walletURL)) } else { close(.route(.carteira)) }
        case .today:
            let items = todayItems
            if items.count == 1, let first = items.first, let ticket = first.ticketId {
                close(.route(.ticket(placeId: first.placeId, ticketId: ticket)))
            } else if items.isEmpty {
                close(.selectTab(.viagem))
            } else {
                close(.route(.reservations))
            }
        case .map:
            if let pack = mapPack, services.maps.isInstalled(pack.id) { close(.route(.mapa)) } else { close(.route(.offlineMaps)) }
        case .sos:
            close(.route(.sos))
        }
    }

    // MARK: Linhas perto

    private var cityCenter: CLLocationCoordinate2D {
        trips.first?.city(on: now, calendar: region.calendar).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            ?? region.defaultCenter
    }

    private var plan: DayPlan? { engine.plan(for: today, region: region, context: context) }

    private var nearbyLines: AtalhoLines? {
        let here = services.location.current?.coordinate ?? cityCenter
        let transit = TransitLoader.load(region)
        guard var lines = AtalhosRules.lines(near: here, transit: transit, areas: AreaCatalog.areas(for: region), region: region) else {
            return nil
        }
        let last = LastTrains.home(region: region, near: here, transit: transit)
        let next = DayClock.read(engine: engine, region: region, context: context, at: now, position: services.location.current?.coordinate).now
        lines.note = AtalhosRules.note(lastTrain: last, leaveAt: next.map { region.timeString($0.leaveAt) },
                                       next: next?.next.map { short($0.label) })
        return lines
    }

    @ViewBuilder private var linesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lines = nearbyLines {
                SectionHead(title: "Linhas perto", trailing: "\(lines.station) · \(lines.walkMinutes) min")
                FlowLayout(spacing: 6) {
                    ForEach(lines.lines) { line in AtalhoLineChip(line: line) }
                }
                if let note = lines.note {
                    MonoLabel(note, size: 10, color: V8.mute).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SectionHead(title: "Linhas perto", trailing: nil)
                Text(region.profile.transit?.noStationText ?? "Nenhuma estação a pé daqui.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Indicados por perto

    @ViewBuilder private var picksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHead(title: "Indicados por perto", trailing: "fora do board")
            if picks.isEmpty {
                Button { close(.route(.discover)) } label: {
                    Text(picksLoaded ? "Abra Por perto no Wi-Fi e os indicados ficam aqui, mesmo offline." : " ")
                        .font(V8Font.text(14)).foregroundStyle(V8.mute).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in
                Button { close(.route(.discover)) } label: {
                    IndexRow(index: "\(i + 1)", title: pick.name, meta: pick.reason)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bolsoRow: some View {
        Button { close(.route(.bolso)) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bolso").font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                    Text("câmbio, frases, último trem · tudo offline").font(V8Font.text(12)).foregroundStyle(V8.mute).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(V8.ink)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Só o que já está no aparelho: o cache do "Por perto" (fresco ou de até 12 h). Com `-debugNearby fake`, as amostras.
    private func loadPicks() async {
        defer { picksLoaded = true }
        guard let here = services.location.current?.coordinate else { return }
        var batch = await services.nearby.cached(lat: here.latitude, lng: here.longitude, region: region, now: now)
        #if DEBUG
        if batch == nil, DebugFlags.string("debugNearby") == "fake" {
            batch = await services.nearby.load(lat: here.latitude, lng: here.longitude, region: region, now: now)
        }
        #endif
        if batch == nil {
            let (lat, lng, r, t) = (here.latitude, here.longitude, region, now)
            batch = await Task.detached { AtalhosRules.cachedBatch(lat: lat, lng: lng, region: r, now: t) }.value
        }
        guard let batch else { return }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let ranked = DiscoverBuilder.ranked(batch: batch, places: places, origin: origin, now: now, region: region)
        picks = AtalhosRules.picks(ranked)
    }

    // MARK: Fechar

    private func close(_ action: AtalhosAction?) {
        withAnimation(.snappy(duration: 0.18)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(action == nil ? 190 : 120))
            onClose(action)
        }
    }

    private func short(_ label: String) -> String {
        let base = label.components(separatedBy: " · ").first ?? label
        let words = base.split(separator: " ")
        return words.count > 2 ? words.prefix(2).joined(separator: " ") : base
    }
}

/// Card da grade (`.a` do `Atalhos.html`): rótulo mono, título 16/700 em até duas linhas, detalhe de uma linha.
struct AtalhoCardView: View {
    var card: AtalhoCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.label.uppercased())
                .font(V8Font.mono(9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(labelColor)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(card.title)
                .font(V8Font.text(17, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(card.detail)
                .font(V8Font.text(12))
                .foregroundStyle(ink.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .topLeading)
        .background(Rectangle().fill(fill))
        .overlay {
            if card.tone == .white || card.tone == .alert {
                Rectangle()
                    .strokeBorder(card.tone == .alert ? V8.orange : V8.ink.opacity(0.14), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label): \(card.title.replacingOccurrences(of: "\n", with: " ")). \(card.detail)")
    }

    private var fill: Color {
        switch card.tone {
        case .ink: V8.ink
        case .orange: V8.orange
        case .white, .alert: V8.white
        }
    }

    private var ink: Color { card.tone == .ink ? V8.white : V8.ink }

    private var labelColor: Color {
        switch card.tone {
        case .ink: V8.muteDark
        case .alert: V8.orangeDeep
        default: V8.ink.opacity(0.75)
        }
    }
}

/// Chip de linha (`.ln`): círculo na cor oficial com o código, nome latino.
private struct AtalhoLineChip: View {
    var line: AtalhoLine

    var body: some View {
        HStack(spacing: 5) {
            Text(line.code)
                .font(V8Font.mono(8, weight: .bold))
                .foregroundStyle(V8.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 20, height: 20)
                .background(Rectangle().fill(Color(hex: line.rgb == 0 ? V8.Hex.ink : line.rgb)))
            Text(line.name).font(V8Font.text(12, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .frame(minHeight: 26)
        .background(Rectangle().fill(V8.paper))
        .overlay(Rectangle().strokeBorder(V8.ink.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("linha \(line.name)")
    }
}
