import SwiftData
import SwiftUI

/// Reservas: as âncoras da viagem — reservas e ingressos dos lugares e eventos sem lugar (trem, voo, dia inteiro).
struct ReservationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.tripTheme) private var theme

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
        VStack(spacing: 0) {
            if !embedded {
                CutScreenHeader(title: "Reservas", corner: [trips.first?.hasTrip == true ? "âncoras da viagem" : "âncoras do mês"],
                                subtitle: "O dia se monta em volta delas", height: 200, onBack: { dismiss() }) {
                    CutCornerButton(systemName: "plus", label: "Novo evento", tint: theme.coverInk) { editing = .new }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        BigNumeral("\(all.count)", size: 64, color: V8.orange).fixedSize()
                        SpecLabel(all.count == 1 ? "marcada\no dia se monta em volta" : "marcadas\no dia se monta em volta")
                        Spacer(minLength: 8)
                        if embedded {
                            CutCornerButton(systemName: "plus", label: "Novo evento") { editing = .new }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { IndexRule() }

                    Button { router.sheet = .ticketImport(inboxId: nil) } label: {
                        CutRow(title: "Trazer ingresso", detail: "PDF, foto ou link") { CutValue(text: "abrir", chevron: true) }
                    }
                    .buttonStyle(.plain)

                    if let next { nextCard(next) }
                    list(all)
                    if all.isEmpty {
                        Text("Nada marcado ainda. Reserva de lugar entra pelo Editar lugar; trem, voo e passeio de dia inteiro, pelo +.")
                            .font(V8Font.text(14)).foregroundStyle(V8.mute).padding(20)
                    }
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("próxima · \(today ? "hoje" : region.shortDay(item.at))", size: 10, color: V8.ink)
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(V8Font.text(22, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                    Spacer()
                    if !item.allDay { Text(region.timeString(item.at)).font(V8Font.numeral(40)).foregroundStyle(V8.ink) }
                }
                Text(parts.joined(separator: " · ")).font(V8Font.text(14)).foregroundStyle(V8.ink.opacity(0.8)).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.orange)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func list(_ all: [Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(all) { item in
                Button { open(item) } label: { row(item) }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Text(region.dayNumber(item.at)).font(V8Font.numeral(34)).foregroundStyle(V8.ink)
                Text(region.monthShort(item.at).uppercased()).font(V8Font.mono(10)).tracking(1).foregroundStyle(V8.mute)
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                Text(item.meta).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            tag(item)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { IndexRule() }
        .opacity(item.done ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func tag(_ item: Item) -> some View {
        let cal = region.calendar
        let todayCity = trips.first?.city(on: now, calendar: cal)
        if item.done && item.place != nil {
            CutTag(text: "feito")
        } else if cal.isDate(item.at, inSameDayAs: now) {
            CutTag(text: "hoje", filled: true)
        } else if item.ticket != nil {
            CutTag(text: "ingresso")
        } else if item.weatherDependent {
            CutTag(text: "tempo")
        } else if let event = item.event {
            CutTag(text: event.allDay ? "dia" : event.kind.tag)
        } else if let cityId = item.cityId, let city = trips.first?.city(id: cityId), city.name != todayCity?.name {
            CutTag(text: city.name)
        } else if trips.first?.hasTrip == true {
            CutTag(text: "viagem")
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
        VStack(alignment: .leading, spacing: 0) {
            SheetHandle().frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(event == nil ? "Novo evento" : "Evento").font(V8Font.display(34)).tracking(-1).foregroundStyle(V8.ink)
                        Spacer()
                    }
                    CutField(label: "o quê", text: $title, placeholder: "Shinkansen → Kyoto, Nara · dia inteiro…")
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(TripEventKind.allCases.filter { $0 != .flight }) { k in
                            Button { kind = k; if k == .dayTrip { allDay = true } } label: { Pill(k.label.capitalized, isOn: kind == k, icon: k.icon) }
                                .buttonStyle(.plain)
                        }
                    }
                    Toggle(isOn: $allDay) { FormRow("Dia inteiro", subtitle: "sem hora marcada") }.toggleStyle(.must)
                    DatePicker("Quando", selection: $at, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        .font(V8Font.text(16)).tint(V8.orange)
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                    CutField(label: "nota", text: $note, placeholder: "Nozomi 215 · vagão 8, ônibus 07:35…")
                    Toggle(isOn: $weatherDependent) { FormRow("Depende do tempo", subtitle: "só vale com céu limpo") }.toggleStyle(.must)
                    if event != nil {
                        GhostButton("Remover evento", icon: .remover) { confirmDelete = true }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .background(V8.paper)
        .cutFooter("Salvar", enabled: !title.trimmingCharacters(in: .whitespaces).isEmpty, action: save)
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
