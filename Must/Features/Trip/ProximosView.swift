import SwiftData
import SwiftUI

/// 12 · Próximos (raiz da aba Viagem, prompt 23 §2, `Proximos.png`): tinta, só o que ainda vai acontecer, em ordem —
/// reserva (laranja), ingresso, trem e voo (papel) em `TicketCard`. Passou, some. Entrada pra Carteira e pro resto da
/// Viagem (voos, compras, mapas offline, gasto e dias). Tudo do aparelho: nenhuma chamada de rede.
struct ProximosView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Environment(\.tripTheme) private var theme

    @Query private var places: [Place]
    @Query private var events: [TripEvent]
    @Query(sort: \Flight.order) private var flights: [Flight]
    @Query private var trips: [TripInfo]
    @Query private var gifts: [Gift]

    private var region: Region { store.region }
    private var cal: Calendar { region.calendar }

    @Query private var people: [Companion]
    @Query private var polls: [PlacePoll]

    var body: some View {
        let now = AppClock.now
        let items = upcoming(now: now)
        List {
            Section {
                minhasViagens
                presentesLinha
            }
            Section {
                if items.isEmpty {
                    emptyRow
                } else {
                    ForEach(items) { item in
                        Button { open(item) } label: { ProximoCard(item: item, region: region, now: now, leave: leaveLine(item)) }
                            .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(items.isEmpty ? "Próximos" : "Próximos · \(items.count)")
            } footer: {
                Text("Só o que ainda vai acontecer. Passou, some.")
            }
            Section("Carteira") {
                link("Carteira", "cartões, passes, QR de entrada", "creditcard") { router.push(.carteira) }
                link("Voos e reservas", "status e checklist", "airplane") { router.push(.schedule(tab: .voos)) }
            }
            Section {
                link("SOS", "emergência, seguro, hospital, consulado", "cross.case.fill", alert: true) { router.push(.sos) }
            }
            Section("Viagem") {
                link("Mapas offline", "baixar a cidade no Wi-Fi", "map") { router.push(.offlineMaps) }
                link("Bolso", "regras locais, atalhos, dinheiro", "bag") { router.push(.bolso) }
                link("Coleção", "um card por lugar feito · mandar", "rectangle.stack") { router.push(.colecao) }
                link("Compras", "lista, cota e regras da volta", "cart") { router.push(.compras) }
                link("Gasto e dias", "orçamento e o que já foi gasto", "chart.pie") { router.push(.trip) }
                link("Mandar a viagem", "PDF um dia por página · cartaz · link", "square.and.arrow.up") { router.sheet = .mandar(date: nil) }
            }
            Section(people.isEmpty ? "Grupo · só você" : "Grupo · você + \(people.count)") {
                link("Pessoas", people.isEmpty ? "quem viaja com você" : people.prefix(3).map(\.name).joined(separator: ", "), "person.2") { router.push(.pessoas, on: router.tab) }
                link("Votar", polls.isEmpty ? "A ou B? entre dois lugares" : "\(polls.filter { $0.winner == nil }.count) sem vencedor", "hand.thumbsup") { router.push(.votar, on: router.tab) }
                link("Acertar contas", "dividir os gastos do grupo", "plusminus") { router.push(.acertar, on: router.tab) }
                link("Mandar o dia", "cartaz, link e PDF de hoje", "paperplane") { router.sheet = .mandar(date: cal.startOfDay(for: now)) }
            }
            Section {
                link("Ajustes", "região, dados, mapas, nuvem", "gearshape") { router.push(.settings) }
            }
        }
        .navigationTitle("Viagem")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .assistant } label: { Image(systemName: "sparkles") }.accessibilityLabel("Assistente")
            }
        }
        .v9Screen(grouped: true)
        #if DEBUG
        .task {
            if DebugFlags.string("debugScreen") == "proximos" { ProximosDemo.ensure(context: context, region: region) }
        }
        #endif
    }

    // MARK: Linhas

    /// Linha fixa do topo da aba: a viagem de agora com bandeira (única cor do país) e moeda; abre Minhas viagens.
    private var minhasViagens: some View {
        Button { router.sheet = .viagens } label: {
            HStack(spacing: 12) {
                TripFlag(theme, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minhas viagens").font(.body.weight(.semibold))
                    Text("\(region.displayName) · \(TripSwitcherModel.currencyLabel(region))")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Minhas viagens, \(region.displayName), moeda \(TripSwitcherModel.currencyLabel(region))")
    }

    /// "Presentes · 5 faltam de 6" abre a lista.
    private var presentesLinha: some View {
        let pending = GiftLogic.pendingCount(gifts) > 0
        return Button { router.push(.presentes) } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift").font(.title3).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Presentes").font(.body.weight(.semibold))
                    Text(GiftLogic.pendingOfText(gifts)).font(.subheadline).foregroundStyle(pending ? V9.accent : .secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Presentes, \(GiftLogic.pendingOfText(gifts))")
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nada marcado pela frente.").font(.headline)
            Text("Reserva, ingresso, trem e voo aparecem aqui em ordem, e somem quando passam.").font(.subheadline).foregroundStyle(.secondary)
            Button("Trazer ingresso") { router.sheet = .ticketImport(inboxId: nil) }.v9Primary()
        }
        .padding(.vertical, 4)
    }

    private func link(_ title: String, _ meta: String, _ icon: String, alert: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(alert ? V9.alert : .secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(alert ? V9.alert : .primary)
                    Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Dados

    private func upcoming(now: Date) -> [Proximos.Item] {
        var reservations: [Proximos.ReservationInput] = []
        var tickets: [Proximos.TicketInput] = []
        for place in places {
            if let r = place.reservation {
                reservations.append(.init(placeId: place.id, name: place.name, sub: place.sub, area: place.area, at: r.at,
                                          party: r.party, price: place.price, note: r.note))
            }
            for t in place.tickets {
                tickets.append(.init(placeId: place.id, ticketId: t.id, name: place.name, area: place.area, at: t.at, people: t.people,
                                     offline: t.qrPayload != nil || t.pdfName != nil, confirmation: t.confirmation))
            }
        }
        let evs = events.map { Proximos.EventInput(id: $0.id.uuidString, kind: $0.kind, title: $0.title, note: $0.note, at: $0.at, allDay: $0.allDay) }
        let fls = flights.map { f in
            Proximos.FlightInput(id: f.id, carrier: f.carrier, legs: f.legs, checklistDone: f.checklist.filter(\.done).count,
                                 checklistTotal: f.checklist.count, checkedKg: f.checkedKg)
        }
        return Proximos.items(now: now, reservations: reservations, tickets: tickets, events: evs, flights: fls,
                              money: { region.money($0) }, calendar: cal)
    }

    /// "saia de Shinjuku 18:25" quando a reserva está no dia de hoje (motor do dia).
    private func leaveLine(_ item: Proximos.Item) -> String? {
        guard item.kind == .reservation || item.kind == .ticket, let placeId = item.placeId, cal.isDate(item.at, inSameDayAs: AppClock.now),
              let plan = dayEngine.plan(for: cal.startOfDay(for: AppClock.now), region: region, context: context),
              let index = plan.stops.firstIndex(where: { $0.placeId == placeId }), index > 0 else { return nil }
        let stop = plan.stops[index]
        let previous = plan.stops[index - 1]
        let minutes = plan.leg(before: stop)?.minutes ?? 0
        let leave = stop.start.addingTimeInterval(-Double(minutes + 5) * 60)
        let from = previous.area.flatMap { id in AreaCatalog.areas(for: region).first { $0.id == id }?.name }
        return from.map { "saia de \($0) \(region.timeString(leave))" } ?? "saia às \(region.timeString(leave))"
    }

    private func open(_ item: Proximos.Item) {
        if let placeId = item.placeId, let ticketId = item.ticketId {
            router.push(.ticket(placeId: placeId, ticketId: ticketId))
        } else if let placeId = item.placeId {
            router.push(.place(id: placeId))
        } else if item.kind == .flight || item.kind == .train {
            router.push(.schedule(tab: .voos))
        }
    }
}

/// Um próximo (V9): tipo e dia, hora em dígitos tabulares, título e detalhe; reserva leva o ponto do acento.
struct ProximoCard: View {
    var item: Proximos.Item
    var region: Region
    var now: Date
    var leave: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(region.timeString(item.at))
                .font(.title2.weight(.semibold)).monospacedDigit()
                .fixedSize()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.kind == .reservation { Circle().fill(V9.accent).frame(width: 8, height: 8).accessibilityHidden(true) }
                    Text("\(item.kind.label.capitalizedFirst) · \(Proximos.dayLabel(item.at, now: now, calendar: region.calendar))")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                let detail = [item.route, item.detail, leave, item.corner].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
