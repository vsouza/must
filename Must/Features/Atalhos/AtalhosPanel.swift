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

/// Topo do Bolso v9 (antes o painel de Atalhos, prompt 25 · D): grade 2×2 (Suica/Carteira, ingressos de hoje, mapa offline,
/// SOS) e as linhas de trem perto. Tudo do aparelho, montado na hora. Os "indicados fora do board" saíram daqui (vão pro
/// Explorar e pra faixa de fora do Quero…).
struct AtalhosPanel: View {
    var onAction: (AtalhosAction) -> Void

    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query(sort: \WalletItem.order) private var wallet: [WalletItem]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            grid
            linesSection.padding(.top, 26)
        }
    }

    private func close(_ action: AtalhosAction?) { if let action { onAction(action) } }

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
        let next = plan.flatMap { engine.now(in: $0, at: now) }
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
                Rectangle().strokeBorder(card.tone == .alert ? V8.orange : V8.ink, lineWidth: 2)
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
                .background(Circle().fill(Color(hex: line.rgb == 0 ? V8.Hex.ink : line.rgb)))
            Text(line.name).font(V8Font.text(12, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .frame(minHeight: 26)
        .background(Rectangle().fill(V8.paper))
        .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("linha \(line.name)")
    }
}
