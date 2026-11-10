import CoreLocation
import SwiftData
import SwiftUI

/// O que o Agora mostra (puro, testável).
struct AgoraContent: Equatable {
    /// "Saia às" ou "Chegue às" (lugar sem reserva com fila).
    var verb: String
    var time: Date
    /// "em 15 min" (ou "agora" / "passou 5 min").
    var countdown: String
    /// "a pé · 9 min"
    var travel: String?
    var title: String
    /// "tsukemen · fila ~20 min · ¥ 1.250 · até 15:00"
    var meta: String
    var chips: [String]
    /// "k de n"
    var position: String
    /// 0–1: quanto do caminho até a saída já passou.
    var progress: Double
    var progressLabel: String
    var next: DayStop?
    var more: [String]
    var walkMinutes: Int?

    static func build(plan: DayPlan, now dayNow: DayNow, at date: Date, region: Region, placeNotes: String?,
                      distance: CLLocationDistance?, hidden: Set<String> = []) -> AgoraContent {
        let current = dayNow.current
        let time = dayNow.arriveBy ?? dayNow.leaveAt
        let minutes = Int((time.timeIntervalSince(date) / 60).rounded())
        let countdown = minutes > 0 ? "em \(minutes) min" : minutes == 0 ? "agora" : "passou \(-minutes) min"

        let legBefore = plan.leg(before: current)
        let walk = distance.map { Walk.minutes($0) } ?? (legBefore?.mode == .walk ? legBefore?.minutes : nil)
        var travel: String?
        if let walk, (distance ?? 0) <= 2000 { travel = "a pé · \(walk) min" } else if let legBefore {
            travel = "\(DayLegRow.modeLabel(legBefore.mode)) · \(legBefore.minutes) min"
        }

        // Meta: o resto do rótulo ("tsukemen"), a nota sem o "Must eat" e o fim da parada.
        let labelParts = current.label.components(separatedBy: " · ").dropFirst()
        let noteParts = current.note.components(separatedBy: " · ").filter { !$0.lowercased().hasPrefix("must ") }
        // "até" some quando a parada acaba bem antes do "saia às" (tempo livre até a próxima): dizia "até 16:30" com
        // "saia às 17:05" na mesma tela. Até 10 min de folga, fica.
        let until = dayNow.leaveAt.timeIntervalSince(current.end) <= 600 ? ["até \(region.timeString(current.end))"] : []
        let meta = (Array(labelParts) + noteParts + until).joined(separator: " · ")

        let k = plan.position(of: current) ?? 1
        let idx = k - 1
        let prevEnd = idx > 0 ? plan.stops[idx - 1].end : region.calendar.startOfDay(for: date)
        let span = time.timeIntervalSince(prevEnd)
        let progress = span > 0 ? min(1, max(0, date.timeIntervalSince(prevEnd) / span)) : 1
        let progressLabel = distance.map { Walk.distanceText($0) } ?? legBefore.map { DayLegRow.text($0) } ?? ""

        let more = plan.stops.dropFirst(idx + 2).filter { !$0.done && !hidden.contains($0.id) }.prefix(4).map { stop in
            let head = DayText.head(stop.label)
            let word = stop.kind == .micro ? (head.split(separator: " ").first.map(String.init)?.lowercased() ?? head) : head
            return "\(region.timeString(stop.start)) \(word)"
        }

        return AgoraContent(verb: dayNow.arriveBy != nil ? "Chegue às" : "Saia às", time: time, countdown: countdown,
                            travel: travel, title: DayText.head(current.label), meta: meta,
                            chips: chips(stop: current, placeNotes: placeNotes, region: region, legBefore: legBefore),
                            position: "\(k) de \(plan.stops.count)", progress: progress, progressLabel: progressLabel,
                            next: dayNow.next, more: Array(more), walkMinutes: walk)
    }

    /// Chips de contexto: caixa antes de lugar só-cash, banheiro na estação (trem/metrô no Japão), "só cash".
    static func chips(stop: DayStop, placeNotes: String?, region: Region, legBefore: DayLeg?) -> [String] {
        var chips: [String] = []
        let cash = CashOnly.detect(stop.label, stop.note, placeNotes)
        let money = region.profile.money, konbini = region.profile.day?.konbiniChips == true
        if cash { chips.append(money?.atmChip ?? "saque antes") }
        if konbini, let mode = legBefore?.mode, mode == .train || mode == .metro { chips.append("banheiro na estação") }
        if konbini, legBefore == nil || legBefore?.mode == .walk { chips.append("konbini no caminho") }
        if cash { chips.append("só cash") }
        return chips
    }
}

/// 03 · Agora (prompt 23 §2, `Agora.png`). Tinta. "Saia às" gigante, o lugar atual, chips de contexto, a barra do
/// trajeto, o "Depois" e as pílulas "e mais". Ações: trocar · Ir · feito. Sem rede, usa a estimativa do plano.
struct AgoraView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Environment(\.tripTheme) private var theme

    @State private var plan: DayPlan?
    @State private var clock: DayClock?
    @State private var content: AgoraContent?
    @State private var current: DayStop?
    /// Antes da primeira parada: ela e a hora de sair pra ela.
    @State private var upcoming: (stop: DayStop, leaveAt: Date)?
    @State private var loaded = false
    @State private var safeTop: CGFloat = 0

    private var region: Region { store.region }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(AppClock.now) }

    var body: some View {
        Group {
            if let content, let current {
                screen(content, current: current)
            } else if loaded {
                empty
            } else {
                V8.paper.ignoresSafeArea()
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .v8Legacy()
        .onAppear(perform: load)
        .task { await clock() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in load() }
    }

    private func clock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            load()
        }
    }

    private func load() {
        let now = AppClock.now
        // O relógio único (o mesmo da capa, da Linha e do Guia): feitos aplicados e, se atrasou, o resto já refeito.
        let clock = DayClock.read(engine: engine, region: region, context: context, at: now, position: services.location.current?.coordinate)
        plan = clock.plan
        self.clock = clock
        guard let effective = clock.plan, let dayNow = clock.now else {
            // Antes da primeira parada o relógio não tem "agora": não é "o dia acabou", é "o dia começa às…".
            upcoming = clock.upcoming.map { ($0.stop, $0.leaveAt) }
            content = nil; current = nil; loaded = true; return
        }
        upcoming = nil
        let place = dayNow.current.placeId.flatMap { id in places.first { $0.id == id } }
        let distance = place.flatMap { $0.distance(from: services.location.current) }
        current = dayNow.current
        content = AgoraContent.build(plan: effective, now: dayNow, at: now, region: region, placeNotes: place?.notes,
                                     distance: distance, hidden: clock.skippedIds)
        loaded = true
    }

    private func screen(_ c: AgoraContent, current: DayStop) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                band(c, current: current)
                CutRule()
                DayStrip {
                    VStack(alignment: .leading, spacing: 8) {
                        Text([c.countdown, c.travel].compactMap { $0 }.joined(separator: " · "))
                            .font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
                        if !c.meta.isEmpty { Text(c.meta).font(V8Font.text(14)).foregroundStyle(V8.mute).lineLimit(3) }
                        if let clock, clock.adjusted {
                            MonoLabel(DayText.adjustedLine(remaining: clock.remaining), size: 10, color: V8.ink)
                        }
                        progressBar(c)
                    }
                }
                if !c.chips.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { ForEach(c.chips, id: \.self) { CutChip(text: $0) } }
                            .padding(.horizontal, 20).padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .bottom) { IndexRule() }
                }
                Button { goTo(current) } label: {
                    HStack {
                        Text(irTitle(c).uppercased()).font(V8Font.mono(14, weight: .semibold)).tracking(1.2).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(V8.orange)
                    .overlay(alignment: .bottom) { IndexRule() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(irTitle(c))
                actionRow("Marcar como feito", detail: "a parada some do agora") { markDone(current) }
                actionRow("Trocar parada", detail: "refazer com outro lugar") { router.push(.montar(date: today), on: .hoje) }
                let rest = later(c)
                if !rest.isEmpty {
                    sectionLabel("depois")
                    ForEach(rest) { stop in
                        DayStopRow(stop: stop, state: .upcoming, region: region, onTap: openLater(stop))
                    }
                }
                actionRow("Ver o dia todo", detail: services.connectivity.isOffline ? "sem rede · offline ok" : "funciona sem internet") {
                    router.push(.linha(date: today), on: .hoje)
                }
                V8BarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .cutBleed($safeTop)
    }

    private func sectionLabel(_ text: String) -> some View {
        MonoLabel(text, size: 10, color: V8.mute)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func actionRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { CutRow(title: title, detail: detail) { CutValue(text: "", chevron: true) } }
            .buttonStyle(.plain)
    }

    /// Bloco do bairro da parada: voltar e ✦ nos cantos, o lugar e, no numeral, a hora de sair (o `DayClock`).
    private func band(_ c: AgoraContent, current: DayStop) -> some View {
        let ink = theme.coverInk
        let leave = region.timeString(c.time)
        let overdue = c.countdown == "agora" || c.countdown.hasPrefix("passou")
        return DayBand(areaId: current.area ?? plan?.area, places: places, height: 270, topInset: safeTop) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    CutCornerButton(systemName: "chevron.left", label: "Voltar", tint: ink) { dismiss() }
                    Spacer(minLength: 8)
                    SpecStack(lines: ["Agora · \(c.position)", areaName(current).map { $0 } ?? region.displayName], color: ink.opacity(0.9), alignment: .trailing)
                    CutCornerButton(systemName: "sparkle", label: "Assistente", tint: ink) { router.sheet = .assistant }
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 12) {
                    Text(c.title)
                        .font(V8Font.display(40)).tracking(-1.2).foregroundStyle(ink)
                        .lineLimit(3).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    DayBandNumeral(value: overdue ? "já" : leave, caption: overdue ? c.verb.replacingOccurrences(of: " às", with: "").lowercased() + " agora" : c.verb.lowercased(), size: 72)
                }
            }
        }
    }

    /// Trajeto até a saída: trilho quadrado de borda 2 pt, preenchido de laranja.
    private func progressBar(_ c: AgoraContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MonoLabel("você", size: 9, color: V8.mute)
                Spacer()
                MonoLabel(c.progressLabel, size: 9, color: V8.mute)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().stroke(V8.ink, lineWidth: 2)
                    Rectangle().fill(V8.orange).frame(width: max(0, geo.size.width * c.progress))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trajeto até \(c.title): \(Int(c.progress * 100)) por cento do tempo até a saída")
    }

    private func goTo(_ current: DayStop) {
        if let id = current.placeId { router.push(.ir(placeId: id), on: .hoje) } else { router.push(.linha(date: today), on: .hoje) }
    }

    /// O que vem depois: a próxima parada e até mais quatro (do plano, sem as já feitas).
    private func later(_ c: AgoraContent) -> [DayStop] {
        guard let next = c.next, let plan else { return [] }
        let done = DayDoneStore().ids(day: dayKey)
        let skipped = clock?.skippedIds ?? []
        let rest = plan.stops.filter { $0.start > next.start && !$0.done && !done.contains($0.id) && !skipped.contains($0.id) }
        return [next] + Array(rest.prefix(4))
    }

    private func openLater(_ stop: DayStop) -> () -> Void {
        { if let id = stop.placeId { router.push(.place(id: id), on: .hoje) } else { router.push(.linha(date: today), on: .hoje) } }
    }

    private var tempText: String? {
        services.sync.now(region: region, trip: trips.first).map { "\(Int($0.temp.rounded()))°" }
    }

    private func areaName(_ stop: DayStop) -> String? {
        let id = stop.area ?? plan?.area
        return id.flatMap { id in AreaCatalog.areas(for: region).first { $0.id == id }?.name }
    }

    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }

    private func irTitle(_ c: AgoraContent) -> String {
        if let travel = c.travel { return "Ir · \(travel.replacingOccurrences(of: " · ", with: " "))" }
        return "Ir"
    }

    /// Feito: some do "agora" (micro-paradas ficam no `DayDoneStore`); lugar do board abre o gasto, que marca 済.
    private func markDone(_ stop: DayStop) {
        DayDoneStore().mark(stop.id, day: dayKey)
        if let id = stop.placeId { router.sheet = .expense(placeId: id) }
        load()
    }

    private var empty: some View {
        let title: String
        let text: String
        if let upcoming {
            title = "O dia começa às \(region.timeString(upcoming.stop.start))."
            text = "Primeira parada: \(upcoming.stop.label). Saia às \(region.timeString(upcoming.leaveAt))."
        } else if plan == nil {
            title = "Nada marcado agora."
            text = "Monte o dia e o Agora mostra a hora de sair, o caminho e o que vem depois."
        } else {
            title = "O dia acabou."
            text = "Todas as paradas passaram. A Boa noite fecha o dia."
        }
        let numeral = upcoming.map { region.timeString($0.leaveAt) }
        return VStack(spacing: 0) {
            CutScreenHeader(title: title, corner: ["Agora"], height: 240, onBack: { dismiss() }) {
                CutCornerButton(systemName: "sparkle", label: "Assistente", tint: theme.coverInk) { router.sheet = .assistant }
            }
            VStack(alignment: .leading, spacing: 14) {
                if let numeral { MonoLabel("saia às \(numeral)", size: 11, color: V8.ink) }
                Text(text).font(V8Font.text(15)).foregroundStyle(V8.mute)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { IndexRule() }
            if upcoming != nil {
                HojeWideButton(title: "Ver o dia") { router.push(.linha(date: today), on: .hoje) }
            } else {
                HojeWideButton(title: plan == nil ? "Montar o dia" : "Boa noite") {
                    router.push(plan == nil ? .montar(date: today) : .boaNoite, on: .hoje)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
