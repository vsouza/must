import CoreLocation
import SwiftData
import SwiftUI

/// Estado da tela Descobrir: só o filtro e o último cache lido. A rede passa pelo `NearbyLoader`.
@MainActor
@Observable
final class DiscoverModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tudo", eat = "Comer", see = "Ver", experiences = "Experiências", outside = "Só fora do board"
        var id: String { rawValue }
    }

    var filter: Filter = .all
    private(set) var batch: NearbyBatch?
    private(set) var loading = false

    /// Uma chamada por abertura (o cache de 30 min por célula segura as seguintes).
    func load(loader: NearbyLoader, origin: CLLocation, region: Region, now: Date) async {
        loading = true
        batch = await loader.load(lat: origin.coordinate.latitude, lng: origin.coordinate.longitude, region: region, now: now)
        loading = false
    }

    func filtered(_ items: [NearbyScored]) -> [NearbyScored] {
        items.filter { item in
            let c = item.candidate
            switch filter {
            case .all: return true
            case .eat: return c.role == .eat
            case .see: return c.role == .see || c.role == .photo
            case .experiences: return c.isExperience
            case .outside: return !c.isOnBoard
            }
        }
    }
}

/// Por perto, agora (V9, `List` nativa). Nunca push: só daqui e da linha da Home.
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]

    @State private var model = DiscoverModel()
    /// Bairro do GPS no título "Por perto · <bairro>".
    @State private var currentArea: Area?

    private var region: Region { store.region }
    private var enabled: Bool { settingsList.first?.suggestNearby ?? true }
    private var location: CLLocation? { services.location.current }
    private var loadKey: String {
        location.map { NearbyCell.key(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, region: region) } ?? "sem-gps"
    }

    var body: some View {
        let now = AppClock.now
        let items = location.map { DiscoverBuilder.ranked(batch: model.batch, places: places, origin: $0, now: now, region: region) } ?? []
        List {
            Section {
                Text("\(areaLabel) · \(region.timeString(now)) · raio 600 m. O que as pessoas gostam aqui, esteja no seu board ou não.")
                    .font(.subheadline).foregroundStyle(.secondary)
                V9OfflineChip()
            }
            if !enabled {
                notice("Sugestões por perto estão desligadas.", action: ("Abrir Ajustes", { router.push(.settings, on: .hoje) }))
            } else if let first = items.first {
                Section {
                    hero(first)
                    actions(first)
                } header: {
                    Text("Mais indicado")
                }
                Section {
                    Picker("Mostrar", selection: $model.filter) {
                        ForEach(DiscoverModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    let rest = model.filtered(items).filter { $0.id != first.id }
                    if rest.isEmpty {
                        Text("Nada com esse filtro.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, item in row(item) }
                } header: {
                    Text("Por perto")
                } footer: {
                    if model.batch?.places.isEmpty ?? true, !model.loading {
                        Text("Sem fontes externas agora (sem chave ou sem rede). Mostrando só o seu board.")
                    }
                }
            } else if location == nil {
                notice("Sem GPS agora: não sei o que tem perto de você.")
            } else {
                notice(model.loading ? "Procurando por perto…" : "Nada por perto no raio de 600 m.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentArea.map { "Por perto · \($0.name)" } ?? "Por perto, agora")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Recarrega o GPS e o cache; a rede só se o cache venceu (30 min).
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Atualizar")
            }
        }
        .v9Screen(grouped: true)
        .task(id: loadKey) { await reload() }
        .task(id: loadKey) {
            guard let here = location else { currentArea = nil; return }
            currentArea = await services.currentArea.area(at: here, region: region)
        }
    }

    private func reload() async {
        guard enabled, let location else { return }
        await model.load(loader: services.nearby, origin: location, region: region, now: AppClock.now)
    }

    private var areaLabel: String {
        guard let location else { return region.shortName }
        let near = places.filter { $0.area != nil }.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
        if let near, near.location.distance(from: location) < 3000, let area = near.area { return area }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)?.name
        return city ?? region.displayName
    }

    // MARK: Destaque

    private func hero(_ item: NearbyScored) -> some View {
        let c = item.candidate
        return VStack(alignment: .leading, spacing: 4) {
            Text(c.isOnBoard ? "No board · \(c.listName ?? "")" : "Não está no seu board")
                .font(.footnote).foregroundStyle(.secondary)
            Text(c.place.name).font(.title3.weight(.semibold)).lineLimit(3)
            Text("\(Walk.distanceText(c.distance)) · \(heroMeta(c))").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            if let phrase = DiscoverBuilder.phrase(for: c.place) {
                Text("“\(phrase)”").font(.subheadline.italic()).lineLimit(4).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "4,5 · 10 mil avaliações · fechado agora". Wikipedia não tem nota: só diz de onde veio.
    private func heroMeta(_ c: NearbyCandidate) -> String {
        if c.isContextOnly { return "contexto · Wikipedia" }
        var parts: [String] = []
        if let rating = c.place.rating {
            parts.append(rating.formatted(.number.precision(.fractionLength(1)).locale(region.locale)))
        }
        if let count = c.place.ratingCount { parts.append("\(compactCount(count)) avaliações") }
        if let open = c.place.openNow { parts.append(open ? "aberto agora" : "fechado agora") }
        return parts.isEmpty ? "sem nota da fonte" : parts.joined(separator: " · ")
    }

    private func actions(_ item: NearbyScored) -> some View {
        let c = item.candidate
        let suggested = DiscoverBuilder.suggestedList(for: c, lists: lists)
        return HStack(spacing: 10) {
            if c.isOnBoard {
                Label("Já no board", systemImage: "checkmark").font(.subheadline.weight(.semibold))
            } else if let suggested {
                Button("+ \(suggested.displayName)") { add(c, to: suggested) }.v9Primary()
            }
            Menu {
                ForEach(lists) { list in
                    Button(list.displayName) { add(c, to: list) }
                }
            } label: {
                Text("Outra lista").frame(minHeight: 28)
            }
            .buttonStyle(.bordered)
            .disabled(c.isOnBoard)
            Spacer(minLength: 0)
            Button { MapsLinks.openApple(to: CLLocationCoordinate2D(latitude: c.place.lat, longitude: c.place.lng), name: c.place.name) } label: {
                Label("Ir", systemImage: "arrow.triangle.turn.up.right.diamond")
            }
            .buttonStyle(.bordered)
        }
        .buttonStyle(.borderless)
    }

    private func add(_ candidate: NearbyCandidate, to list: MustList) {
        DiscoverBuilder.addToBoard(candidate, list: list, region: region, now: AppClock.now, context: context)
    }

    // MARK: Lista

    private func row(_ item: NearbyScored) -> some View {
        let c = item.candidate
        let label = V9Row(title: c.place.name, detail: rowMeta(c),
                          reason: c.isOnBoard ? "no board" : (c.place.sources.compactMap(\.chip).first),
                          systemImage: c.isOnBoard ? "bookmark.fill" : "mappin.circle")
        if let id = c.boardPlaceId {
            return AnyView(Button { router.push(.place(id: id), on: .hoje) } label: { label }.buttonStyle(.plain))
        }
        return AnyView(HStack {
            label
            if let list = DiscoverBuilder.suggestedList(for: c, lists: lists) {
                Button { add(c, to: list) } label: { Image(systemName: "plus.circle").font(.title2).frame(width: 44, height: 44) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Adicionar a \(list.displayName)")
            }
        })
    }

    /// Board: "Must drink · aberto · 180 m · 4,6 · 3,1 mil". De fora: a categoria em pt no lugar do nome da lista.
    private func rowMeta(_ c: NearbyCandidate) -> String {
        var parts: [String] = [c.listName ?? NearbyRanker.categoryLabel(c.place) ?? "lugar"]
        if c.place.openNow == true { parts.append("aberto") } else if c.place.openNow == false { parts.append("fechado") }
        parts.append(Walk.distanceText(c.distance))
        if let rating = c.place.rating { parts.append(rating.formatted(.number.precision(.fractionLength(1)).locale(region.locale))) }
        if let count = c.place.ratingCount { parts.append(compactCount(count)) }
        return parts.joined(separator: " · ")
    }

    private func compactCount(_ n: Int) -> String {
        n >= 1000 ? "\((Double(n) / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(region.locale))) mil" : "\(n)"
    }

    // MARK: Avisos

    private func notice(_ text: String, action: (String, () -> Void)? = nil) -> some View {
        Section {
            Text(text).font(.body)
            if let action {
                Button(action.0) { action.1() }
            }
        }
    }
}
