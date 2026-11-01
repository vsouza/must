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
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 360, cy: 262, rx: 125, ry: 78, rotation: -8, fill: .green),
                Blob(cx: 10, cy: 470, rx: 100, ry: 62, rotation: 14, fill: .sky),
            ]))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    cards
                        .padding(.top, 34)
                    form
                        .padding(.top, -22)
                    Text("Tudo fica no iPhone · exporta de volta como .json quando quiser")
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(mode == .firstRun ? "Começar" : "Pronto", icon: .avancar, iconTrailing: true) { finish() }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 8)
                .background {
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.96), .white],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.json]) { result in
            handlePicked(result)
        }
    }

    // MARK: Topo

    private var header: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                ZStack {
                    Circle().fill(Color.must.ink)
                    Text("済").font(.must.kanji(15)).foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                Spacer()
                Micro(mode == .firstRun ? "primeiro uso · 1 de 2" : "reimportar · \(region.shortName)")
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Traz o seu board").mustTitle()
                Text("o whiteboard vira listas; o Must cuida do resto")
                    .mustSerif(18)
                    .foregroundStyle(Color.must.secondary)
            }
        }
    }

    // MARK: Cards empilhados

    private var resolvedCount: Int { places.filter { $0.placeId != nil && $0.hours != nil }.count }

    private var breakdown: String {
        lists.map { "\($0.name.capitalized) \($0.places.count)" }.joined(separator: " · ")
    }

    private var cards: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                Micro(fileName.map { "\($0) · lido" } ?? "board.json · lido", color: MustColor.eat.text)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    MonoNumber("\(places.count)", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("lugares em \(lists.count) listas").font(.must.archivo(19, .semibold))
                        Text(breakdown).font(.must.archivo(13)).lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160, alignment: .top)
            .stackCard(color: .eat, rotation: -2)
            .padding(.leading, 56)
            .padding(.trailing, -40)

            VStack(alignment: .leading, spacing: 8) {
                Micro("resolvidos no Google Places", color: MustColor.drink.text)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    MonoNumber("\(resolvedCount)", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("com horário e preço").font(.must.archivo(19, .semibold))
                        Text("\(places.count - resolvedCount) pendentes · resolve na 1ª sincronização")
                            .font(.must.archivo(13)).lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 140, alignment: .top)
            .stackCard(color: .drink, rotation: 1.2)
            .padding(.trailing, -20)
            .offset(y: 132)
        }
        .frame(height: 290, alignment: .top)
    }

    // MARK: Formulário

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            boardRow
            RowDivider()
            tripRows
            RowDivider()
            if let settings = settingsList.first {
                BudgetRow(settings: settings, region: region)
                RowDivider()
            }
            locationRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .glass(cornerRadius: 26)
    }

    private var boardRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormRow("Board", subtitle: fileName ?? "seed-\(region.rawValue).json · já está no app") {
                Button { showPicker = true } label: { Pill("Escolher .json") }
                    .buttonStyle(MustPressStyle())
            }
            if let resultText {
                Text(resultText).font(.must.meta).foregroundStyle(MustColor.eat.text).padding(.bottom, 10)
            }
            if let errorText {
                Text(errorText).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D)).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private var tripRows: some View {
        if let trip = trips.first {
            TripRows(trip: trip, region: region, editing: $editingTrip)
        } else {
            FormRow("Viagem", subtitle: "sem viagem · dia a dia na cidade") { MonoValue("—") }
        }
    }

    private var locationRow: some View {
        let location = services.location
        return FormRow("Localização", subtitle: "só enquanto usa · pra “perto de você”") {
            if location.isAuthorized {
                Tag("permitido", dot: Color.must.green)
            } else if location.isDenied {
                Tag("negado · Ajustes do iOS", dot: Color(hex: 0xC2261D))
            } else {
                Button { location.requestAuthorization() } label: { Pill("Permitir", style: .green) }
                    .buttonStyle(MustPressStyle())
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
        FormRow("Orçamento por dia", subtitle: "dá pra mudar a cada manhã") {
            HStack(spacing: 6) {
                Text(region.currencySymbol).font(.must.mono(17, .semibold))
                TextField("0", value: $settings.perDayBudget,
                          format: .number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...2)))
                    .font(.must.mono(17, .semibold))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
            }
            .foregroundStyle(Color.must.ink)
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
                    FormRow("Viagem", subtitle: "lida do board · toque pra editar") { MonoValue(rangeLabel) }
                }
                .buttonStyle(.plain)
                if editing {
                    VStack(spacing: 8) {
                        DatePicker("Ida", selection: binding(\.start), displayedComponents: .date)
                        DatePicker("Volta", selection: binding(\.end), displayedComponents: .date)
                    }
                    .font(.must.body)
                    .tint(Color.must.ink)
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)
                    .padding(.bottom, 12)
                }
            }
        } else {
            FormRow("Viagem", subtitle: "sem viagem · dia a dia em \(trip.cities.first?.name ?? region.displayName)") {
                MonoValue("—")
            }
        }
        RowDivider()
        VStack(alignment: .leading, spacing: 0) {
            FormRow("Cidades", subtitle: trip.hasTrip ? "na ordem da viagem" : "cidade de casa")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(trip.cities.enumerated()), id: \.element.id) { index, city in
                        Pill(cityLabel(city), isOn: index == 0)
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
