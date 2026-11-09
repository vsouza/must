import CoreLocation
import SwiftData
import SwiftUI

/// Dicas v9: a primeira página do Assistente ("O que eu sei de hoje", `Assistente-1.png`). Filtros quadrados (Agora ·
/// bairro · país · Salvas), numeral laranja = dicas de agora e linhas de índice. Lê o dia do motor, as notas do board, as
/// regras do país e só o cache das Dicas de quem foi: nenhuma chamada de rede. Não rola sozinha (o Assistente rola).
struct DicasPage: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Environment(\.friends) private var friends
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    /// Fecha o Assistente antes de abrir um Lugar (a tela de dicas mora numa sheet).
    var onOpenPlace: (String) -> Void = { _ in }

    @State private var filter: DayTips.Filter = .now
    @State private var peopleTips: [String: String] = [:]
    @AppStorage("v8.dicas.saved") private var savedRaw = ""

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var saved: Set<String> { Set(savedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let context = dayContext()
        let cards = DayTips.build(now: now, region: region, current: context.current, next: context.next, night: context.night,
                                  lastTrain: context.lastTrain, country: PocketRules.country(region), saved: saved,
                                  time: region.timeString)
        let today = DayTips.filtered(cards, by: .now)
        let shown = DayTips.filtered(cards, by: filter)
        List {
            Section {
                filters(areaName: context.areaName)
                    .listRowInsets(EdgeInsets(top: 8, leading: V9.gutter, bottom: 8, trailing: V9.gutter))
                    .listRowBackground(Color.clear)
            } header: {
                Text("\(today.count) \(today.count == 1 ? "dica" : "dicas") pra agora")
                    .textCase(nil).font(.subheadline)
            }
            Section {
                ForEach(shown) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Button { if let id = card.placeId { onOpenPlace(id) } } label: { DayTipRow(card: card) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(saved.contains(card.id) ? "Tirar das salvas" : "Salvar dica",
                                       systemImage: saved.contains(card.id) ? "bookmark.slash" : "bookmark") { toggleSaved(card.id) }
                            }
                            .accessibilityAction(named: saved.contains(card.id) ? "Tirar das salvas" : "Salvar dica") { toggleSaved(card.id) }
                        // Amigos que foram a esse lugar (mock "exemplo" por enquanto): uma linha, some sem visita.
                        if let id = card.placeId, let line = FriendsLine.summary(friends.visits(placeId: id)) {
                            HStack(spacing: 6) {
                                Text(line).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                if friends.isSample { Text("exemplo").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(saved.contains(card.id) ? "Tirar" : "Salvar", systemImage: "bookmark") { toggleSaved(card.id) }
                            .tint(V9.accent)
                    }
                }
                if shown.isEmpty {
                    Text(filter == .saved ? "Salve uma dica pelo menu de contexto (toque e segure) ou deslizando a linha." : "Nada aqui por enquanto.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Do seu board, \(PocketRules.country(region).name) e do dia. Funciona sem rede.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .task { await loadPeopleTips(context) }
    }

    private func filters(areaName: String?) -> some View {
        Picker("Filtro", selection: $filter) {
            Text("Agora").tag(DayTips.Filter.now)
            Text(areaName ?? "Bairro").tag(DayTips.Filter.area)
            Text(PocketRules.country(region).name).tag(DayTips.Filter.country)
            Text("Salvas").tag(DayTips.Filter.saved)
        }
        .pickerStyle(.segmented)
    }

    private func toggleSaved(_ id: String) {
        var set = saved
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        savedRaw = set.sorted().joined(separator: ",")
    }

    // MARK: Dia

    private struct Context {
        var current: DayTips.Stop?
        var next: DayTips.Stop?
        var night: DayTips.Stop?
        var lastTrain: (line: String, time: String)?
        var areaName: String?
    }

    private func dayContext() -> Context {
        let areas = AreaCatalog.areas(for: region)
        let plan = dayEngine.plan(for: region.calendar.startOfDay(for: now), region: region, context: context)
        let area = plan?.area.flatMap { id in areas.first { $0.id == id } }
            ?? services.location.current.flatMap { CurrentAreaService.curated($0, in: areas) }
        var result = Context(areaName: area?.name)
        if let plan {
            let current = dayEngine.now(in: plan, at: now)
            result.current = current.map { tipStop($0.current, areaId: area?.id) }
            result.next = current?.next.map { tipStop($0, areaId: area?.id) }
            let after = current?.next?.start ?? now
            if let night = plan.stops.first(where: { $0.start > after && $0.kind != .micro && region.calendar.component(.hour, from: $0.start) >= 19 }) {
                result.night = tipStop(night, areaId: area?.id)
            }
            if let last = plan.lastTrain { result.lastTrain = (last.line, region.timeString(last.at)) }
        }
        if result.lastTrain == nil {
            if region.profile.has(.cityLastMetro) {
                result.lastTrain = ("metrô", PocketRules.lastMetro(at: now, region: region))
            } else if let last = LastTrains.home(region: region, near: services.location.current?.coordinate, transit: TransitLoader.load(region)) {
                result.lastTrain = (last.label.replacingOccurrences(of: "Último ", with: ""), last.time)
            }
        }
        return result
    }

    private func tipStop(_ stop: DayStop, areaId: String?) -> DayTips.Stop {
        let place = stop.placeId.flatMap { id in places.first { $0.id == id } }
        var golden: Date?
        if place?.kind == .photo, let place {
            golden = SunService.day(stop.start, place.coordinate, timeZone: region.timeZone).goldenPM?.start
        }
        return DayTips.Stop(id: stop.id, placeId: place?.id, name: place?.name ?? stop.label, kind: place?.kind ?? .place, sub: place?.sub,
                            notes: [place?.notes, place == nil ? stop.note : nil].compactMap { $0 }.joined(separator: ". "),
                            queueMinutes: place?.queueMinutes, at: stop.start,
                            closesAt: place?.hours?.closesAt(stop.start, timeZone: region.timeZone), golden: golden,
                            inArea: stop.area == nil || stop.area == areaId, peopleTip: place.flatMap { peopleTips[$0.id] })
    }

    /// Só o cache das Dicas de quem foi (até 30 dias), nunca a rede.
    private func loadPeopleTips(_ context: Context) async {
        let ids = [context.current?.placeId, context.next?.placeId, context.night?.placeId].compactMap { $0 }
        var found: [String: String] = [:]
        for id in ids {
            guard let place = places.first(where: { $0.id == id }) else { continue }
            let query = TipsQuery(id: place.id, name: place.name, nameLocal: place.nameLocal,
                                  city: trips.first?.city(id: place.cityId)?.name ?? region.displayName, region: region,
                                  lat: place.lat, lng: place.lng, googlePlaceId: place.placeId, fsqId: place.fsqId)
            for source in [TipSource.google, .foursquare, .reddit] {
                if let tip = await TipsCache.shared.batch(query, source, allowStale: true)?.tips.first {
                    found[id] = tip.translation ?? tip.text
                    break
                }
            }
        }
        if found != peopleTips { peopleTips = found }
    }
}

/// Uma dica como linha da lista: rótulo (tipo/hora) em cima, título e detalhe. "Agora e é seu" ganha o acento; o
/// resto fica em texto do sistema.
struct DayTipRow: View {
    var card: DayTips.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(card.tone == .orange ? V9.accent : .secondary)
                .lineLimit(2)
            Text(card.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if !card.detail.isEmpty {
                Text(card.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        [card.corner, card.tag].filter { !$0.isEmpty }.map { $0.capitalized }.joined(separator: " · ")
    }
}
