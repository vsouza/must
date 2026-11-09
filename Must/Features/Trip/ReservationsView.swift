import SwiftData
import SwiftUI

/// Reservas: as âncoras da viagem — reservas e ingressos dos lugares e eventos sem lugar (trem, voo, dia inteiro).
struct ReservationsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query(sort: \TripEvent.at) private var events: [TripEvent]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var flights: [Flight]

    /// Dentro da agenda (Viagem › calendário): sem o botão voltar, que é da agenda.
    var embedded = false
    /// Toque num voo: a agenda troca pra aba Voos.
    var onFlight: (() -> Void)? = nil

    @State private var editing: EditTarget?

    private enum EditTarget: Identifiable {
        case new
        case event(TripEvent)
        var id: String { if case .event(let e) = self { e.id.uuidString } else { "new" } }
    }

    /// Uma linha: reserva de lugar ou evento.
    struct Item: Identifiable {
        var id: String
        var at: Date
        var title: String
        var meta: String
        var place: Place?
        var event: TripEvent?
        var done: Bool
        var allDay: Bool
        var weatherDependent: Bool
        var cityId: String?
        /// Ingresso anexado ao lugar (abre o Ingresso).
        var ticket: Ticket? = nil
        /// Trecho de voo (abre a aba Voos).
        var flightId: String? = nil
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    private var items: [Item] {
        let reserved = places.compactMap { p -> Item? in
            guard let r = p.reservation else { return nil }
            let party = r.party.map { "\($0) \($0 == 1 ? "pessoa" : "pessoas")" }
            let meta = [p.area, region.timeString(r.at), party, r.note].compactMap { $0 }.joined(separator: " · ")
            return Item(id: p.id, at: r.at, title: p.name, meta: meta, place: p, event: nil, done: p.isDone, allDay: false,
                        weatherDependent: NotesRules(notes: p.notes).weatherDependent, cityId: p.cityId)
        }
        let ticketed = places.flatMap { p in
            p.tickets.map { t -> Item in
                let meta = [p.area, region.timeString(t.at), t.confirmation.map { "conf. \($0)" }].compactMap { $0 }.joined(separator: " · ")
                return Item(id: "\(p.id)#\(t.id)", at: t.at, title: p.name, meta: meta, place: p, event: nil,
                            done: t.at < region.calendar.startOfDay(for: now), allDay: false, weatherDependent: false,
                            cityId: p.cityId, ticket: t)
            }
        }
        let evs = events.map { e in
            Item(id: e.id.uuidString, at: e.at, title: e.title,
                 meta: [e.allDay ? "sem hora" : region.timeString(e.at), e.note.isEmpty ? nil : e.note].compactMap { $0 }.joined(separator: " · "),
                 place: nil, event: e, done: e.at < region.calendar.startOfDay(for: now), allDay: e.allDay,
                 weatherDependent: e.weatherDependent, cityId: trips.first?.city(on: e.at, calendar: region.calendar)?.id)
        }
        let flown = flights.flatMap { f in
            f.legs.map { leg -> Item in
                let zone = FlightFormat.zone(leg.from, fallback: region.timeZone)
                let meta = [FlightFormat.time(leg.departsNow, zone: zone), leg.seat.map { "assento \($0)" }, f.pnr.isEmpty ? nil : "PNR \(f.pnr)"]
                    .compactMap { $0 }.joined(separator: " · ")
                return Item(id: "flight#\(leg.id)", at: leg.departsNow, title: "\(leg.number) · \(leg.routeLabel)", meta: meta,
                            place: nil, event: nil, done: leg.departsNow < region.calendar.startOfDay(for: now), allDay: false,
                            weatherDependent: false, cityId: nil, flightId: f.id)
            }
        }
        return (reserved + ticketed + evs + flown).sorted { $0.at < $1.at }
    }

    var body: some View {
        let all = items
        let next = all.first { !$0.done && ($0.allDay ? region.calendar.startOfDay(for: $0.at) >= region.calendar.startOfDay(for: now) : $0.at >= now) }
        List {
            Section {
                Text(all.count == 1 ? "1 marcada · o dia se monta em volta" : "\(all.count) marcadas · o dia se monta em volta")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { router.sheet = .ticketImport(inboxId: nil) } label: {
                    Label("Trazer ingresso (PDF, foto ou link)", systemImage: "ticket")
                }
                Button { editing = .new } label: { Label("Novo evento", systemImage: "plus") }
            }
            if let next {
                Section("Próxima · \(region.calendar.isDate(next.at, inSameDayAs: now) ? "hoje" : region.shortDay(next.at))") {
                    nextCard(next)
                }
            }
            if all.isEmpty {
                Section {
                    Text("Nada marcado ainda. Reserva de lugar entra pelo Editar lugar; trem, voo e passeio de dia inteiro, pelo Novo evento.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section(trips.first?.hasTrip == true ? "Âncoras da viagem" : "Âncoras do mês") {
                    ForEach(all) { item in
                        Button { open(item) } label: { row(item) }.foregroundStyle(.primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V9.groupedBackground)
        .navigationTitle(embedded ? "" : "Reservas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            switch target {
            case .new: EventEditor(event: nil, region: region)
            case .event(let e): EventEditor(event: e, region: region)
            }
        }
    }

    private func nextCard(_ item: Item) -> some View {
        let today = region.calendar.isDate(item.at, inSameDayAs: now)
        var parts = [item.meta]
        if let place = item.place, let here = services.location.current {
            let leg = DaySolver.leg(here.coordinate, place.coordinate, walkMax: settingsList.first?.walkMaxKm ?? 1.5)
            let leave = RoutesService.leaveAt(item.at, travelMinutes: leg.minutes)
            if leave > now, today { parts.append("saia \(region.timeString(leave))") }
        }
        return Button { open(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.headline).lineLimit(2)
                    Spacer()
                    if !item.allDay { Text(region.timeString(item.at)).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(V9.accent) }
                }
                Text(parts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(region.dayNumber(item.at)).font(.title2.weight(.semibold)).monospacedDigit()
                Text(region.monthShort(item.at)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(item.meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                tag(item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(item.done ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func tag(_ item: Item) -> some View {
        let cal = region.calendar
        let todayCity = trips.first?.city(on: now, calendar: cal)
        if item.done && item.place != nil {
            J9Tag(text: "feito")
        } else if cal.isDate(item.at, inSameDayAs: now) {
            J9Tag(text: "hoje", filled: true)
        } else if item.ticket != nil {
            J9Tag(text: "ingresso")
        } else if item.weatherDependent {
            J9Tag(text: "tempo")
        } else if let event = item.event {
            J9Tag(text: event.allDay ? "dia" : event.kind.tag)
        } else if let cityId = item.cityId, let city = trips.first?.city(id: cityId), city.name != todayCity?.name {
            J9Tag(text: city.name)
        } else if trips.first?.hasTrip == true {
            J9Tag(text: "viagem")
        }
    }

    private func open(_ item: Item) {
        if let place = item.place, let ticket = item.ticket { router.push(.ticket(placeId: place.id, ticketId: ticket.id), on: router.tab) }
        else if let place = item.place { router.push(.place(id: place.id), on: router.tab) }
        else if let event = item.event { editing = .event(event) }
        else if item.flightId != nil { onFlight?() }
    }
}

/// Novo evento / editar evento (sem lugar no board).
struct EventEditor: View {
    var event: TripEvent?
    var region: Region

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var at = AppClock.now
    @State private var kind: TripEventKind = .train
    @State private var note = ""
    @State private var allDay = false
    @State private var weatherDependent = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Shinkansen → Kyoto, Nara · dia inteiro…", text: $title)
                } header: { Text("O quê") }
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(TripEventKind.allCases.filter { $0 != .flight }) { k in Text(k.label.capitalized).tag(k) }
                    }
                    .onChange(of: kind) { _, k in if k == .dayTrip { allDay = true } }
                    Toggle(isOn: $allDay) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dia inteiro")
                            Text("sem hora marcada").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Quando", selection: $at, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                }
                Section("Nota") {
                    TextField("Nozomi 215 · vagão 8, ônibus 07:35…", text: $note, axis: .vertical)
                    Toggle(isOn: $weatherDependent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Depende do tempo")
                            Text("só vale com céu limpo").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if event != nil {
                    Section { Button("Remover evento", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(event == nil ? "Novo evento" : "Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .v9Screen(grouped: true)
            .scrollContentBackground(.hidden)
        }
        .onAppear(perform: load)
        .confirmationDialog("Remover \(title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remover", role: .destructive) {
                if let event { context.delete(event); try? context.save() }
                dismiss()
            }
        }
    }

    private func load() {
        guard let event else {
            at = region.calendar.date(byAdding: .hour, value: 9, to: region.calendar.startOfDay(for: AppClock.now)) ?? AppClock.now
            return
        }
        title = event.title
        at = event.at
        kind = event.kind
        note = event.note
        allDay = event.allDay
        weatherDependent = event.weatherDependent
    }

    private func save() {
        let date = allDay ? region.calendar.startOfDay(for: at) : at
        if let event {
            event.title = title
            event.at = date
            event.kind = kind
            event.note = note
            event.allDay = allDay
            event.weatherDependent = weatherDependent
        } else {
            context.insert(TripEvent(at: date, title: title, kind: kind, note: note, allDay: allDay, weatherDependent: weatherDependent))
        }
        try? context.save()
        dismiss()
    }
}
