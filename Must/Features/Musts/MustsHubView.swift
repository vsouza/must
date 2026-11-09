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
        let ids = Set(scoped.map(\.id))
        List {
            Section {
                filters
            } header: {
                Text("\(scoped.count) lugares · \(done) feitos")
            }
            Section("Listas") {
                ForEach(lists) { list in
                    let inList = list.places.filter { ids.contains($0.id) }
                    Button { router.push(list.kind == .experience ? .experiences : .list(id: list.id), on: .musts) } label: {
                        MustsIndexRow(list: list, meta: MustsMeta.line(list: list, places: inList, snapshot: snapshot, region: region, now: now),
                                      count: inList.count, done: inList.filter(\.isDone).count)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                let later = places.filter { $0.saveForEnd && !$0.isDone }.count
                if later > 0 {
                    extraRow("Fica pro fim · \(later)", meta: trips.first?.hasTrip == true ? "entram nos últimos dias da cidade" : "quando você pedir", icon: "flag.checkered") {
                        router.push(.saveForEnd, on: .musts)
                    }
                }
                extraRow("Ver tudo · editar", meta: "o board inteiro", icon: "square.grid.2x2") { router.push(.board(edit: false), on: .musts) }
                extraRow("Nova lista", meta: "nome, tipo e sub-listas", icon: "plus.circle") { router.cover = .newList }
            }
        }
        .navigationTitle("Musts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .addLink(url: nil, listId: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Adicionar por link")
            }
        }
        .v9Screen(grouped: true)
    }

    /// Cidade (se houver mais de uma) e filtros como um menu e interruptores: tudo visível, nada escondido.
    @ViewBuilder private var filters: some View {
        if !cityNames.isEmpty {
            Picker("Cidade", selection: Binding(get: { activeCity ?? "" }, set: { city = $0.isEmpty ? nil : $0; cityPicked = true })) {
                Text("Todas").tag("")
                ForEach(cityNames, id: \.self) { Text($0).tag($0) }
            }
        }
        Toggle("Perto (até 2 km)", isOn: $near)
        Toggle("Abertos agora", isOn: $openOnly)
        Toggle("Sem foto (gasta menos dados)", isOn: $noPhotos)
    }

    private func extraRow(_ title: String, meta: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(.secondary).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum MustsPrefs {
    /// "Sem foto" (Musts): as listas abrem sem miniaturas.
    static let noPhotosKey = "v8.lists.noPhotos"
}

/// Linha de uma lista: ícone da lista (ponto da cor do Must), nome, meta e a contagem à direita.
struct MustsIndexRow: View {
    var list: MustList
    var meta: String
    var count: Int
    var done: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MustIconView(list.icon, size: 20)
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.displayName).font(.body.weight(.semibold)).lineLimit(2)
                Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)").font(.body.weight(.semibold)).monospacedDigit()
                Text(done == 1 ? "1 feito" : "\(done) feitos").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(list.displayName), \(count) lugares, \(done) feitos. \(meta)")
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
