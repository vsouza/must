import CoreLocation
import SwiftData
import SwiftUI

/// Editar lugar (e "Novo lugar" à mão). Edita um rascunho; só grava em "Salvar".
struct EditPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var trips: [TripInfo]
    @Query private var allPlaces: [Place]

    private let placeId: String?
    private let newListId: String?
    private let prefillName: String?
    private let onSaved: ((Place) -> Void)?

    @State private var draft = PlaceDraft()
    @State private var loaded = false
    @State private var editingReservation = false
    @State private var confirmDelete = false
    @State private var error: String?

    /// Editar um lugar existente.
    init(placeId: String) {
        self.placeId = placeId
        self.newListId = nil
        self.prefillName = nil
        self.onSaved = nil
    }

    /// Novo lugar à mão, já numa lista.
    init(newInListId listId: String?, prefillName: String? = nil, onSaved: ((Place) -> Void)? = nil) {
        self.placeId = nil
        self.newListId = listId
        self.prefillName = prefillName
        self.onSaved = onSaved
    }

    private var region: Region { store.region }
    private var isNew: Bool { placeId == nil }
    private var existing: Place? { placeId.flatMap { id in allPlaces.first { $0.id == id } } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([Blob(cx: 345, cy: 105, rx: 95, ry: 62, rotation: -18, fill: .blue)]))

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    topBar
                    nameFields
                    listPicker
                    cityAndPrice
                    areaField
                    placesCard
                    windowsPicker
                    notesField
                    sourcePicker
                    locationRow
                    if let error {
                        Text(error).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
                    }
                    if !isNew {
                        Button { confirmDelete = true } label: {
                            Text("Remover do board")
                                .font(.must.archivo(15, .semibold))
                                .foregroundStyle(Color(hex: 0xC2261D))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Capsule().fill(.white))
                                .overlay(Capsule().strokeBorder(Color(hex: 0xF1C9C6)))
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear(perform: load)
        .sheet(isPresented: $editingReservation) {
            ReservationEditor(reservation: $draft.reservation, region: region)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Remover \(draft.name) do board?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remover", role: .destructive, action: delete)
        } message: {
            Text("Os gastos ligados a ele ficam, sem o lugar.")
        }
    }

    // MARK: Seções

    private var topBar: some View {
        HStack {
            IconButton(.fechar, style: .glass, label: "Fechar") { dismiss() }
            Spacer()
            Micro(isNew ? "novo lugar" : "editar lugar")
            Spacer()
            Button(action: save) {
                Text("Salvar")
                    .font(.must.archivo(15, .semibold))
                    .underline()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
        }
        .padding(.top, 16)
    }

    private var nameFields: some View {
        HStack(alignment: .top, spacing: 10) {
            field("nome") {
                TextField("Nome do lugar", text: $draft.name).font(.must.archivo(17))
            }
            field("日本語 · local") {
                TextField("opcional", text: $draft.nameLocal).font(.must.kanji(17, bold: false))
            }
            .frame(width: 130)
        }
    }

    private struct ListChoice: Hashable { var listId: String; var sub: String?; var label: String }

    private var listChoices: [ListChoice] {
        lists.flatMap { list -> [ListChoice] in
            let name = list.name.capitalized
            if list.subs.isEmpty { return [ListChoice(listId: list.id, sub: nil, label: name)] }
            return list.subs.map { ListChoice(listId: list.id, sub: $0, label: "\(name) · \($0)") }
                + [ListChoice(listId: list.id, sub: nil, label: name)]
        }
    }

    private var listPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("lista")
            FlowLayout(spacing: 8) {
                ForEach(listChoices, id: \.self) { choice in
                    let selected = draft.listId == choice.listId && draft.sub == choice.sub
                    Button {
                        draft.listId = choice.listId
                        draft.sub = choice.sub
                    } label: { Pill(choice.label, style: selected ? .green : .default) }
                        .buttonStyle(MustPressStyle())
                }
            }
        }
    }

    private var cityAndPrice: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Micro("cidade")
                FlowLayout(spacing: 8) {
                    ForEach(trips.first?.cities ?? []) { city in
                        Button { draft.cityId = city.id } label: {
                            Pill(trips.first?.label(for: city, region: region) ?? city.name, isOn: draft.cityId == city.id)
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
            }
            field("preço · \(region.currencySymbol)") {
                TextField("0", text: $draft.priceText).font(.must.mono(17)).keyboardType(.decimalPad)
            }
            .frame(width: 130)
        }
    }

    private var areaField: some View {
        field("bairro") {
            TextField("Savassi, Naka-Meguro…", text: $draft.area).font(.must.archivo(17))
        }
    }

    private var placesCard: some View {
        FormSection {
            Button {
                if draft.placeId != nil {
                    draft.placeId = nil
                    draft.hours = nil
                    draft.placesOn = false
                } else {
                    draft.placesOn.toggle()
                }
            } label: {
                FormRow("Google Places", subtitle: placesSubtitle) {
                    StatusChip(text: draft.placeId != nil ? "ligado" : (draft.placesOn ? "pendente" : "desligado"),
                               on: draft.placeId != nil)
                }
            }
            .buttonStyle(.plain)
            RowDivider()
            Button { editingReservation = true } label: {
                FormRow("Reserva", subtitle: "vira âncora do dia") {
                    MonoValue(draft.reservation.map {
                        "\(region.shortDay($0.at)) \(region.timeString($0.at))"
                    } ?? "nenhuma", chevron: true)
                }
            }
            .buttonStyle(.plain)
            RowDivider()
            Toggle(isOn: $draft.saveForEnd) {
                FormRow("Fica pro fim", subtitle: "só entra nos últimos dias da cidade")
            }
            .toggleStyle(.must)
            RowDivider()
            Toggle(isOn: $draft.allowBudgetException) {
                FormRow("Vale a exceção", subtitle: "pode estourar o orçamento do dia")
            }
            .toggleStyle(.must)
        }
    }

    private var placesSubtitle: String {
        if let id = draft.placeId {
            let short = id.count > 9 ? "\(id.prefix(4))…\(id.suffix(3))" : id
            let tz = region.timeZone
            let hours = draft.hours.flatMap { $0.todayText(AppClock.now, timeZone: tz) } ?? "sem horário em cache"
            let closed = draft.hours?.closedDays.isEmpty == false ? " · fecha \(draft.hours!.closedDays.joined(separator: ", "))" : ""
            return "\(short) · \(hours)\(closed)"
        }
        return draft.placesOn ? "resolve na próxima sincronização" : "sem placeId · horário e preço ficam de fora"
    }

    private var windowsPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("melhor janela")
            FlowLayout(spacing: 8) {
                ForEach(DayWindow.allCases) { window in
                    let on = draft.windows.contains(window)
                    Button {
                        if on { draft.windows.remove(window) } else { draft.windows.insert(window) }
                    } label: { Pill(window.label.capitalized, isOn: on) }
                        .buttonStyle(MustPressStyle())
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("notas do board")
            TextField("o que pedir, onde sentar, quando ir…", text: $draft.notes, axis: .vertical)
                .font(.must.serif(19))
                .lineLimit(3...8)
                .padding(16)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("fonte")
            FlowLayout(spacing: 8) {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    Button { draft.sourceKind = kind } label: { Pill(kind.label, isOn: draft.sourceKind == kind) }
                        .buttonStyle(MustPressStyle())
                }
            }
            if draft.sourceKind != .board && draft.sourceKind != .manual {
                TextField("link", text: $draft.sourceURL)
                    .font(.must.mono(14))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var locationRow: some View {
        FormSection {
            FormRow("Localização", subtitle: draft.approx ? "aproximada · resolve no Places" : "confirmada") {
                Button {
                    if let c = services.location.current?.coordinate {
                        draft.lat = c.latitude
                        draft.lng = c.longitude
                        draft.approx = false
                    }
                } label: { Pill("Usar minha posição", icon: .voceGps) }
                    .buttonStyle(MustPressStyle())
                    .disabled(services.location.current == nil)
            }
            Text(String(format: "%.5f, %.5f", draft.lat, draft.lng))
                .font(.must.mono(12))
                .foregroundStyle(Color.must.secondary)
                .padding(.bottom, 12)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro(label)
            content()
                .foregroundStyle(Color.must.ink)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: Ações

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let place = existing {
            draft = PlaceDraft(place: place, region: region)
        } else {
            let now = AppClock.now
            let city = trips.first?.city(on: now, calendar: region.calendar)
            draft.name = prefillName ?? ""
            draft.listId = newListId ?? lists.first?.id
            draft.cityId = city?.id ?? trips.first?.cities.first?.id ?? region.rawValue
            draft.sourceKind = .manual
            // Posição atual se estiver na cidade; senão o centro da cidade (aproximado).
            let center = CLLocation(latitude: city?.lat ?? region.defaultCenter.latitude, longitude: city?.lng ?? region.defaultCenter.longitude)
            if let here = services.location.current, here.distance(from: center) < 40_000 {
                draft.lat = here.coordinate.latitude
                draft.lng = here.coordinate.longitude
            } else {
                draft.lat = center.coordinate.latitude
                draft.lng = center.coordinate.longitude
            }
            draft.approx = true
        }
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Dá um nome pro lugar."; return }
        guard let listId = draft.listId, let list = lists.first(where: { $0.id == listId }) else { error = "Escolhe uma lista."; return }

        let place: Place
        if let existing {
            place = existing
        } else {
            place = Place(id: "m-\(UUID().uuidString.prefix(8).lowercased())", name: name, cityId: draft.cityId)
            context.insert(place)
        }
        draft.apply(to: place, name: name, list: list, region: region)
        do {
            try context.save()
            Log.data.info("\(isNew ? "novo" : "editado", privacy: .public) \(place.id, privacy: .public)")
            onSaved?(place)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() {
        guard let existing else { return }
        context.delete(existing)
        try? context.save()
        dismiss()
    }
}

/// Rascunho editável de um `Place`.
struct PlaceDraft {
    var name = ""
    var nameLocal = ""
    var listId: String?
    var sub: String?
    var cityId = ""
    var priceText = ""
    var area = ""
    var placeId: String?
    var hours: PlaceHours?
    var placesOn = false
    var reservation: Reservation?
    var saveForEnd = false
    var allowBudgetException = false
    var windows: Set<DayWindow> = []
    var notes = ""
    var sourceKind: SourceKind = .board
    var sourceURL = ""
    var sourceSavedAt: String?
    var lat: Double = 0
    var lng: Double = 0
    var approx = true

    init() {}

    init(place: Place, region: Region) {
        name = place.name
        nameLocal = place.nameLocal ?? ""
        listId = place.list?.id
        sub = place.sub
        cityId = place.cityId
        priceText = place.price.map { region.money($0, symbol: false) } ?? ""
        area = place.area ?? ""
        placeId = place.placeId
        hours = place.hours
        placesOn = place.placeId != nil
        reservation = place.reservation
        saveForEnd = place.saveForEnd
        allowBudgetException = place.allowBudgetException
        windows = Set(place.windows)
        notes = place.notes
        sourceKind = place.source?.kind ?? .board
        sourceURL = place.source?.url ?? ""
        sourceSavedAt = place.source?.savedAt
        lat = place.lat
        lng = place.lng
        approx = place.approx
    }

    @MainActor
    func apply(to place: Place, name: String, list: MustList, region: Region) {
        place.name = name
        place.nameLocal = nameLocal.isEmpty ? nil : nameLocal
        place.list = list
        place.sub = sub
        place.cityId = cityId
        place.price = Double(priceText.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        place.area = area.isEmpty ? nil : area
        place.placeId = placeId
        place.hours = placeId == nil ? nil : hours
        place.reservation = reservation
        place.saveForEnd = saveForEnd
        place.allowBudgetException = allowBudgetException
        place.windows = DayWindow.allCases.filter { windows.contains($0) }
        place.notes = notes
        let savedAt = sourceSavedAt ?? BoardDates(timeZone: region.timeZone).dayString(AppClock.now)
        place.source = Source(kind: sourceKind, url: sourceURL.isEmpty ? nil : sourceURL,
                              savedAt: sourceKind == .board ? sourceSavedAt : savedAt)
        place.lat = lat
        place.lng = lng
        place.approx = approx
    }
}

/// Data/hora, pessoas e nota da reserva.
struct ReservationEditor: View {
    @Binding var reservation: Reservation?
    var region: Region
    @Environment(\.dismiss) private var dismiss

    @State private var at = AppClock.now
    @State private var party = 2
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHandle().frame(maxWidth: .infinity)
            Text("Reserva").mustTitle()
            DatePicker("Quando", selection: $at)
                .font(.must.body)
                .tint(Color.must.ink)
                .environment(\.timeZone, region.timeZone)
                .environment(\.locale, region.locale)
            Stepper(value: $party, in: 1...12) {
                HStack {
                    Text("Pessoas").mustBody()
                    Spacer()
                    Text("\(party)").font(.must.mono(15))
                }
            }
            TextField("nota (confirmado por e-mail, pede pontualidade…)", text: $note)
                .font(.must.archivo(15))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
            HStack(spacing: 10) {
                if reservation != nil {
                    GhostButton("Remover reserva") { reservation = nil; dismiss() }
                }
                PrimaryButton("Pronto", style: .dark) {
                    reservation = Reservation(at: at, party: party, note: note.isEmpty ? nil : note)
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .onAppear {
            if let r = reservation {
                at = r.at
                party = r.party ?? 2
                note = r.note ?? ""
            } else {
                // Padrão: hoje 19:00 no fuso da região.
                let start = region.calendar.startOfDay(for: AppClock.now)
                at = region.calendar.date(byAdding: .hour, value: 19, to: start) ?? AppClock.now
            }
        }
    }
}
