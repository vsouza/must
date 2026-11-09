import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "Traz o seu board" — primeira abertura da região e Ajustes → Reimportar.
struct ImportView: View {
    enum Mode { case firstRun, reimport }

    var mode: Mode = .firstRun

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]

    @State private var showPicker = false
    @State private var fileName: String?
    @State private var resultText: String?
    @State private var errorText: String?
    @State private var editingTrip = false

    private var region: Region { store.region }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode == .firstRun ? "Primeiro uso · 1 de 2" : "Reimportar · \(region.shortName)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("O whiteboard vira listas; o Must cuida do resto.").font(.body).foregroundStyle(.secondary)
                    cards
                    form
                    Text("Tudo fica no iPhone · exporta de volta como .json quando quiser")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, V9.gutter)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Traz o seu board")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                J9Button(mode == .firstRun ? "Começar" : "Pronto") { finish() }
                    .padding(V9.gutter)
                    .background(.bar)
            }
            .v9Screen(grouped: true)
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.json]) { result in
            handlePicked(result)
        }
    }

    // MARK: Resumo

    private var resolvedCount: Int { places.filter { $0.placeId != nil && $0.hours != nil }.count }

    private var breakdown: String {
        lists.map { "\($0.name.capitalized) \($0.places.count)" }.joined(separator: " · ")
    }

    private var cards: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName.map { "\($0) · lido" } ?? "board.json · lido").font(.footnote).foregroundStyle(.secondary)
                Text("\(places.count) lugares em \(lists.count) listas").font(.title3.weight(.semibold))
                Text(breakdown).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            .v9Card(grouped: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Resolvidos no Google Places").font(.footnote).foregroundStyle(.secondary)
                Text("\(resolvedCount) com horário e preço").font(.title3.weight(.semibold))
                Text("\(places.count - resolvedCount) pendentes · resolve na 1ª sincronização")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            .v9Card(grouped: true)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Formulário

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            boardRow
            J9Divider()
            tripRows
            J9Divider()
            if let settings = settingsList.first {
                BudgetRow(settings: settings, region: region)
                J9Divider()
            }
            locationRow
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 2)
        .background(V9.groupedCard, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
    }

    private var boardRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            J9Row("Board", subtitle: fileName ?? "seed-\(region.rawValue).json · já está no app") {
                Button { showPicker = true } label: { J9Chip("Escolher .json") }
                    .buttonStyle(.plain)
            }
            if let resultText {
                Text(resultText).font(.footnote).foregroundStyle(Color.secondary).padding(.bottom, 10)
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Color.red).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private var tripRows: some View {
        if let trip = trips.first {
            TripRows(trip: trip, region: region, editing: $editingTrip)
        } else {
            J9Row("Viagem", subtitle: "sem viagem · dia a dia na cidade") { J9Value("—") }
        }
    }

    private var locationRow: some View {
        let location = services.location
        return J9Row("Localização", subtitle: "só enquanto usa · pra “perto de você”") {
            if location.isAuthorized {
                J9Tag(text: "permitido")
            } else if location.isDenied {
                J9Tag(text: "negado · Ajustes do iOS")
            } else {
                Button { location.requestAuthorization() } label: { J9Chip("Permitir", prominent: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Ações

    private func handlePicked(_ result: Result<URL, any Error>) {
        errorText = nil
        resultText = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let board = try BoardCodec.decode(Data(contentsOf: url))
            let summary = try BoardCodec(context: context, region: region).import(board: board, merge: true)
            fileName = url.lastPathComponent
            resultText = summary.description
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func finish() {
        try? context.save()
        if mode == .firstRun {
            store.markOnboarded()
            services.location.start()
        }
        dismiss()
    }
}

/// Orçamento por dia, editável no lugar.
private struct BudgetRow: View {
    @Bindable var settings: Settings
    var region: Region

    var body: some View {
        J9Row("Orçamento por dia", subtitle: "dá pra mudar a cada manhã") {
            HStack(spacing: 6) {
                Text(region.currencySymbol).font(J9.font(17, .semibold).monospacedDigit())
                TextField("0", value: $settings.perDayBudget,
                          format: .number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...2)))
                    .font(J9.font(17, .semibold).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
            }
            .foregroundStyle(Color.primary)
        }
    }
}

/// Viagem (datas editáveis) + cidades lidas do board.
private struct TripRows: View {
    @Bindable var trip: TripInfo
    var region: Region
    @Binding var editing: Bool

    var body: some View {
        if trip.hasTrip {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy) { editing.toggle() } } label: {
                    J9Row("Viagem", subtitle: "lida do board · toque pra editar") { J9Value(rangeLabel) }
                }
                .buttonStyle(.plain)
                if editing {
                    VStack(spacing: 8) {
                        DatePicker("Ida", selection: binding(\.start), displayedComponents: .date)
                        DatePicker("Volta", selection: binding(\.end), displayedComponents: .date)
                    }
                    .font(.body)
                    .tint(Color.primary)
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)
                    .padding(.bottom, 12)
                }
            }
        } else {
            J9Row("Viagem", subtitle: "sem viagem · dia a dia em \(trip.cities.first?.name ?? region.displayName)") {
                J9Value("—")
            }
        }
        J9Divider()
        VStack(alignment: .leading, spacing: 0) {
            J9Row("Cidades", subtitle: trip.hasTrip ? "na ordem da viagem" : "cidade de casa")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(trip.cities.enumerated()), id: \.element.id) { index, city in
                        J9Chip(cityLabel(city), isOn: index == 0)
                    }
                }
            }
            .padding(.top, -4)
            .padding(.bottom, 14)
        }
    }

    private var rangeLabel: String {
        guard let start = trip.start, let end = trip.end else { return "—" }
        return "\(region.dayNumber(start)) → \(region.dayNumber(end)) \(region.monthShort(end))"
    }

    private func cityLabel(_ city: City) -> String {
        guard let from = city.from, let to = city.to else { return city.name }
        return "\(city.name) \(region.dayNumber(from))–\(region.dayNumber(to))"
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<TripInfo, Date?>) -> Binding<Date> {
        Binding(get: { trip[keyPath: keyPath] ?? AppClock.now }, set: { trip[keyPath: keyPath] = $0 })
    }
}
