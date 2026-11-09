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

    /// Conteúdo pra dentro de uma `List`: a seção dos atalhos e a das linhas perto.
    var body: some View {
        Section("Atalhos") {
            ForEach(cards) { card in
                Button { tap(card) } label: { AtalhoCardView(card: card) }
                    .buttonStyle(.plain)
            }
        }
        linesSection
    }

    private func close(_ action: AtalhosAction?) { if let action { onAction(action) } }

    // MARK: Grade 2×2

    private var cards: [AtalhoCard] {
        [walletCard, todayCard, mapCard, AtalhosRules.sosCard(region: region)]
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
        if let lines = nearbyLines {
            Section {
                FlowLayout(spacing: 8) {
                    ForEach(lines.lines) { line in AtalhoLineChip(line: line) }
                }
                .padding(.vertical, 4)
                if let note = lines.note {
                    Text(note).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Linhas perto · \(lines.station) · \(lines.walkMinutes) min")
            }
        } else {
            Section("Linhas perto") {
                Text(region.profile.transit?.noStationText ?? "Nenhuma estação a pé daqui.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func short(_ label: String) -> String {
        let base = label.components(separatedBy: " · ").first ?? label
        let words = base.split(separator: " ")
        return words.count > 2 ? words.prefix(2).joined(separator: " ") : base
    }
}

/// Linha de atalho: rótulo pequeno, título e detalhe quebrando (nada cortado); chevron à direita. Alerta = vermelho do sistema.
struct AtalhoCardView: View {
    var card: AtalhoCard

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.label).font(.footnote.weight(.semibold)).foregroundStyle(card.tone == .alert ? Color.red : Color.secondary)
                Text(card.title.replacingOccurrences(of: "\n", with: " ")).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label): \(card.title.replacingOccurrences(of: "\n", with: " ")). \(card.detail)")
    }
}

/// Chip de linha: círculo na cor oficial com o código, nome latino.
private struct AtalhoLineChip: View {
    var line: AtalhoLine

    var body: some View {
        HStack(spacing: 6) {
            Text(line.code)
                .font(.caption2.weight(.bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(hex: line.rgb == 0 ? V8.Hex.ink : line.rgb)))
            Text(line.name).font(.footnote.weight(.semibold)).lineLimit(1)
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(V9.fill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("linha \(line.name)")
    }
}
