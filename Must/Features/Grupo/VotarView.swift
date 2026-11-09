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
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query(sort: [SortDescriptor(\PlacePoll.createdAt, order: .reverse)]) private var polls: [PlacePoll]
    @Query private var places: [Place]

    var body: some View {
        CutPage(title: "Votar", corner: ["Viagem · Grupo", polls.isEmpty ? "nenhuma votação" : "\(polls.count) \(polls.count == 1 ? "votação" : "votações")"],
                subtitle: "A ou B? Mande o cartaz no grupo e marque o que cada um respondeu.", height: 200, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(polls) { poll in row(poll) }
                if polls.isEmpty {
                    Text("Escolha dois lugares do board e mande “A ou B?” pro grupo.")
                        .font(V8Font.text(15)).foregroundStyle(V8.mute)
                        .padding(.horizontal, 20).padding(.top, 20)
                }
            }
        }
        .cutFooter("Nova votação") { router.sheet = .aOuB(placeId: nil) }
    }

    private func name(_ id: String) -> String { places.first { $0.id == id }?.name ?? "lugar saiu do board" }

    private func row(_ poll: PlacePoll) -> some View {
        let t = PollLogic.tally(poll.votes)
        let winner = poll.winner
        return Button { router.push(.votacao(id: poll.id), on: router.tab) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(name(poll.placeAId)) ou \(name(poll.placeBId))")
                        .font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2).multilineTextAlignment(.leading)
                    MonoLabel(winner.map { "ganhou \($0.rawValue) · \(poll.addedToDay ? "no dia" : "\(t.a) × \(t.b)")" } ?? (t.a + t.b == 0 ? "sem votos" : "empate \(t.a) × \(t.b)"),
                              size: 10, color: winner == nil ? V8.mute : V8.orangeDeep)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)).foregroundStyle(V8.ink)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 0) {
            CutScreenHeader(title: "A ou B?", corner: ["Votar", "\(picked.count) de 2"], height: 150, onBack: { dismiss() }, backIcon: "xmark")
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    slot("A", aId)
                    slot("B", bId)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                TextField("Buscar no board…", text: $query)
                    .font(V8Font.text(16)).padding(.horizontal, 12).frame(minHeight: 44)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                    .padding(.horizontal, 20).padding(.bottom, 10)
                IndexRule()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { place in
                            Button { toggle(place) } label: { pickRow(place) }.buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .cutFooter("Criar votação", enabled: aId != nil && bId != nil, action: create)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            aId = placeId
        }
    }

    private func slot(_ tag: String, _ id: String?) -> some View {
        HStack(spacing: 8) {
            Text(tag).font(V8Font.display(22)).foregroundStyle(V8.ink).frame(width: 34, height: 34).background(V8.orange)
            Text(id.flatMap { id in places.first { $0.id == id }?.name } ?? "escolha")
                .font(V8Font.text(14, weight: .semibold)).foregroundStyle(id == nil ? V8.mute : V8.ink).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    private func pickRow(_ place: Place) -> some View {
        let tag = place.id == aId ? "A" : place.id == bId ? "B" : nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                Text([place.list?.displayName, PollSideInfo.area(place, region: store.region)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let tag { Text(tag).font(V8Font.mono(13, weight: .bold)).foregroundStyle(V8.ink).frame(width: 30, height: 30).background(V8.orange) }
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.rule).frame(height: 1) }
        .contentShape(Rectangle())
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
