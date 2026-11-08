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

    var body: some View {
        let now = AppClock.now
        let items = upcoming(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(now: now).padding(.top, 8)
                minhasViagens.padding(.top, 14)
                presentesLinha.padding(.top, 10)
                // Grupo na raiz da aba (antes ficava escondido em Viagem › Gasto e dias).
                GrupoBlock(onInk: true).padding(.top, 22)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Próximos")
                        .font(V8Font.display(52))
                        .tracking(-1.6)
                        .foregroundStyle(V8.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    BigNumeral("\(items.count)", size: 74, color: V8.orange)
                }
                .padding(.top, 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Próximos: \(items.count)")
                SpecLabel("Só o que ainda vai acontecer · passou, some", color: V8.muteDark)
                    .padding(.top, 14)
                if items.isEmpty {
                    empty.padding(.top, 28)
                } else {
                    // Faixas de ponta a ponta com régua (o corte): reserva laranja, o resto papel.
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            Button { open(item) } label: { ProximoCard(item: item, region: region, now: now, leave: leaveLine(item)) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, -20)
                    .padding(.top, 22)
                }
                links.padding(.top, 30)
                V8BarSpacer()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack(alignment: .topLeading) {
                V8.ink
                Rings(color: V8.white, count: 1, diameter: 560, opacity: 0.32, offset: CGSize(width: -150, height: -210))
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .task {
            if DebugFlags.string("debugScreen") == "proximos" { ProximosDemo.ensure(context: context, region: region) }
        }
        #endif
    }

    // MARK: Topo

    private func header(now: Date) -> some View {
        let trip = trips.first?.hasTrip == true ? trips.first : nil
        let line = Proximos.tripLine(start: trip?.start, end: trip?.end, now: now, calendar: cal, month: region.monthShort)
        return HStack(alignment: .top) {
            V8SpecStack(lines: ["Viagem · \(region.shortName)", line ?? "sem viagem marcada · \(region.displayName)"], color: V8.muteDark)
                .padding(.top, 14)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                V8CornerButton(systemName: "creditcard", label: "Carteira", onInk: true) { router.push(.carteira) }
                AssistantCorner(onInk: true)
            }
        }
    }

    /// Linha fixa do topo da aba (v9): a viagem de agora com bandeira e moeda; tocar abre Minhas viagens (o mesmo ⇄ da capa).
    private var minhasViagens: some View {
        Button { router.sheet = .viagens } label: {
            HStack(spacing: 12) {
                TripFlag(theme, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minhas viagens").font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.white).lineLimit(1)
                    Text("\(region.displayName) · \(TripSwitcherModel.currencyLabel(region))")
                        .font(V8Font.mono(10)).tracking(0.8).textCase(.uppercase)
                        .foregroundStyle(V8.muteDark).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(V8.white)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(Rectangle().strokeBorder(V8.white, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Minhas viagens, \(region.displayName), moeda \(TripSwitcherModel.currencyLabel(region))")
    }

    /// Linha fixa logo abaixo de "Minhas viagens": "Presentes · 5 faltam de 6" abre a lista.
    private var presentesLinha: some View {
        let pending = GiftLogic.pendingCount(gifts) > 0
        return Button { router.push(.presentes) } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift").font(.system(size: 20, weight: .regular)).foregroundStyle(V8.white).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Presentes").font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.white).lineLimit(1)
                    Text(GiftLogic.pendingOfText(gifts))
                        .font(V8Font.mono(10)).tracking(0.8).textCase(.uppercase)
                        .foregroundStyle(pending ? V8.orange : V8.muteDark).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(V8.white)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(Rectangle().strokeBorder(V8.white, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Presentes, \(GiftLogic.pendingOfText(gifts))")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nada marcado pela frente.")
                .font(V8Font.display(26))
                .foregroundStyle(V8.white)
            Text("Reserva, ingresso, trem e voo aparecem aqui em ordem, e somem quando passam.")
                .font(V8Font.text(15))
                .foregroundStyle(V8.muteDark)
                .fixedSize(horizontal: false, vertical: true)
            V8Button("Trazer ingresso", .orange, icon: .colarLink) { router.sheet = .ticketImport(inboxId: nil) }
        }
    }

    /// Resto da Viagem (Nav.png: Próximos · Carteira · Voos · Compras · Mapas offline).
    private var links: some View {
        VStack(spacing: 0) {
            link("Coleção", "um card por lugar feito · mandar") { router.push(.colecao) }
            link("Carteira", "cartões, passes, QR de entrada") { router.push(.carteira) }
            link("Voos e reservas", "status e checklist") { router.push(.schedule(tab: .voos)) }
            link("Compras", "lista, cota e regras da volta") { router.push(.compras) }
            link("Mapas offline", "baixar a cidade no Wi-Fi") { router.push(.offlineMaps) }
            link("Gasto e dias", "orçamento e o que já foi gasto") { router.push(.trip) }
            // Prompt 25 · B.5: a viagem inteira em PDF (um dia por página), o cartaz e o link do dia.
            link("Mandar a viagem", "PDF um dia por página · cartaz · link") { router.sheet = .mandar(date: nil) }
        }
    }

    private func link(_ title: String, _ meta: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(V8Font.text(16, weight: .semibold)).foregroundStyle(V8.white)
                    Text(meta).font(V8Font.text(13)).foregroundStyle(V8.muteDark).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(V8.muteDark)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(V8.white.opacity(0.12)).frame(height: 1) }
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

/// Um bilhete: etiqueta (tipo · dia) e rótulo à direita; hora grande com a rota; título e meta.
struct ProximoCard: View {
    var item: Proximos.Item
    var region: Region
    var now: Date
    var leave: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                V8Tag(text: "\(item.kind.label) · \(Proximos.dayLabel(item.at, now: now, calendar: region.calendar))", style: .ink)
                Spacer(minLength: 8)
                if let corner = item.corner {
                    SpecLabel(corner, color: item.kind == .reservation ? V8.ink : V8.mute)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(region.timeString(item.at))
                    .font(V8Font.numeral(44))
                    .tracking(-1.4)
                    .foregroundStyle(V8.ink)
                    .fixedSize()
                if let route = item.route {
                    SpecLabel(route, color: item.kind == .reservation ? V8.ink : V8.mute)
                }
            }
            Text(item.title)
                .font(V8Font.text(18, weight: .bold))
                .foregroundStyle(V8.ink)
                .lineLimit(2)
            let detail = [item.detail, leave].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !detail.isEmpty {
                Text(detail)
                    .font(V8Font.text(14))
                    .foregroundStyle(V8.ink.opacity(0.72))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.kind == .reservation ? V8.orange : V8.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
        .accessibilityElement(children: .combine)
    }
}
