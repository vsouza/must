import CoreLocation
import SwiftUI

/// Lugar › "Filmes gravados aqui" (`LugarAmigos.png`, bloco de baixo): capas tipográficas (ano em numeral laranja, sem
/// pôster por licença) e um cartão tracejado que abre a tela Filmes. Só consulta com o Lugar aberto, uma vez por lugar
/// por sessão (o provedor guarda 30 dias em disco). Sem filme, o bloco some.
struct FilmsSection: View {
    var place: Place
    var region: Region
    var areaName: String?

    @Environment(\.films) private var filmsProvider
    @Environment(AppRouter.self) private var router
    @State private var films: [Film] = []

    private static let radiusKm = 1.5

    var body: some View {
        Group {
            if !films.isEmpty { content }
        }
        .task(id: place.id) {
            let key = FilmsSessionMemo.key(place.id, radiusKm: Self.radiusKm)
            if let memo = FilmsSessionMemo.get(key) { films = memo; return }
            let found = FilmsFormat.ordered(await FilmsProvider.resolve(filmsProvider, region: region)
                .films(near: place.coordinate, radiusKm: Self.radiusKm))
            FilmsSessionMemo.set(key, found)
            films = found
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Filmes gravados aqui").font(V8Font.display(28)).tracking(-0.8).foregroundStyle(V8.ink)
                    .lineLimit(2).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                SpecLabel("wikidata")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(films.prefix(5).enumerated()), id: \.offset) { offset, film in
                        card(film, ink: offset == 0)
                    }
                    moreCard
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
            .scrollClipDisabled()
            .padding(.top, 14)
            SpecLabel("wikidata cc0 · cache 30 dias").padding(.top, 12)
        }
    }

    private func card(_ film: Film, ink: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SpecLabel(ink ? "filmado" : FilmsFormat.credit(film), color: ink ? V8.muteDark : V8.mute)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if ink {
                    BigNumeral(FilmsFormat.yearDigits(film.year), size: 60, color: V8.orange, alignment: .trailing)
                }
            }
            Spacer(minLength: 8)
            Text(film.title).font(V8Font.text(18, weight: .bold)).tracking(-0.2)
                .foregroundStyle(ink ? V8.white : V8.ink).lineLimit(3).multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(width: 118, height: 168, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ink ? V8.ink : Color.clear))
        .overlay { if !ink { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(V8.ink, lineWidth: 1.5) } }
        .accessibilityElement(children: .combine)
    }

    private var moreCard: some View {
        Button { router.push(.filmes(placeId: place.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)
                Text("\(films.count)")
                    .font(V8Font.numeral(44)).foregroundStyle(V8.orangeDeep)
                Text("no bairro\(areaName.map { " de \($0)" } ?? "") ↗")
                    .font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                    .lineLimit(3).multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(width: 128, height: 168, alignment: .bottomLeading)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(V8.mute, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("\(films.count) filmes no bairro")
    }
}
