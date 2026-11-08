import SwiftData
import SwiftUI

/// Em cartaz (`EmCartaz.png`, prompt 27 §1): o que está em cartaz na viagem — exposição, show, jogo — vindo do board,
/// de link/foto colados e do que o `ShowEventsProviding` já tem no aparelho. Leitura local: nada espera rede.
struct EmCartazView: View {
    @Environment(\.showEvents) private var showEvents
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var trips: [TripInfo]

    @State private var filter: EmCartazFilter = .trip

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    private var sections: EmCartazSections {
        let provider = EmCartazProvider.resolve(showEvents)
        return EmCartazModel.sections(today: provider.today(region: region, at: now),
                                      upcoming: provider.upcoming(region: region, from: now, days: 120),
                                      filter: filter, now: now, calendar: region.calendar)
    }

    var body: some View {
        let sections = sections
        let total = EmCartazModel.sections(today: sections.today, upcoming: sections.later, filter: .trip, now: now,
                                           calendar: region.calendar)
        let counts = EmCartazModel.headerCounts(total)
        VStack(spacing: 0) {
            header(counts: counts)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        BigNumeral("\(sections.count)", size: 74, color: V8.orange).fixedSize()
                        SpecLabel("em cartaz\nna viagem")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Em cartaz: \(sections.count)")
                    filters.padding(.horizontal, 20).padding(.vertical, 16)
                    IndexRule()
                    if sections.count == 0 { empty }
                    if !sections.today.isEmpty {
                        sectionTitle("Hoje", trailing: "\(DayText.weekdayShort(now, region: region)) \(region.dayNumber(now)) · \(sections.today.count)")
                        rows(sections.today, startAt: 1)
                    }
                    if !sections.later.isEmpty {
                        sectionTitle("Dias seguintes", trailing: "\(sections.later.count)")
                        rows(sections.later, startAt: sections.today.count + 1)
                    }
                    Color.clear.frame(height: 190)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .accessibilityIdentifier("em-cartaz")
    }

    // MARK: Cabeçalho

    private func header(counts: (left: String, right: String)) -> some View {
        let city = trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.displayName
        return CutScreenHeader(title: "Em cartaz",
                               corner: ["\(city) · \(DayText.weekdayShort(now, region: region)) \(region.shortDay(now))", counts.left, counts.right]
                                   .filter { !$0.isEmpty },
                               height: 210, onBack: { dismiss() })
    }

    private var filters: some View {
        V8FilterRow(items: EmCartazFilter.allCases.map { .init(id: $0.rawValue, title: $0.title, on: $0 == filter) }) { id in
            if let f = EmCartazFilter(rawValue: id) { filter = f }
        }
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(V8Font.display(26)).tracking(-0.8).foregroundStyle(V8.paper)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            SpecLabel(trailing, color: V8.muteDark)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(V8.ink)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nada em cartaz.").font(V8Font.display(28)).foregroundStyle(V8.ink)
            Text("Cole o link da programação de um museu, casa de show ou estádio, ou fotografe o cartaz: o Must lê no aparelho.")
                .font(V8Font.text(15)).foregroundStyle(V8.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    // MARK: Linhas

    private func rows(_ events: [ShowEvent], startAt: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { offset, event in
                Button {
                    if let id = event.placeId { router.push(.place(id: id)) }
                } label: {
                    EmCartazRow(index: startAt + offset, event: event, region: region, now: now,
                                stacked: typeSize.isAccessibilitySize)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Rodapé

    private var footer: some View {
        // Dois botões de ponta a ponta no pé: laranja (colar link) e tinta (foto do cartaz), régua de tinta em cima.
        // TODO(r23:A): quando o leitor de cartaz (Vision + EventExtractor) tiver fluxo próprio, apontar pra ele;
        // até lá o atalho abre o leitor de ingresso (câmera/Fotos), que já faz OCR no aparelho.
        HStack(spacing: 0) {
            footerButton("Colar link", fill: V8.orange, ink: V8.ink) { router.sheet = .addLink(url: nil, listId: nil) }
            footerButton("Foto do cartaz", fill: V8.ink, ink: V8.paper) { router.sheet = .ticketImport(inboxId: nil) }
        }
        .padding(.bottom, 82) // acima da barra v8
        .background(V8.paper.ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
    }

    private func footerButton(_ title: String, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(V8Font.mono(12, weight: .semibold)).tracking(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(fill)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Uma linha da lista: índice, nome, meta, origem e, à direita, o dia e a hora.
struct EmCartazRow: View {
    var index: Int
    var event: ShowEvent
    var region: Region
    var now: Date
    var stacked = false

    var body: some View {
        let trailing = EmCartazModel.trailing(event, region: region, now: now)
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(Font(V8Fonts.bricolage(30, weight: 800, width: 80, opticalSize: 96)))
                .tracking(-1.2)
                .foregroundStyle(V8.orangeDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 34, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(V8Font.text(17, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(V8.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(EmCartazModel.meta(event, region: region, now: now))
                    .font(V8Font.text(13))
                    .foregroundStyle(V8.mute)
                    .lineLimit(stacked ? 3 : 1)
                    .truncationMode(.tail)
                CutTag(text: EmCartazModel.origin(event.source)).padding(.top, 4)
                if stacked { trailingView(trailing).padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked { trailingView(trailing) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { IndexRule() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func trailingView(_ t: (top: String, bottom: String?)) -> some View {
        VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
            Text(t.top.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(0.8).foregroundStyle(V8.ink)
            if let bottom = t.bottom { Text(bottom).font(V8Font.mono(11, weight: .medium)).foregroundStyle(V8.mute) }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
