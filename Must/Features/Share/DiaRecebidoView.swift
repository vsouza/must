import SwiftData
import SwiftUI

/// O dia que alguém mandou (`must://d/<payload>`, prompt 25 · B.2): abre sem servidor, só com o que está no link.
/// Só leitura — não mexe no dia de quem recebe. Parada com `Place.id` que existe neste board abre o Lugar.
struct DiaRecebidoView: View {
    var payload: String

    @Environment(AppRouter.self) private var router
    @Query private var places: [Place]

    @State private var decoded: Result<SharedDay, DayLink.Failure>?
    @State private var posterURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch decoded {
                case .success(let day): content(day)
                case .failure: broken
                case nil: EmptyView()
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, V9.gutter)
        }
        .navigationTitle("Dia recebido")
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen()
        .onAppear {
            guard decoded == nil else { return }
            decoded = Result { try DayLink.decode(payload) }.mapError { $0 as? DayLink.Failure ?? .corrupt }
        }
        .task(id: payload) { await renderPoster() }
    }

    private func renderPoster() async {
        guard case .success(let day)? = decoded, let poster = DayPoster.make(shared: day),
              let png = DayPosterRenderer.png(poster, options: PosterOptions()) else { return }
        posterURL = DayPosterRenderer.write(png, name: "Must · Dia \(poster.numeral) · \(poster.area).png")
    }

    @ViewBuilder
    private func content(_ day: SharedDay) -> some View {
        let region = day.region ?? .bh
        let plan = day.plan()
        let number = day.n.map(String.init) ?? plan.map { region.dayNumber($0.date) } ?? ""
        Text("Só leitura · " + [day.c, plan.map { DayText.dayLine($0.date, region: region) }].compactMap { $0 }.joined(separator: " · "))
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.top, 8)
        Text(number.isEmpty ? (day.a ?? day.t) : "Dia \(number) · \(day.a ?? day.t)")
            .font(.largeTitle.bold())
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
        Text("Quem mandou montou este dia no Must. Os horários são do fuso de \(region.displayName).")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        if let plan {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { i, stop in
                    DayStopRow(stop: stop, index: i + 1, state: .upcoming, region: region, onTap: tap(stop))
                }
            }
            .padding(.top, 20)
        }
        if let posterURL {
            ShareLink(item: posterURL) {
                Label("Ver o cartaz", systemImage: "photo").frame(maxWidth: .infinity)
            }
            .v9Secondary()
            .padding(.top, 20)
        }
    }

    private func tap(_ stop: DayStop) -> (() -> Void)? {
        guard let id = stop.placeId, places.contains(where: { $0.id == id }) else { return nil }
        return { router.push(.place(id: id), on: .hoje) }
    }

    private var broken: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Esse link não abriu.").font(.title2.bold()).padding(.top, 20)
            Text("O dia vai dentro do link: se ele chegou cortado (o WhatsApp às vezes corta), peça pra mandar de novo ou o cartaz.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
