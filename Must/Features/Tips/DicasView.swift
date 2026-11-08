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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                filters(areaName: context.areaName)
                BigNumeral("\(today.count)", size: 64, color: V8.orange)
                    .fixedSize()
                    .accessibilityLabel("\(today.count) dicas pra agora")
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.vertical, 14)
            Rectangle().fill(V8.ink).frame(height: 2)
            ForEach(shown) { card in
                VStack(alignment: .leading, spacing: 0) {
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
                            Text(line).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(2)
                            if friends.isSample { V8Tag(text: "exemplo", style: .paper) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
            }
            if shown.isEmpty {
                Text(filter == .saved ? "Segure uma dica pra salvar." : "Nada aqui por enquanto.")
                    .font(V8Font.text(15)).foregroundStyle(V8.mute).padding(20)
            }
            MonoLabel("do seu board, \(PocketRules.country(region).name.lowercased()) e do dia · funciona sem rede", size: 9, color: V8.mute)
                .padding(.horizontal, 20)
                .padding(.top, 14)
        }
        .task { await loadPeopleTips(context) }
    }

    private func filters(areaName: String?) -> some View {
        let items: [V8FilterRow.Item] = [
            .init(id: DayTips.Filter.now.rawValue, title: "Agora", on: filter == .now),
            .init(id: DayTips.Filter.area.rawValue, title: areaName ?? "Bairro", on: filter == .area),
            .init(id: DayTips.Filter.country.rawValue, title: PocketRules.country(region).name, on: filter == .country),
            .init(id: DayTips.Filter.saved.rawValue, title: "Salvas", on: filter == .saved),
        ]
        return V8FilterRow(items: items, bleed: false) { id in
            if let f = DayTips.Filter(rawValue: id) { filter = f }
        }
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

/// Uma dica como linha de índice: rótulo mono (hora, valor, tipo) à esquerda, título e detalhe à direita. Laranja = é seu e
/// dá agora; tinta = de fora do board; papel = o resto.
struct DayTipRow: View {
    var card: DayTips.Card
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize > .xLarge
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.corner.uppercased())
                    .font(V8Font.mono(11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(cornerColor)
                    .lineLimit(2)
                Text(card.tag.uppercased())
                    .font(V8Font.mono(9))
                    .tracking(0.9)
                    .foregroundStyle(subColor)
                    .lineLimit(2)
            }
            .frame(width: stacked ? nil : 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(V8Font.text(17, weight: .bold))
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.detail.isEmpty {
                    Text(card.detail)
                        .font(V8Font.text(14))
                        .foregroundStyle(subColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        switch card.tone {
        case .orange: V8.orange
        case .ink: V8.ink
        case .white: V8.paper
        }
    }
    private var titleColor: Color { card.tone == .ink ? V8.white : V8.ink }
    private var subColor: Color {
        switch card.tone {
        case .orange: V8.ink.opacity(0.78)
        case .ink: V8.muteDark
        case .white: V8.mute
        }
    }
    private var cornerColor: Color {
        switch card.tone {
        case .orange: V8.ink
        case .ink: V8.orange
        case .white: V8.orangeDeep
        }
    }
}
