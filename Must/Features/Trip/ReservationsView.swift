import SwiftData
import SwiftUI

/// Reservas: as âncoras da viagem — reservas dos lugares e eventos sem lugar (trem, voo, dia inteiro).
struct ReservationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query(sort: \TripEvent.at) private var events: [TripEvent]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

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
        let evs = events.map { e in
            Item(id: e.id.uuidString, at: e.at, title: e.title,
                 meta: [e.allDay ? "sem hora" : region.timeString(e.at), e.note.isEmpty ? nil : e.note].compactMap { $0 }.joined(separator: " · "),
                 place: nil, event: e, done: e.at < region.calendar.startOfDay(for: now), allDay: e.allDay,
                 weatherDependent: e.weatherDependent, cityId: trips.first?.city(on: e.at, calendar: region.calendar)?.id)
        }
        return (reserved + evs).sorted { $0.at < $1.at }
    }

    var body: some View {
        let all = items
        let next = all.first { !$0.done && ($0.allDay ? region.calendar.startOfDay(for: $0.at) >= region.calendar.startOfDay(for: now) : $0.at >= now) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconButton(.voltar, style: .glass, label: "Voltar") { dismiss() }
                    Spacer()
                    Micro(trips.first?.hasTrip == true ? "âncoras da viagem" : "âncoras do mês")
                    Spacer()
                    IconButton(.adicionar, style: .dark, label: "Novo evento") { editing = .new }
                }
                .padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reservas").mustTitle()
                    Text("o dia se monta em volta delas · \(all.count) \(all.count == 1 ? "marcada" : "marcadas")")
                        .mustSerif(18).foregroundStyle(Color.must.secondary)
                }
                .padding(.top, 22)

                if let next { nextCard(next).padding(.top, 22) }
                list(all).padding(.top, next == nil ? 22 : -14)
                if all.isEmpty {
                    Text("Nada marcado ainda. Reserva de lugar entra pelo Editar lugar; trem, voo e passeio de dia inteiro, pelo +.")
                        .mustMeta().padding(.top, 20)
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .custom([
                    Blob(cx: 350, cy: 140, rx: 100, ry: 70, rotation: -18, fill: .blue, opacity: 0.85),
                    Blob(cx: 0, cy: 250, rx: 60, ry: 45, rotation: 10, fill: .green),
                ]))
            }
            .ignoresSafeArea()
        }
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
                Micro("próxima · \(today ? "hoje" : region.shortDay(item.at))", color: .white.opacity(0.75))
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.must.archivo(24, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    if !item.allDay { Text(region.timeString(item.at)).font(.must.mono(26, .semibold)).foregroundStyle(.white) }
                }
                Text(parts.joined(separator: " · ")).font(.must.archivo(14)).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0x4C8DFF), Color.must.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .rotationEffect(.degrees(-1))
            .zIndex(1)
        }
        .buttonStyle(MustPressStyle())
    }

    private func list(_ all: [Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                Button { open(item) } label: { row(item) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, all.isEmpty ? 0 : 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Text(region.dayNumber(item.at)).font(.must.mono(24, .semibold)).foregroundStyle(Color.must.ink)
                Text(region.monthShort(item.at).uppercased()).font(.must.mono(10)).tracking(1).foregroundStyle(Color.must.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).mustPlace().lineLimit(1)
                Text(item.meta).mustMeta().lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            tag(item)
        }
        .padding(.vertical, 16)
        .opacity(item.done ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func tag(_ item: Item) -> some View {
        let cal = region.calendar
        let todayCity = trips.first?.city(on: now, calendar: cal)
        if item.done && item.place != nil {
            KanjiSeal(done: true, size: 30, look: .soft)
        } else if cal.isDate(item.at, inSameDayAs: now) {
            Tag("hoje", style: .dark)
        } else if item.weatherDependent {
            Tag("tempo", dot: Color.must.blue)
        } else if let event = item.event {
            Tag(event.allDay ? "dia" : event.kind.tag)
        } else if let cityId = item.cityId, let city = trips.first?.city(id: cityId), city.name != todayCity?.name {
            Tag(city.name)
        } else if trips.first?.hasTrip == true {
            Tag("viagem")
        }
    }

    private func open(_ item: Item) {
        if let place = item.place { router.push(.place(id: place.id), on: router.tab) }
        else if let event = item.event { editing = .event(event) }
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
        VStack(alignment: .leading, spacing: 18) {
            SheetHandle().frame(maxWidth: .infinity)
            HStack {
                Text(event == nil ? "Novo evento" : "Evento").mustTitle()
                Spacer()
                Button("Salvar", action: save)
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Capsule().fill(Color.must.ink))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("Shinkansen → Kyoto, Nara · dia inteiro…", text: $title)
                .font(.must.archivo(17))
                .padding(.horizontal, 16).frame(height: 52)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            FlowLayout(spacing: 8) {
                ForEach(TripEventKind.allCases) { k in
                    Button { kind = k; if k == .dayTrip { allDay = true } } label: { Pill(k.label.capitalized, isOn: kind == k, icon: k.icon) }
                        .buttonStyle(MustPressStyle())
                }
            }
            Toggle(isOn: $allDay) { FormRow("Dia inteiro", subtitle: "sem hora marcada") }.toggleStyle(.must)
            DatePicker("Quando", selection: $at, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                .font(.must.body).tint(Color.must.ink)
                .environment(\.timeZone, region.timeZone)
                .environment(\.locale, region.locale)
            TextField("nota (Nozomi 215 · vagão 8, ônibus 07:35…)", text: $note)
                .font(.must.archivo(15))
                .padding(.horizontal, 14).frame(height: 48)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Toggle(isOn: $weatherDependent) { FormRow("Depende do tempo", subtitle: "só vale com céu limpo") }.toggleStyle(.must)
            Spacer()
            if event != nil {
                GhostButton("Remover evento", icon: .remover) { confirmDelete = true }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Color.must.bg)
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
