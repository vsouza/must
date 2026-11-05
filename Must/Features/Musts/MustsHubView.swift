import SwiftData
import SwiftUI

/// 10 · Musts (prompt 23 §2, `Musts.png`): índice gigante por lista (01 Eat 23 …), uma linha de meta, contagem e feitos.
/// Filtros por cidade, Perto, Abertos e Sem foto (economia de dado: as listas abrem sem miniaturas). Sem cor por lista.
struct MustsHubView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var city: String?
    @State private var cityPicked = false
    @State private var near = false
    @State private var openOnly = false
    @AppStorage(MustsPrefs.noPhotosKey) private var noPhotos = false
    @State private var openNow = OpenNowIndex()

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    /// Cidades da viagem (Tóquio 1 e 2 contam como uma). Só aparecem com mais de uma.
    private var cityNames: [String] {
        var seen: [String] = []
        for c in trips.first?.cities ?? [] where !seen.contains(c.name) { seen.append(c.name) }
        return seen.count > 1 ? seen : []
    }

    /// Cidade ativa: a escolhida, ou a de hoje na viagem.
    private var activeCity: String? {
        if cityPicked { return city }
        guard !cityNames.isEmpty else { return nil }
        return trips.first?.city(on: now, calendar: region.calendar)?.name ?? cityNames.first
    }

    private func cityName(_ place: Place) -> String? { trips.first?.city(id: place.cityId)?.name }

    var body: some View {
        let snapshot = openNow.snapshot(for: places, now: now, timeZone: region.timeZone, location: services.location.current)
        let scoped = places.filter { place in
            if let activeCity, cityName(place) != activeCity { return false }
            if near, (snapshot.distance(place.id) ?? .infinity) > 2_000 { return false }
            if openOnly, !snapshot.isOpen(place.id) { return false }
            return true
        }
        let done = scoped.filter(\.isDone).count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(total: scoped.count, done: done).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Musts")
                        .font(V8Font.display(52))
                        .tracking(-1.6)
                        .foregroundStyle(V8.ink)
                        .accessibilityAddTraits(.isHeader)
                    BigNumeral("\(scoped.count)", size: 74, color: V8.orange)
                }
                .padding(.top, 22)
                filters.padding(.top, 20)
                rows(scoped: scoped, snapshot: snapshot).padding(.top, 24)
                extras.padding(.top, 8)
                V8BarSpacer()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(V8PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func header(total: Int, done: Int) -> some View {
        HStack(alignment: .top) {
            V8SpecStack(lines: ["Musts · \(activeCity ?? region.shortName)", "\(total) lugares · \(done) feitos"]).padding(.top, 14)
            Spacer(minLength: 12)
            V8CornerButton(systemName: "plus", label: "Adicionar por link", filled: true) {
                router.sheet = .addLink(url: nil, listId: nil)
            }
        }
    }

    private var filters: some View {
        var items = cityNames.map { V8FilterRow.Item(id: "city:\($0)", title: $0, on: activeCity == $0) }
        items.append(.init(id: "near", title: "Perto", on: near))
        items.append(.init(id: "open", title: "Abertos", on: openOnly))
        items.append(.init(id: "nophoto", title: "Sem foto", on: noPhotos))
        return V8FilterRow(items: items) { id in
            switch id {
            case "near": near.toggle()
            case "open": openOnly.toggle()
            case "nophoto": noPhotos.toggle()
            default:
                let name = String(id.dropFirst("city:".count))
                city = activeCity == name ? nil : name
                cityPicked = true
            }
        }
    }

    private func rows(scoped: [Place], snapshot: OpenNowIndex.Snapshot) -> some View {
        let ids = Set(scoped.map(\.id))
        return VStack(spacing: 0) {
            ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                let inList = list.places.filter { ids.contains($0.id) }
                Button { router.push(list.kind == .experience ? .experiences : .list(id: list.id), on: .musts) } label: {
                    MustsIndexRow(index: String(format: "%02d", index + 1), title: list.name.capitalized,
                                  meta: MustsMeta.line(list: list, places: inList, snapshot: snapshot, region: region, now: now),
                                  count: inList.count, done: inList.filter(\.isDone).count)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
    }

    /// Fica pro fim, o board inteiro e a lista nova (o que o hub v5 tinha).
    private var extras: some View {
        let later = places.filter { $0.saveForEnd && !$0.isDone }.count
        return VStack(spacing: 0) {
            if later > 0 {
                extraRow("Fica pro fim · \(later)", meta: trips.first?.hasTrip == true ? "entram nos últimos dias da cidade" : "quando você pedir") {
                    router.push(.saveForEnd, on: .musts)
                }
            }
            extraRow("Ver tudo · editar", meta: "o board inteiro") { router.push(.board(edit: false), on: .musts) }
            extraRow("Nova lista", meta: "nome, tipo e sub-listas") { router.cover = .newList }
        }
    }

    private func extraRow(_ title: String, meta: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(V8Font.text(16, weight: .semibold)).foregroundStyle(V8.ink)
                    Text(meta).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(V8.mute)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum MustsPrefs {
    /// "Sem foto" (Musts): as listas abrem sem miniaturas.
    static let noPhotosKey = "v8.lists.noPhotos"
}

/// Linha do índice de listas: "01" grande em laranja escuro, nome, meta; à direita a contagem e os feitos.
struct MustsIndexRow: View {
    var index: String
    var title: String
    var meta: String
    var count: Int
    var done: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(index)
                .font(V8Font.numeral(40))
                .tracking(-1.5)
                .foregroundStyle(V8.orangeDeep)
                .frame(width: 66, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                Text(meta).font(V8Font.text(14)).foregroundStyle(V8.mute).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(count)").font(V8Font.mono(13).weight(.bold)).foregroundStyle(V8.ink)
                Text(done == 1 ? "1 feito" : "\(done) feitos").font(V8Font.mono(12)).foregroundStyle(V8.mute)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) lugares, \(done) feitos. \(meta)")
    }
}

/// A linha de meta de cada lista (Musts.png): "ramen 9 · sushi 7 · 11 abertos agora", "golden hoje 16:38 · 2 perto",
/// "2 saem esta semana", "corrida 3 · jogo 2".
@MainActor
enum MustsMeta {
    static func line(list: MustList, places: [Place], snapshot: OpenNowIndex.Snapshot, region: Region, now: Date) -> String {
        var parts: [String] = []
        switch list.kind {
        case .photo:
            if let first = places.first {
                let sun = SunService.day(now, first.coordinate, timeZone: region.timeZone)
                if let g = sun.goldenPM { parts.append("golden \(now <= g.end ? "hoje" : "amanhã") \(region.timeString(g.end))") }
            }
            let close = places.filter { (snapshot.distance($0.id) ?? .infinity) < 2_000 }.count
            if close > 0 { parts.append("\(close) perto") }
        case .art:
            let ending = places.filter { p in
                (p.extra?.art?.daysLeft(from: now, calendar: region.calendar)).map { (0...7).contains($0) } ?? false
            }.count
            if ending > 0 { parts.append("\(ending) \(ending == 1 ? "sai" : "saem") esta semana") }
        case .sport:
            let counts = Dictionary(grouping: places.compactMap { $0.extra?.sport?.activity }, by: { $0 })
            for a in SportActivity.allCases { if let n = counts[a]?.count { parts.append("\(a.label.lowercased()) \(n)") } }
        case .place, .experience:
            break
        }
        if parts.isEmpty {
            parts = list.subs.compactMap { sub -> String? in
                let n = places.filter { $0.sub == sub }.count
                return n > 0 ? "\(sub.lowercased()) \(n)" : nil
            }.prefix(2).map { $0 }
        }
        let open = places.filter { snapshot.isOpen($0.id) }.count
        if open > 0 && list.kind == .place { parts.append("\(open) abertos agora") }
        if parts.isEmpty { parts.append(places.isEmpty ? "nada aqui ainda" : "\(places.filter(\.isDone).count) feitos") }
        return parts.joined(separator: " · ")
    }
}
