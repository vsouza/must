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

/// Por perto, agora (design: Descobrir.png). Nunca push: só daqui e da linha da Home.
struct DiscoverView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]

    @State private var model = DiscoverModel()
    /// Bairro do GPS no cabeçalho "Por perto · <bairro>" (prompt 21 · fatia 2).
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar(now: now).padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentArea.map { "Por perto · \($0.name)" } ?? "Por perto, agora").mustTitle()
                    Text("o que as pessoas gostam aqui — esteja no seu board ou não").mustSerif(18).foregroundStyle(Color.must.secondary)
                }
                .padding(.top, 22)

                if !enabled {
                    notice("Sugestões por perto estão desligadas.", action: ("Abrir Ajustes", { router.push(.settings, on: .hoje) }))
                        .padding(.top, 26)
                } else if let first = items.first {
                    hero(first).padding(.top, 26)
                    actions(first).padding(.top, 22)
                    chips.padding(.top, 20)
                    list(model.filtered(items).filter { $0.id != first.id }).padding(.top, 14)
                    if model.batch?.places.isEmpty ?? true, !model.loading {
                        Text("Sem fontes externas agora (sem chave ou sem rede). Mostrando só o seu board.")
                            .font(.must.meta).foregroundStyle(Color.must.secondary).padding(.top, 12)
                    }
                } else if location == nil {
                    notice("Sem GPS agora: não sei o que tem perto de você.")
                        .padding(.top, 26)
                } else {
                    notice(model.loading ? "Procurando por perto…" : "Nada por perto no raio de 600 m.")
                        .padding(.top, 26)
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .home)
            }
            .ignoresSafeArea()
        }
        .task(id: loadKey) { await reload() }
        .task(id: loadKey) {
            guard let here = location else { currentArea = nil; return }
            currentArea = await services.currentArea.area(at: here, region: region)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func reload() async {
        guard enabled, let location else { return }
        await model.load(loader: services.nearby, origin: location, region: region, now: AppClock.now)
    }

    // MARK: Topo

    private func topBar(now: Date) -> some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("\(areaLabel) · \(region.timeString(now)) · raio 600 m")
            Spacer()
            // Recarrega o GPS e o cache; a rede só se o cache venceu (30 min).
            IconButton(.outraProposta, style: .dark, label: "Atualizar") { Task { await reload() } }
        }
    }

    private var areaLabel: String {
        guard let location else { return region.shortName.uppercased() }
        let near = places.filter { $0.area != nil }.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
        if let near, near.location.distance(from: location) < 3000, let area = near.area { return area.uppercased() }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)?.name
        return (city ?? region.displayName).uppercased()
    }

    // MARK: Destaque

    private func hero(_ item: NearbyScored) -> some View {
        let c = item.candidate
        let color = NearbyRanker.suggestedColor(c.place, role: c.role ?? NearbyRanker.role(for: c.place))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Tag(c.isOnBoard ? "no board · \(c.listName ?? "")" : "não está no seu board")
                Spacer()
                Micro(Walk.distanceText(c.distance), color: .white.opacity(0.9))
            }
            Spacer(minLength: 0)
            Text(c.place.name)
                .font(.must.archivo(26, .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(heroMeta(c))
                .font(.must.archivo(13))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            if let phrase = DiscoverBuilder.phrase(for: c.place) {
                Text("“\(phrase)”")
                    .mustSerif(19)
                    .foregroundStyle(Color(hex: 0xB9F5CF))
                    .lineLimit(3)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .background {
            ZStack {
                Color.must.ink
                RadialGradient(colors: [color.strong.opacity(0.9), .clear], center: .topTrailing, startRadius: 10, endRadius: 280)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .rotationEffect(.degrees(-1.2))
        .padding(.horizontal, 6)
    }

    /// "4,5 · 10 mil avaliações · fechado agora". Wikipedia não tem nota: só diz de onde veio.
    private func heroMeta(_ c: NearbyCandidate) -> String {
        if c.isContextOnly { return "contexto · Wikipedia · \(Walk.distanceText(c.distance))" }
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
                Pill("já no board", isOn: true)
            } else if let suggested {
                PrimaryButton("+ \(suggested.displayName)", style: .green) { add(c, to: suggested) }
            }
            Menu {
                ForEach(lists) { list in
                    Button(list.displayName) { add(c, to: list) }
                }
            } label: {
                Text("Outra lista")
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(suggested == nil && !c.isOnBoard ? Color.must.green : Color.must.surface))
            }
            .disabled(c.isOnBoard)
            Button { MapsLinks.openApple(to: CLLocationCoordinate2D(latitude: c.place.lat, longitude: c.place.lng), name: c.place.name) } label: {
                MustIconView(.avancar, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Ir")
        }
    }

    private func add(_ candidate: NearbyCandidate, to list: MustList) {
        DiscoverBuilder.addToBoard(candidate, list: list, region: region, now: AppClock.now, context: context)
    }

    // MARK: Filtros e lista

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DiscoverModel.Filter.allCases) { option in
                    Button { model.filter = option } label: { Pill(option.rawValue, isOn: model.filter == option) }
                        .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func list(_ items: [NearbyScored]) -> some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("Nada com esse filtro.").font(.must.meta).foregroundStyle(Color.must.secondary).padding(18)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(item)
                if index < items.count - 1 { RowDivider().padding(.horizontal, 14) }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func row(_ item: NearbyScored) -> some View {
        let c = item.candidate
        let role = c.role ?? NearbyRanker.role(for: c.place)
        let color = NearbyRanker.suggestedColor(c.place, role: role)
        let content = HStack(spacing: 12) {
            TintedPhoto(url: nil, color: color)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.place.name).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                    if c.isOnBoard { Tag("no board") }
                }
                Text(rowMeta(c)).font(.must.meta).foregroundStyle(Color.must.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let chip = c.place.sources.compactMap(\.chip).first { Tag(chip) }
        }
        .padding(14)
        .contentShape(Rectangle())

        if let id = c.boardPlaceId {
            return AnyView(Button { router.push(.place(id: id), on: .hoje) } label: { content }.buttonStyle(MustPressStyle()))
        }
        return AnyView(Button {
            if let list = DiscoverBuilder.suggestedList(for: c, lists: lists) { add(c, to: list) }
        } label: { content }
        .buttonStyle(MustPressStyle()))
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
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
            if let action {
                GhostButton(action.0) { action.1() }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
