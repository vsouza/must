import SwiftUI

/// Textos puros do bloco "Em cartaz" do Lugar (`LugarEmCartaz.png`).
enum PlaceEmCartaz {
    /// Eventos que o bloco mostra: sem os vencidos, "agora" primeiro, depois por data.
    static func visible(_ events: [ShowEvent], now: Date, calendar: Calendar) -> [ShowEvent] {
        let alive = events.filter { !EmCartazModel.isExpired($0, now: now, calendar: calendar) }
        return alive.sorted { a, b in
            let an = EmCartazModel.happensToday(a, now: now, calendar: calendar)
            let bn = EmCartazModel.happensToday(b, now: now, calendar: calendar)
            if an != bn { return an }
            return (EmCartazModel.nextDate(a, now: now) ?? .distantPast) < (EmCartazModel.nextDate(b, now: now) ?? .distantPast)
        }
    }

    static func nowCount(_ events: [ShowEvent], now: Date, calendar: Calendar) -> Int {
        events.filter { EmCartazModel.happensToday($0, now: now, calendar: calendar) }.count
    }

    /// "2 agora · 1 em breve".
    static func summary(_ events: [ShowEvent], now: Date, calendar: Calendar) -> String {
        let n = nowCount(events, now: now, calendar: calendar)
        let soon = events.count - n
        return [n > 0 ? "\(n) agora" : nil, soon > 0 ? "\(soon) em breve" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// "colado há 3 dias" / "checado hoje"; nil sem data de checagem.
    static func checked(_ events: [ShowEvent], now: Date, calendar: Calendar) -> String? {
        guard let last = events.compactMap(\.checkedAt).max() else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        let manual = events.contains { $0.source == .link || $0.source == .poster }
        let verb = manual ? "colado" : "checado"
        if days <= 0 { return "\(verb) hoje" }
        return "\(verb) há \(days) \(days == 1 ? "dia" : "dias")"
    }

    /// Período: "até 15 fev", "permanente", "21 nov – 8 fev".
    static func period(_ event: ShowEvent, region: Region, now: Date) -> String? {
        let cal = region.calendar
        if let start = event.startsAt, let until = event.runsUntil {
            if start <= now { return "até \(region.shortDay(until))" }
            return "\(region.shortDay(start)) – \(region.shortDay(until))"
        }
        if event.kind == .exhibition, event.runsUntil == nil, let start = event.startsAt, start < cal.startOfDay(for: now) { return "permanente" }
        if let next = EmCartazModel.nextDate(event, now: now) { return "\(KindLines.weekdayDay(next, region: region)) · \(region.timeString(next))" }
        return nil
    }
}

/// Lugar › "Em cartaz" (`LugarEmCartaz.png`): tag AGORA / EM BREVE, título, período, origem, atalhos de colar e a data da
/// última checagem. Só aparece quando há algo em cartaz (nada de card vazio).
struct EmCartazSection: View {
    var events: [ShowEvent]
    var region: Region
    var now: Date
    var onInk: Bool
    var onPaste: () -> Void
    var onPoster: () -> Void

    private var primary: Color { onInk ? V8.white : V8.ink }
    private var secondary: Color { onInk ? V8.muteDark : V8.mute }
    private var rule: Color { primary.opacity(onInk ? 0.28 : 0.14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Em cartaz").font(V8Font.display(28)).tracking(-0.8).foregroundStyle(primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                SpecLabel(PlaceEmCartaz.summary(events, now: now, calendar: region.calendar), color: secondary)
            }
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 1) }
            ForEach(events) { event in
                row(event).overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 1) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button(action: onPaste) { V8Pill("Colar programação", onInk: onInk) }
                    Button(action: onPoster) { V8Pill("Fotografar cartaz", onInk: onInk) }
                }
                .buttonStyle(MustPressStyle())
            }
            .padding(.top, 20)
            if let checked = PlaceEmCartaz.checked(events, now: now, calendar: region.calendar) {
                SpecLabel("checado: \(checked) · funciona sem internet", color: secondary).padding(.top, 14)
            }
        }
    }

    private func row(_ event: ShowEvent) -> some View {
        let live = EmCartazModel.happensToday(event, now: now, calendar: region.calendar)
        let next = EmCartazModel.nextDate(event, now: now)
        let detail = [PlaceEmCartaz.period(event, region: region, now: now), event.venue, event.priceText]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 16) {
            Group {
                if live { V8Tag(text: "agora", style: .orange) }
                else if let next { V8Tag(text: region.shortDay(next), style: onInk ? .graphite : .paper) }
                else { V8Tag(text: "em breve", style: onInk ? .graphite : .paper) }
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(V8Font.text(19, weight: .bold)).tracking(-0.2).foregroundStyle(primary)
                    .lineLimit(3).multilineTextAlignment(.leading)
                if !detail.isEmpty {
                    Text(detail).font(V8Font.text(14)).foregroundStyle(secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                V8Tag(text: EmCartazModel.origin(event.source), style: onInk ? .graphite : .paper).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
