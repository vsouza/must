import CoreLocation
import SwiftData
import SwiftUI

/// Dados do cartaz e do texto de um lado da votação, tirados do Must (sem rede: foto só se já está no disco).
@MainActor
enum PollSideInfo {
    static func area(_ place: Place, region: Region) -> String {
        guard let raw = place.area, !raw.isEmpty else { return "" }
        return AreaCatalog.areas(for: region).first { $0.id == raw }?.name ?? raw
    }

    static func minutes(_ place: Place, here: CLLocation?, walkMax: Double) -> Int? {
        guard let here else { return nil }
        let minutes = PlaceFicha.travelMinutes(place, from: here, walkMaxKm: walkMax)
        return minutes <= maxMinutes ? minutes : nil
    }

    @MainActor
    static func side(_ place: Place, region: Region, here: CLLocation?, walkMax: Double) -> PollPoster.Side {
        let photo = place.photoRefs.first.flatMap { PlacePhotoStore.existing($0) }?.path()
        return PollPoster.Side(name: place.name, area: area(place, region: region),
                               minutes: minutesText(minutes(place, here: here, walkMax: walkMax)), photoPath: photo)
    }

    /// Acima disso o lugar é de outra cidade (Tóquio → Kyoto dava "440 min" no cartaz): melhor não dizer nada.
    nonisolated static let maxMinutes = 90

    nonisolated static func minutesText(_ minutes: Int?) -> String {
        guard let minutes, minutes <= maxMinutes else { return "" }
        return "\(minutes) min"
    }
}

/// Viagem › Grupo › Votar (prompt 32): as votações "A ou B?" da viagem. Nova votação escolhe dois Musts.
struct VotarView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query(sort: [SortDescriptor(\PlacePoll.createdAt, order: .reverse)]) private var polls: [PlacePoll]
    @Query private var places: [Place]

    var body: some View {
        List {
            Section {
                ForEach(polls) { poll in row(poll) }
                if polls.isEmpty {
                    Text("Escolha dois lugares do board e mande “A ou B?” pro grupo.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } header: {
                Text(polls.isEmpty ? "Nenhuma votação" : "\(polls.count) \(polls.count == 1 ? "votação" : "votações")")
            } footer: {
                Text("A ou B? Mande o cartaz no grupo e marque o que cada um respondeu.")
            }
        }
        .navigationTitle("Votar")
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .j9Footer("Nova votação") { router.sheet = .aOuB(placeId: nil) }
    }

    private func name(_ id: String) -> String { places.first { $0.id == id }?.name ?? "lugar saiu do board" }

    private func row(_ poll: PlacePoll) -> some View {
        let t = PollLogic.tally(poll.votes)
        let winner = poll.winner
        let status = winner.map { "ganhou \($0.rawValue) · \(poll.addedToDay ? "no dia" : "\(t.a) × \(t.b)")" } ?? (t.a + t.b == 0 ? "sem votos" : "empate \(t.a) × \(t.b)")
        return Button { router.push(.votacao(id: poll.id), on: router.tab) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(name(poll.placeAId)) ou \(name(poll.placeBId))")
                        .font(.body).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                    Text(status).font(.footnote).foregroundStyle(winner == nil ? Color.secondary : V9.accent)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }
}

/// Folha "A ou B?": o lugar de onde veio (A) e a escolha do B entre os Musts da cidade; cria a votação e abre.
struct NovaVotacaoView: View {
    var placeId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query(sort: \Place.name) private var places: [Place]

    @State private var aId: String?
    @State private var bId: String?
    @State private var query = ""
    @State private var loaded = false

    private var picked: [String] { [aId, bId].compactMap { $0 } }
    private var shown: [Place] {
        let list = places.filter { !$0.isDone && $0.matches(query) }
        return query.isEmpty ? Array(list.prefix(80)) : list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    slot("A", aId)
                    slot("B", bId)
                }
                .padding(.horizontal, V9.gutter).padding(.vertical, 12)
                J9SearchField(text: $query, placeholder: "Buscar no board…") { EmptyView() }
                    .padding(.horizontal, V9.gutter).padding(.bottom, 8)
                List {
                    ForEach(shown) { place in
                        Button { toggle(place) } label: { pickRow(place) }.foregroundStyle(.primary)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("A ou B?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .j9Footer("Criar votação", enabled: aId != nil && bId != nil, action: create)
            .v9Screen()
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            aId = placeId
        }
    }

    private func slot(_ tag: String, _ id: String?) -> some View {
        HStack(spacing: 8) {
            Text(tag).font(.headline).foregroundStyle(.white).frame(width: 32, height: 32).background(V9.accent, in: Circle())
            Text(id.flatMap { id in places.first { $0.id == id }?.name } ?? "escolha")
                .font(.subheadline.weight(.semibold)).foregroundStyle(id == nil ? Color.secondary : Color.primary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(V9.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pickRow(_ place: Place) -> some View {
        let tag = place.id == aId ? "A" : place.id == bId ? "B" : nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body).lineLimit(2)
                Text([place.list?.displayName, PollSideInfo.area(place, region: store.region)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let tag { Text(tag).font(.subheadline.weight(.bold)).foregroundStyle(.white).frame(width: 30, height: 30).background(V9.accent, in: Circle()) }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(tag == nil ? [] : .isSelected)
    }

    private func toggle(_ place: Place) {
        if aId == place.id { aId = nil } else if bId == place.id { bId = nil }
        else if aId == nil { aId = place.id } else if bId == nil { bId = place.id }
        else { bId = place.id }
    }

    private func create() {
        guard let aId, let bId, aId != bId else { return }
        let poll = PlacePoll(a: aId, b: bId)
        context.insert(poll)
        try? context.save()
        let id = poll.id
        dismiss()
        router.push(.votacao(id: id), on: router.tab)
    }
}
