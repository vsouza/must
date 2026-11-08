import CoreLocation
import SwiftData
import SwiftUI

/// 07 · Dicas (prompt 23 §2, `Dicas.png`): papel, numeral "N pra hoje", filtros Agora / bairro / país / Etiqueta / Salvas
/// e os cards do dia (`DayTips`). Lê o dia do motor, as notas do board, as regras do país e só o cache das Dicas de quem
/// foi: nenhuma chamada de rede.
struct DicasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Environment(\.friends) private var friends

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

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
        VStack(spacing: 0) {
            CutScreenHeader(title: "Dicas", corner: ["Dicas · \(region.timeString(now))", "pra agora e pro resto do dia"],
                            height: 210, onBack: { dismiss() }, backIcon: "xmark")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        BigNumeral("\(today.count)", size: 74, color: V8.orange)
                            .fixedSize()
                        SpecLabel("pra hoje")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(today.count) dicas pra hoje")
                    filters(areaName: context.areaName).padding(.horizontal, 20).padding(.vertical, 16)
                    IndexRule()
                    ForEach(shown) { card in
                        VStack(alignment: .leading, spacing: 0) {
                            Button { if let id = card.placeId { router.push(.place(id: id)) } } label: { DayTipCardView(card: card) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(saved.contains(card.id) ? "Tirar das salvas" : "Salvar dica",
                                           systemImage: saved.contains(card.id) ? "bookmark.slash" : "bookmark") { toggleSaved(card.id) }
                                }
                            // Amigos que foram a esse lugar (mock "exemplo" por enquanto): uma linha, some sem visita.
                            if let id = card.placeId, let line = FriendsLine.summary(friends.visits(placeId: id)) {
                                HStack(spacing: 8) {
                                    Text(line).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(2)
                                    if friends.isSample { CutTag(text: "exemplo") }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { IndexRule() }
                            }
                        }
                    }
                    if shown.isEmpty {
                        Text(filter == .saved ? "Segure uma dica pra salvar." : "Nada aqui por enquanto.")
                            .font(V8Font.text(15)).foregroundStyle(V8.mute).padding(20)
                    }
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPeopleTips(context) }
    }

    private func filters(areaName: String?) -> some View {
        let items: [V8FilterRow.Item] = [
            .init(id: DayTips.Filter.now.rawValue, title: "Agora", on: filter == .now),
            .init(id: DayTips.Filter.area.rawValue, title: areaName ?? "Bairro", on: filter == .area),
            .init(id: DayTips.Filter.country.rawValue, title: PocketRules.country(region).name, on: filter == .country),
            .init(id: DayTips.Filter.etiquette.rawValue, title: "Etiqueta", on: filter == .etiquette),
            .init(id: DayTips.Filter.saved.rawValue, title: "Salvas", on: filter == .saved),
        ]
        return V8FilterRow(items: items) { id in
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

/// Uma dica como faixa de índice (corte): laranja = é do seu board e abre o Lugar, tinta = o mundo lá fora, papel = o resto.
struct DayTipCardView: View {
    var card: DayTips.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.tag.uppercased())
                    .font(V8Font.mono(11, weight: .semibold))
                    .tracking(1.1)
                    .lineLimit(1)
                    .foregroundStyle(tagColor)
                Spacer(minLength: 8)
                SpecLabel(card.corner, color: cornerColor)
            }
            Text(card.title)
                .font(V8Font.text(18, weight: .bold))
                .foregroundStyle(card.tone == .ink ? V8.white : V8.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(V8Font.text(14))
                    .foregroundStyle(card.tone == .ink ? V8.muteDark : card.tone == .orange ? V8.ink.opacity(0.8) : V8.mute)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .overlay(alignment: .bottom) { IndexRule() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        switch card.tone {
        case .orange: V8.orange
        case .ink: V8.ink
        case .white: Color.clear
        }
    }

    private var tagColor: Color {
        switch card.tone {
        case .orange: V8.ink
        case .ink: V8.orange
        case .white: card.placeId != nil ? V8.orangeDeep : V8.mute
        }
    }

    private var cornerColor: Color {
        switch card.tone {
        case .orange: V8.ink
        case .ink: V8.muteDark
        case .white: V8.mute
        }
    }
}
