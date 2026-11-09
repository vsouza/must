import CoreLocation
import SwiftData
import SwiftUI

/// Filmes gravados no lugar/bairro (V9, prompt 27 §6). Abre com o cache e atualiza por
/// baixo; BH quase sempre cai no estado vazio, com "Tentar 5 km" e "Ver <cidade> inteira".
struct FilmsView: View {
    var placeId: String

    @Environment(\.films) private var filmsProvider
    @Environment(RegionStore.self) private var store
    @Query private var matches: [Place]

    @State private var radiusKm = 1.5
    @State private var films: [Film]?

    init(placeId: String) {
        self.placeId = placeId
        _matches = Query(filter: #Predicate<Place> { $0.id == placeId })
    }

    private var region: Region { store.region }
    private var place: Place? { matches.first }

    private var areaLabel: String {
        guard let place else { return region.displayName }
        return region == .jp ? (place.area ?? place.name) : "\(place.name) · \(region.shortName)"
    }

    var body: some View {
        let list = films ?? []
        List {
            Section {
                Text("\(areaLabel) · raio \(radiusText)").font(.subheadline).foregroundStyle(.secondary)
            } footer: {
                Text(list.isEmpty ? "Fonte: Wikidata." : "Fonte: Wikidata · CC0 · cache de 30 dias.")
            }
            if list.isEmpty, films != nil {
                emptyState
            } else if !list.isEmpty {
                Section("\(list.count) no bairro") {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, film in row(film) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Filmes")
        .navigationBarTitleDisplayMode(.large)
        .v9Screen(grouped: true)
        .task(id: radiusKm) { await load() }
    }

    private var radiusText: String {
        radiusKm == radiusKm.rounded() ? "\(Int(radiusKm)) km" : String(format: "%.1f km", radiusKm).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Linhas

    private func row(_ film: Film) -> some View {
        Button { if let url = film.url { UIApplication.shared.open(url) } } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(FilmsFormat.yearDigits(film.year))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56, alignment: .leading)
                    .accessibilityLabel("Ano \(FilmsFormat.yearDigits(film.year))")
                VStack(alignment: .leading, spacing: 3) {
                    Text(film.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(3).multilineTextAlignment(.leading)
                    let credit = FilmsFormat.credit(film)
                    if !credit.isEmpty { Text(credit).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    let where_ = FilmsFormat.place(film)
                    if !where_.isEmpty {
                        Text("Filmado em \(where_)").font(.subheadline).foregroundStyle(.primary)
                            .lineLimit(3).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Vazio

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nada filmado aqui, ainda.").font(.headline)
                Text("O Wikidata tem pouco de \(region.displayName). O bloco “Filmes gravados aqui” some do Lugar quando não há resultado.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Tentar 5 km") { radiusKm = 5 }.disabled(radiusKm >= 5)
            Button("Ver \(region.shortName) inteira") { radiusKm = 25 }.disabled(radiusKm >= 25)
        } footer: {
            Text("Consultado uma vez, guardado 30 dias. Sem internet, mostra o último resultado.")
        }
    }

    // MARK: Dados

    private func load() async {
        guard let place else { films = []; return }
        let key = FilmsSessionMemo.key(place.id, radiusKm: radiusKm)
        if let memo = FilmsSessionMemo.get(key) { films = memo; return }
        let found = FilmsFormat.ordered(await FilmsProvider.resolve(filmsProvider, region: region)
            .films(near: place.coordinate, radiusKm: radiusKm))
        FilmsSessionMemo.set(key, found)
        films = found
    }
}
