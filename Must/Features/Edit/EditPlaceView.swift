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

    private let placeId: String?
    private let newListId: String?
    private let prefillName: String?
    private let onSaved: ((Place) -> Void)?

    @State private var draft = PlaceDraft()
    @State private var loaded = false
    @State private var editingReservation = false
    @State private var editingTickets = false
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
    /// O lugar editado, lido pelo id no contexto desta árvore (rodada 23 · G): antes um `@Query` de todos os lugares
    /// (100+ no Japão) rodava a cada tecla só pra achar este. Lido só no abrir/salvar/apagar, nunca no `body`.
    private func existingPlace() -> Place? {
        guard let id = placeId else { return nil }
        return try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    nameFields
                    listPicker
                    cityAndPrice
                    areaField
                }
                Section { placesCard }
                Section { windowsPicker }
                if let kind = lists.first(where: { $0.id == draft.listId })?.kind, kind != .place {
                    Section(kindTitle(kind)) { KindExtraFields(kind: kind, extra: $draft.extra, region: region) }
                }
                Section { notesField }
                Section { sourcePicker }
                Section { locationRow }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if !isNew {
                    Section {
                        Button("Remover do board", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "Novo lugar" : "Editar lugar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save).accessibilityIdentifier("edit.save")
                }
            }
        }
        .v9Screen(grouped: true)
        .onAppear(perform: load)
        .sheet(isPresented: $editingReservation) {
            ReservationEditor(reservation: $draft.reservation, region: region)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $editingTickets) {
            TicketsEditor(tickets: $draft.tickets, sessions: draft.extra.sessions, region: region, placeName: draft.name)
        }
        .confirmationDialog("Remover \(draft.name) do board?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remover", role: .destructive, action: delete)
        } message: {
            Text("Os gastos ligados a ele ficam, sem o lugar.")
        }
    }

    private func kindTitle(_ kind: ListKind) -> String {
        switch kind {
        case .photo: "Foto"
        case .art: "Arte"
        case .sport: "Esporte"
        case .experience: "Experiência"
        case .place: "Lugar"
        }
    }

    // MARK: Seções

    @ViewBuilder private var nameFields: some View {
        field("Nome") {
            TextField("Nome do lugar", text: $draft.name).accessibilityIdentifier("edit.name")
        }
        field("Nome local · mostre ao atendente") {
            TextField("opcional", text: $draft.nameLocal).accessibilityIdentifier("edit.nameLocal")
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
        field("Lista") {
            FlowLayout(spacing: 8) {
                ForEach(listChoices, id: \.self) { choice in
                    let selected = draft.listId == choice.listId && draft.sub == choice.sub
                    Button {
                        draft.listId = choice.listId
                        draft.sub = choice.sub
                    } label: { V9Chip(choice.label, isOn: selected) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder private var cityAndPrice: some View {
        if let cities = trips.first?.cities, cities.count > 1 {
            field("Cidade") {
                FlowLayout(spacing: 8) {
                    ForEach(cities) { city in
                        Button { draft.cityId = city.id } label: {
                            V9Chip(trips.first?.label(for: city, region: region) ?? city.name, isOn: draft.cityId == city.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        field("Preço · \(region.currencySymbol)") {
            TextField("0", text: $draft.priceText).monospacedDigit().keyboardType(.decimalPad).accessibilityIdentifier("edit.price")
        }
    }

    private var areaField: some View {
        field("Bairro") {
            TextField("Savassi, Naka-Meguro…", text: $draft.area).accessibilityIdentifier("edit.area")
        }
    }

    @ViewBuilder private var placesCard: some View {
        Button {
            if draft.placeId != nil {
                draft.placeId = nil
                draft.hours = nil
                draft.placesOn = false
            } else {
                draft.placesOn.toggle()
            }
        } label: {
            infoRow("Google Places", subtitle: placesSubtitle,
                    value: draft.placeId != nil ? "ligado" : (draft.placesOn ? "pendente" : "desligado"))
        }
        .buttonStyle(.plain)
        Button { editingReservation = true } label: {
            infoRow("Reserva", subtitle: "vira âncora do dia",
                    value: draft.reservation.map { "\(region.shortDay($0.at)) \(region.timeString($0.at))" } ?? "nenhuma", chevron: true)
        }
        .buttonStyle(.plain)
        Button { editingTickets = true } label: {
            infoRow("Ingresso", subtitle: "PDF, QR ou código · vira âncora do dia",
                    value: draft.tickets.isEmpty ? "nenhum" : "\(draft.tickets.count)", chevron: true)
        }
        .buttonStyle(.plain)
        Toggle(isOn: $draft.saveForEnd) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fica pro fim")
                Text("só entra nos últimos dias da cidade").font(.footnote).foregroundStyle(.secondary)
            }
        }
        Toggle(isOn: $draft.allowBudgetException) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vale a exceção")
                Text("pode estourar o orçamento do dia").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ title: String, subtitle: String, value: String, chevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
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
        field("Melhor janela") {
            FlowLayout(spacing: 8) {
                ForEach(DayWindow.allCases) { window in
                    let on = draft.windows.contains(window)
                    Button {
                        if on { draft.windows.remove(window) } else { draft.windows.insert(window) }
                    } label: { V9Chip(window.label.capitalized, isOn: on) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var notesField: some View {
        field("Notas do board") {
            TextField("o que pedir, onde sentar, quando ir…", text: $draft.notes, axis: .vertical)
                .accessibilityIdentifier("edit.notes")
                .lineLimit(3...8)
        }
    }

    @ViewBuilder private var sourcePicker: some View {
        field("Fonte") {
            FlowLayout(spacing: 8) {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    Button { draft.sourceKind = kind } label: { V9Chip(kind.label, isOn: draft.sourceKind == kind) }
                        .buttonStyle(.borderless)
                }
            }
        }
        if draft.sourceKind != .board && draft.sourceKind != .manual {
            TextField("link", text: $draft.sourceURL)
                .accessibilityIdentifier("edit.link")
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder private var locationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Localização")
            Text(draft.approx ? "aproximada · resolve no Places" : "confirmada").font(.footnote).foregroundStyle(.secondary)
            Text(String(format: "%.5f, %.5f", draft.lat, draft.lng)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        Button("Usar minha posição") {
            if let c = services.location.current?.coordinate {
                draft.lat = c.latitude
                draft.lng = c.longitude
                draft.approx = false
            }
        }
        .disabled(services.location.current == nil)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        V9Field(label) { content() }
    }

    // MARK: Ações

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let place = existingPlace() {
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
        if let existing = existingPlace() {
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
        guard let existing = existingPlace() else { return }
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
    /// photo / art / sport / experience.
    var extra = PlaceExtra()
    /// Ingressos anexados (Editar lugar › Ingresso).
    var tickets: [Ticket] = []

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
        extra = place.extra ?? PlaceExtra()
        tickets = place.tickets
    }

    @MainActor
    func apply(to place: Place, name: String, list: MustList, region: Region) {
        place.name = name
        place.nameLocal = nameLocal.isEmpty ? nil : nameLocal
        place.list = list
        place.sub = sub
        place.cityId = cityId
        place.price = NumberInput.double(priceText.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
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
                              savedAt: sourceKind == .board ? sourceSavedAt : savedAt,
                              caption: place.source?.caption, author: place.source?.author)
        place.lat = lat
        place.lng = lng
        place.approx = approx
        // Guarda só o bloco do tipo da lista escolhida.
        var kept = PlaceExtra()
        switch list.kind {
        case .photo: kept.photo = extra.photo
        case .art: kept.art = extra.art
        case .sport: kept.sport = extra.sport
        case .experience: kept.experience = extra.experience
        case .place: kept = extra
        }
        place.extra = kept
        // Ingresso anexado a uma sessão marca a sessão como comprada (âncora).
        place.tickets = tickets
        place.syncBoughtSessions()
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
        NavigationStack {
            Form {
                Section {
                    DatePicker("Quando", selection: $at)
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                    Stepper("Pessoas: \(party)", value: $party, in: 1...12)
                    TextField("Nota: confirmado por e-mail, pede pontualidade…", text: $note)
                }
                if reservation != nil {
                    Section {
                        Button("Remover reserva", role: .destructive) { reservation = nil; dismiss() }
                    }
                }
            }
            .navigationTitle("Reserva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") {
                        reservation = Reservation(at: at, party: party, note: note.isEmpty ? nil : note)
                        dismiss()
                    }
                }
            }
        }
        .v9Screen(grouped: true)
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
