import SwiftData
import SwiftUI

/// O dia que alguém mandou (`must://d/<payload>`, prompt 25 · B.2): abre sem servidor, só com o que está no link.
/// Só leitura — não mexe no dia de quem recebe. Parada com `Place.id` que existe neste board abre o Lugar.
struct DiaRecebidoView: View {
    var payload: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query private var places: [Place]

    @State private var decoded: Result<SharedDay, DayLink.Failure>?
    @State private var posterURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            V8.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch decoded {
                    case .success(let day): content(day)
                    case .failure: broken
                    case nil: EmptyView()
                    }
                    Color.clear.frame(height: 130)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            BottomFade(color: V8.paper, height: 150)
        }
        .toolbar(.hidden, for: .navigationBar)
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
        HStack(alignment: .top) {
            V8CornerButton(systemName: "chevron.left", label: "Voltar") { dismiss() }
            Spacer(minLength: 12)
            SpecStack(lines: ["Dia recebido · só leitura", [day.c, plan.map { DayText.dayLine($0.date, region: region) }]
                .compactMap { $0 }.joined(separator: " · ")], color: V8.mute, alignment: .trailing)
                .padding(.top, 6)
        }
        .padding(.top, 10)
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Dia").font(V8Font.display(44)).foregroundStyle(V8.ink)
            BigNumeral(day.n.map(String.init) ?? plan.map { region.dayNumber($0.date) } ?? "", size: 84, color: V8.orange)
                .fixedSize()
                .padding(.bottom, -6)
        }
        .padding(.top, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dia \(day.n.map(String.init) ?? "")")
        Text(day.a ?? day.t)
            .font(V8Font.display(26))
            .foregroundStyle(V8.ink)
            .padding(.top, 6)
        Text("Quem mandou montou este dia no Must. Os horários são do fuso de \(region.displayName).")
            .font(V8Font.text(14))
            .foregroundStyle(V8.mute)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        if let plan {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { i, stop in
                    DayStopRow(stop: stop, index: i + 1, state: .upcoming, region: region, onTap: tap(stop))
                }
            }
            .padding(.top, 22)
        }
        if let posterURL {
            ShareLink(item: posterURL) {
                Text("Ver o cartaz")
                    .font(V8Font.text(16, weight: .bold))
                    .foregroundStyle(V8.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(Capsule().strokeBorder(V8.ink, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(MustPressStyle())
            .padding(.top, 24)
        }
    }

    private func tap(_ stop: DayStop) -> (() -> Void)? {
        guard let id = stop.placeId, places.contains(where: { $0.id == id }) else { return nil }
        return { router.push(.place(id: id), on: .hoje) }
    }

    private var broken: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                V8CornerButton(systemName: "chevron.left", label: "Voltar") { dismiss() }
                Spacer()
            }
            .padding(.top, 10)
            Text("Esse link não abriu.")
                .font(V8Font.display(28))
                .foregroundStyle(V8.ink)
                .padding(.top, 20)
            Text("O dia vai dentro do link: se ele chegou cortado (o WhatsApp às vezes corta), peça pra mandar de novo ou o cartaz.")
                .font(V8Font.text(15))
                .foregroundStyle(V8.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
