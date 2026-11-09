import SwiftData
import SwiftUI

/// Em cartaz (V9, `List` nativa, prompt 27 §1): o que está em cartaz na viagem — exposição, show, jogo — vindo do board,
/// de link/foto colados e do que o `ShowEventsProviding` já tem no aparelho. Leitura local: nada espera rede.
struct EmCartazView: View {
    @Environment(\.showEvents) private var showEvents
    @Environment(AppRouter.self) private var router
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
        let city = trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.displayName
        List {
            Section {
                Text("\(city) · \(sections.count) em cartaz na viagem")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Mostrar", selection: $filter) {
                    ForEach(EmCartazFilter.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            if sections.count == 0 { empty }
            if !sections.today.isEmpty {
                Section {
                    rows(sections.today)
                } header: {
                    Text("Hoje · \(DayText.weekdayShort(now, region: region)) \(region.dayNumber(now)) · \(sections.today.count)")
                }
            }
            if !sections.later.isEmpty {
                Section {
                    rows(sections.later)
                } header: {
                    Text("Dias seguintes · \(sections.later.count)")
                }
            }
            Section {
                Button { router.sheet = .addLink(url: nil, listId: nil) } label: { Label("Colar link", systemImage: "link") }
                Button { router.sheet = .ticketImport(inboxId: nil) } label: { Label("Foto do cartaz", systemImage: "camera") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Em cartaz")
        .navigationBarTitleDisplayMode(.large)
        .v9Screen(grouped: true)
        .accessibilityIdentifier("em-cartaz")
    }

    private var empty: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nada em cartaz.").font(.headline)
                Text("Cole o link da programação de um museu, casa de show ou estádio, ou fotografe o cartaz: o Must lê no aparelho.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Linhas

    @ViewBuilder private func rows(_ events: [ShowEvent]) -> some View {
        ForEach(events) { event in
            Button {
                if let id = event.placeId { router.push(.place(id: id)) }
            } label: {
                EmCartazRow(event: event, region: region, now: now, stacked: typeSize.isAccessibilitySize)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Uma linha da lista: nome, meta, origem e, à direita, o dia e a hora.
struct EmCartazRow: View {
    var event: ShowEvent
    var region: Region
    var now: Date
    var stacked = false

    var body: some View {
        let trailing = EmCartazModel.trailing(event, region: region, now: now)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.body.weight(.semibold)).lineLimit(3).multilineTextAlignment(.leading)
                Text(EmCartazModel.meta(event, region: region, now: now))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(stacked ? 4 : 2)
                Text(EmCartazModel.origin(event.source)).font(.footnote).foregroundStyle(.secondary)
                if stacked { trailingView(trailing).padding(.top, 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked { trailingView(trailing) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func trailingView(_ t: (top: String, bottom: String?)) -> some View {
        VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
            Text(t.top).font(.subheadline.weight(.semibold).monospacedDigit())
            if let bottom = t.bottom { Text(bottom).font(.footnote.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
