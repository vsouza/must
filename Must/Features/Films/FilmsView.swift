import CoreLocation
import SwiftData
import SwiftUI

/// Filmes gravados no lugar/bairro (`Filmes.png`, `FilmesVazio.png`, prompt 27 §6). Abre com o cache e atualiza por
/// baixo; BH quase sempre cai no estado vazio, com "Tentar 5 km" e "Ver <cidade> inteira".
struct FilmsView: View {
    var placeId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.films) private var filmsProvider
    @Environment(RegionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 8)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("Filmes").font(V8Font.display(52)).tracking(-1.6).foregroundStyle(V8.ink)
                        .lineLimit(1).minimumScaleFactor(0.6).accessibilityAddTraits(.isHeader)
                    BigNumeral("\(list.count)", size: 74, color: list.isEmpty ? V8.muteDark : V8.orange)
                    if !list.isEmpty { SpecLabel("no bairro").padding(.bottom, 10) }
                }
                .padding(.top, 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Filmes: \(list.count)")
                if list.isEmpty, films != nil {
                    emptyState.padding(.top, 70)
                } else if !list.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, film in row(film) }
                    }
                    .padding(.top, 26)
                    SpecLabel("wikidata · cc0 · cache de 30 dias").padding(.top, 20)
                }
                V8BarSpacer()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: radiusKm) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            V8CornerButton(systemName: "chevron.left", label: "Voltar") { dismiss() }
            Spacer(minLength: 12)
            V8SpecStack(lines: ["\(areaLabel) · raio \(radiusText)", films?.isEmpty == false ? "fonte: wikidata · cc0" : "wikidata"]
                .map { $0 }, alignment: .trailing).padding(.top, 14)
        }
    }

    private var radiusText: String {
        radiusKm == radiusKm.rounded() ? "\(Int(radiusKm)) km" : String(format: "%.1f km", radiusKm).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Linhas

    private func row(_ film: Film) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(FilmsFormat.yearDigits(film.year))
                .font(V8Font.numeral(50)).foregroundStyle(V8.orange)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 62, height: 90, alignment: .topTrailing)
                .padding(.trailing, 2)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(V8.ink))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title).font(V8Font.text(20, weight: .bold)).tracking(-0.3).foregroundStyle(V8.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                let credit = FilmsFormat.credit(film)
                if !credit.isEmpty { Text(credit).font(V8Font.text(14)).foregroundStyle(V8.mute).lineLimit(1) }
                let where_ = FilmsFormat.place(film)
                if !where_.isEmpty {
                    Text(where_).font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                V8Tag(text: "filmado", style: .orange).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { if let url = film.url { UIApplication.shared.open(url) } }
        .accessibilityElement(children: .combine)
    }

    // MARK: Vazio

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nada filmado aqui, ainda.").font(V8Font.display(34)).tracking(-1).foregroundStyle(V8.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("O Wikidata tem pouco de \(region.displayName). O bloco “Filmes gravados aqui” some do Lugar quando não há resultado: nada de caixa vazia.")
                .font(V8Font.text(16)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(spacing: 12) { buttons }
            }
            .padding(.top, 6)
            SpecLabel("consultado uma vez · guardado 30 dias · sem internet, mostra o último resultado")
                .padding(.top, 90)
        }
    }

    @ViewBuilder private var buttons: some View {
        V8Button("Tentar 5 km", .line) { radiusKm = 5 }.disabled(radiusKm >= 5)
        V8Button("Ver \(region.shortName) inteira", .ink) { radiusKm = 25 }.disabled(radiusKm >= 25)
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
