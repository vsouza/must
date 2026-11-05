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
                      distance: CLLocationDistance?) -> AgoraContent {
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

        let more = plan.stops.dropFirst(idx + 2).prefix(4).map { stop in
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
        if cash { chips.append(region == .jp ? "caixa 7 Bank no konbini" : "saque antes") }
        if region == .jp, let mode = legBefore?.mode, mode == .train || mode == .metro { chips.append("banheiro na estação") }
        if region == .jp, legBefore == nil || legBefore?.mode == .walk { chips.append("konbini no caminho") }
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

    @State private var plan: DayPlan?
    @State private var content: AgoraContent?
    @State private var current: DayStop?
    /// Antes da primeira parada: ela e a hora de sair pra ela.
    @State private var upcoming: (stop: DayStop, leaveAt: Date)?
    @State private var loaded = false

    private var region: Region { store.region }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(AppClock.now) }

    var body: some View {
        Group {
            if let content, let current {
                screen(content, current: current)
            } else if loaded {
                empty
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                V8.ink
                Rings(color: V8.white, count: 2, diameter: 560, opacity: 0.28, offset: CGSize(width: -60, height: 40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
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
        let start = region.calendar.startOfDay(for: now)
        plan = engine.plan(for: start, region: region, context: context)
        let doneIds = DayDoneStore().ids(day: dayKey)
        // O que você já marcou como feito aqui sai do "agora" (o motor ainda não sabe das micro-paradas).
        let effective = plan.map { p in
            var p = p
            p.stops = p.stops.map { var s = $0; if doneIds.contains(s.id) { s.done = true }; return s }
            return p
        }
        // "Agora" só entre as que faltam: a parada marcada como feita passa a vez pra próxima.
        let pending = effective.map { p in var p = p; p.stops = p.stops.filter { !$0.done }; return p }
        guard let effective, let pending, let dayNow = engine.now(in: pending, at: now) else {
            // Antes da primeira parada o motor devolve `nil`: não é "o dia acabou", é "o dia começa às…".
            upcoming = pending.flatMap { p in
                p.stops.first.flatMap { now < $0.start ? ($0, DayNowRules.leaveTime(to: $0, in: p)) : nil }
            }
            content = nil; current = nil; loaded = true; return
        }
        upcoming = nil
        let place = dayNow.current.placeId.flatMap { id in places.first { $0.id == id } }
        let distance = place.flatMap { $0.distance(from: services.location.current) }
        current = dayNow.current
        content = AgoraContent.build(plan: effective, now: dayNow, at: now, region: region, placeNotes: place?.notes,
                                     distance: distance)
        loaded = true
    }

    private func screen(_ c: AgoraContent, current: DayStop) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SpecStack(lines: ["Agora · \(region.timeString(AppClock.now))", "parada \(c.position)"], color: V8.muteDark)
                Spacer(minLength: 12)
                SpecStack(lines: [[areaName(current), tempText].compactMap { $0 }.joined(separator: " · "),
                                  services.connectivity.isOffline ? "sem rede · offline ok" : "offline ok"],
                          color: V8.muteDark, alignment: .trailing)
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    MonoLabel(c.verb, size: 10.5, color: V8.orange)
                    Spacer(minLength: 8)
                    SpecStack(lines: [c.countdown, c.travel].compactMap { $0 }, color: V8.muteDark, alignment: .trailing)
                }
                .padding(.top, 34)
                BigNumeral(region.timeString(c.time), size: 140, color: V8.orange)
                    .padding(.leading, -6)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(c.verb) \(region.timeString(c.time)), \(c.countdown)")

            Text(c.title)
                .font(V8Font.display(46))
                .foregroundStyle(V8.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 12)
            Text(c.meta)
                .font(V8Font.text(15))
                .foregroundStyle(V8.muteDark)
                .lineLimit(1)
                .padding(.top, 6)
            if !c.chips.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(c.chips, id: \.self) { chip in contextChip(chip) }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.top, 14)
            }

            progressBar(c).padding(.top, 22)

            if let next = c.next { nextCard(next).padding(.top, 20) }
            if !c.more.isEmpty { morePills(c.more).padding(.top, 16) }

            Spacer(minLength: 16)
            actions(c, current: current)
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 20)
    }

    private var tempText: String? {
        services.sync.now(region: region, trip: trips.first).map { "\(Int($0.temp.rounded()))°" }
    }

    private func areaName(_ stop: DayStop) -> String? {
        let id = stop.area ?? plan?.area
        return id.flatMap { id in AreaCatalog.areas(for: region).first { $0.id == id }?.name }
    }

    private func contextChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(V8.orange).frame(width: 6, height: 6)
            Text(text).font(V8Font.text(12.5, weight: .semibold)).foregroundStyle(V8.white).lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .overlay(Capsule().strokeBorder(V8.white.opacity(0.3), lineWidth: 1))
    }

    private func progressBar(_ c: AgoraContent) -> some View {
        VStack(spacing: 8) {
            HStack {
                MonoLabel("Você", color: V8.muteDark)
                Spacer(minLength: 8)
                MonoLabel(c.progressLabel, color: V8.muteDark)
                Spacer(minLength: 8)
                MonoLabel(c.title, color: V8.orange)
            }
            GeometryReader { geo in
                let x = geo.size.width * c.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(V8.white.opacity(0.18)).frame(height: 6)
                    Capsule().fill(V8.orange).frame(width: max(6, x), height: 6)
                    Circle().fill(V8.white).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(V8.ink, lineWidth: 3).padding(-3))
                        .offset(x: min(max(0, x - 8), geo.size.width - 16))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trajeto até \(c.title): \(Int(c.progress * 100)) por cento do tempo até a saída")
    }

    private func nextCard(_ next: DayStop) -> some View {
        Button {
            if let id = next.placeId { router.push(.place(id: id), on: .hoje) } else { router.push(.linha(date: today), on: .hoje) }
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    MonoLabel("Depois", size: 9.5, color: V8.mute)
                    Text(region.timeString(next.start)).font(V8Font.mono(16)).fontWeight(.semibold).foregroundStyle(V8.ink)
                }
                .frame(minWidth: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.label).font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                    Text(next.note).font(V8Font.text(12)).foregroundStyle(V8.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
                if next.kind == .anchor {
                    Text("ÂNCORA").font(V8Font.mono(9)).fontWeight(.semibold).tracking(0.7).foregroundStyle(V8.ink)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(V8.orange))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(V8.paper))
        }
        .buttonStyle(MustPressStyle())
    }

    private func morePills(_ more: [String]) -> some View {
        HStack(spacing: 8) {
            MonoLabel("e mais", color: V8.muteDark).fixedSize()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(more, id: \.self) { text in
                        Button { router.push(.linha(date: today), on: .hoje) } label: {
                            Text(text).font(V8Font.text(12.5, weight: .semibold)).foregroundStyle(V8.white).lineLimit(1)
                                .padding(.horizontal, 13).frame(height: 30)
                                .overlay(Capsule().strokeBorder(V8.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }

    private func actions(_ c: AgoraContent, current: DayStop) -> some View {
        HStack(spacing: 10) {
            RoundButton(systemImage: "arrow.up.arrow.down", label: "Trocar parada", style: .line, tint: V8.white, size: 56) {
                router.push(.montar(date: today), on: .hoje)
            }
            BigButton(title: irTitle(c), style: .orange, systemImage: "arrow.up.right") {
                if let id = current.placeId { router.push(.ir(placeId: id), on: .hoje) } else { router.push(.linha(date: today), on: .hoje) }
            }
            RoundButton(systemImage: "checkmark", label: "Marcar como feito", style: .paper, size: 56) { markDone(current) }
        }
    }

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
        VStack(alignment: .leading, spacing: 14) {
            SpecStack(lines: ["Agora · \(region.timeString(AppClock.now))",
                              plan == nil ? "sem dia montado" : upcoming != nil ? "antes da primeira parada" : "dia feito"],
                      color: V8.muteDark)
                .padding(.top, 10)
            Spacer()
            if let upcoming {
                Text("O dia começa às \(region.timeString(upcoming.stop.start)).")
                    .font(V8Font.display(40))
                    .foregroundStyle(V8.white)
                Text("Primeira parada: \(upcoming.stop.label). Saia às \(region.timeString(upcoming.leaveAt)).")
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.muteDark)
                BigButton(title: "Ver o dia", style: .orange, systemImage: "arrow.up.right") {
                    router.push(.linha(date: today), on: .hoje)
                }
                .padding(.top, 8)
            } else {
                Text(plan == nil ? "Nada marcado agora." : "O dia acabou.")
                    .font(V8Font.display(40))
                    .foregroundStyle(V8.white)
                Text(plan == nil ? "Monte o dia e o Agora mostra a hora de sair, o caminho e o que vem depois."
                                 : "Todas as paradas passaram. A Boa noite fecha o dia.")
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.muteDark)
                BigButton(title: plan == nil ? "Montar o dia" : "Boa noite", style: .orange, systemImage: "arrow.up.right") {
                    router.push(plan == nil ? .montar(date: today) : .boaNoite, on: .hoje)
                }
                .padding(.top, 8)
            }
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 20)
    }
}
