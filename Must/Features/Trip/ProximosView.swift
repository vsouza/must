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
        VStack(spacing: 0) {
        CutScreenHeader(title: "Viagem", corner: [region.displayName, items.isEmpty ? "nada pela frente" : "\(items.count) próximos"], height: 160) {
                    CutCornerButton(systemName: "sparkles", label: "Assistente", tint: theme.coverInk) { router.sheet = .assistant }
                }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                minhasViagens
                presentesLinha
                CutSection(label: items.isEmpty ? "Próximos" : "Próximos · \(items.count)", trailing: "passou, some", inset: false) {
                    if items.isEmpty {
                        emptyRow
                    } else {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                Button { open(item) } label: { ProximoCard(item: item, region: region, now: now, leave: leaveLine(item)) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .overlay(alignment: .top) { IndexRule() }
                    }
                }
                CutSection(label: "Carteira", inset: false) {
                    VStack(spacing: 0) {
                        link("Carteira", "cartões, passes, QR de entrada") { router.push(.carteira) }
                        link("Voos e reservas", "status e checklist") { router.push(.schedule(tab: .voos)) }
                    }
                }
                CutSection(label: "Emergência", inset: false) {
                    link("SOS", "emergência, seguro, hospital, consulado", alert: true) { router.push(.sos) }
                }
                CutSection(label: "Viagem", inset: false) {
                    VStack(spacing: 0) {
                        link("Mapas offline", "baixar a cidade no Wi-Fi") { router.push(.offlineMaps) }
                        link("Bolso", "regras locais, atalhos, dinheiro") { router.push(.bolso) }
                        link("Coleção", "um card por lugar feito · mandar") { router.push(.colecao) }
                        link("Compras", "lista, cota e regras da volta") { router.push(.compras) }
                        link("Gasto e dias", "orçamento e o que já foi gasto") { router.push(.trip) }
                        link("Mandar a viagem", "PDF um dia por página · cartaz · link") { router.sheet = .mandar(date: nil) }
                    }
                }
                CutSection(label: people.isEmpty ? "Grupo · só você" : "Grupo · você + \(people.count)", inset: false) {
                    VStack(spacing: 0) {
                        link("Pessoas", people.isEmpty ? "quem viaja com você" : people.prefix(3).map(\.name).joined(separator: ", ")) { router.push(.pessoas, on: router.tab) }
                        link("Votar", polls.isEmpty ? "A ou B? entre dois lugares" : "\(polls.filter { $0.winner == nil }.count) sem vencedor") { router.push(.votar, on: router.tab) }
                        link("Acertar contas", "dividir os gastos do grupo") { router.push(.acertar, on: router.tab) }
                        link("Mandar o dia", "cartaz, link e PDF de hoje") { router.sheet = .mandar(date: cal.startOfDay(for: now)) }
                    }
                }
                CutSection(label: "Ajustes", inset: false) {
                    link("Ajustes", "região, dados, mapas, nuvem") { router.push(.settings) }
                }
                V8BarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .v8Legacy()
        #if DEBUG
        .task {
            if DebugFlags.string("debugScreen") == "proximos" { ProximosDemo.ensure(context: context, region: region) }
        }
        #endif
    }

    // MARK: Linhas

    /// Linha fixa do topo da aba: a viagem de agora com bandeira e moeda; abre Minhas viagens.
    private var minhasViagens: some View {
        Button { router.sheet = .viagens } label: {
            HStack(spacing: 12) {
                TripFlag(theme, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minhas viagens").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                    Text("\(region.displayName) · \(TripSwitcherModel.currencyLabel(region))")
                        .font(V8Font.mono(12)).foregroundStyle(V8.mute).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(V8.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .overlay(alignment: .bottom) { IndexRule() }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Presentes").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                    Text(GiftLogic.pendingOfText(gifts)).font(V8Font.mono(12)).foregroundStyle(pending ? V8.orangeDeep : V8.mute).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(V8.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Presentes, \(GiftLogic.pendingOfText(gifts))")
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nada marcado pela frente.").font(V8Font.display(24)).tracking(-0.6).foregroundStyle(V8.ink)
            Text("Reserva, ingresso, trem e voo aparecem aqui em ordem, e somem quando passam.")
                .font(V8Font.text(14)).foregroundStyle(V8.mute)
            Button { router.sheet = .ticketImport(inboxId: nil) } label: { CutChip(text: "Trazer ingresso", isOn: true) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    private func link(_ title: String, _ meta: String, alert: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CutRow(title: title, detail: meta) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(alert ? V8.orangeDeep : V8.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(meta)")
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

/// Um próximo (corte): hora em numeral mono grande à esquerda, tipo e dia em micro-rótulo, título e detalhe; reserva leva o
/// ponto laranja. Régua de 2 pt embaixo.
struct ProximoCard: View {
    var item: Proximos.Item
    var region: Region
    var now: Date
    var leave: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(region.timeString(item.at))
                .font(V8Font.mono(26, weight: .bold)).monospacedDigit()
                .foregroundStyle(item.kind == .reservation ? V8.orangeDeep : V8.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.kind == .reservation { Circle().fill(V8.orange).frame(width: 7, height: 7).accessibilityHidden(true) }
                    Text("\(item.kind.label) · \(Proximos.dayLabel(item.at, now: now, calendar: region.calendar))".uppercased())
                        .font(V8Font.mono(10, weight: .semibold)).tracking(0.8).foregroundStyle(V8.mute).lineLimit(1)
                }
                Text(item.title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                let detail = [item.route, item.detail, leave, item.corner].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { IndexRule() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
