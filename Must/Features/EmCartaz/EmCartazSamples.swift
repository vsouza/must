import Foundation

#if DEBUG
/// Dados de exemplo só pra prints (`-debugScreen emcartaz | lugar-emcartaz`) enquanto o provedor real está vazio.
/// Os nomes são os do design (`EmCartaz.png`, `LugarEmCartaz.png`); nada disto existe em release.
struct SampleShowEvents: ShowEventsProviding {
    var base: any ShowEventsProviding

    static var enabled: Bool {
        let screen = DebugFlags.string("debugScreen") ?? ""
        return screen.hasPrefix("emcartaz") || screen.hasPrefix("lugar-emcartaz")
    }

    func today(region: Region, at date: Date) -> [ShowEvent] {
        let real = base.today(region: region, at: date)
        return real.isEmpty ? Self.all(region: region, now: date).filter { EmCartazModel.happensToday($0, now: date, calendar: region.calendar) } : real
    }

    func upcoming(region: Region, from date: Date, days: Int) -> [ShowEvent] {
        let real = base.upcoming(region: region, from: date, days: days)
        return real.isEmpty ? Self.all(region: region, now: date) : real
    }

    func events(placeId: String, at date: Date) -> [ShowEvent] {
        let real = base.events(placeId: placeId, at: date)
        guard real.isEmpty else { return real }
        let region: Region = placeId.hasPrefix("p") ? .bh : .jp
        let cal = region.calendar
        func at(_ days: Int, _ hour: Int) -> Date {
            let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: date)) ?? date
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        return [
            ShowEvent(id: "p-1", placeId: placeId, kind: .exhibition, title: "Daidō Moriyama — A Retrospective",
                      venue: "até 15 fev · salas 1–3 · fotografar só no hall", startsAt: at(-30, 10), runsUntil: at(92, 18),
                      source: .board, checkedAt: at(-1, 9)),
            ShowEvent(id: "p-2", placeId: placeId, kind: .exhibition, title: "Acervo · fotografia do pós-guerra",
                      venue: "permanente · 2º andar · incluso no ingresso", startsAt: at(-300, 10),
                      source: .link, checkedAt: at(-3, 9)),
            ShowEvent(id: "p-3", placeId: placeId, kind: .exhibition, title: "Coletiva · fotografia contemporânea",
                      venue: "ingresso separado", startsAt: at(6, 10), runsUntil: at(85, 18), priceText: region.money(1500),
                      source: .poster, checkedAt: at(-2, 9)),
        ]
    }

    static func all(region: Region, now: Date) -> [ShowEvent] {
        let cal = region.calendar
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        switch region {
        case .bh:
            return [
                ShowEvent(id: "s-bh1", placeId: "p26", kind: .exhibition, title: "Fotografia mineira · mostra coletiva",
                          venue: "Museu · Centro", startsAt: at(-20, 10), runsUntil: at(60, 18), source: .board, checkedAt: at(-1, 9)),
                ShowEvent(id: "s-bh2", placeId: "p16", kind: .show, title: "Orquestra Sinfônica de Minas Gerais",
                          venue: "Palácio das Artes", startsAt: at(1, 20), priceText: "R$ 60", source: .link, checkedAt: at(-3, 9)),
                ShowEvent(id: "s-bh3", placeId: "p50", kind: .match, title: "Cruzeiro × Atlético · jogo",
                          venue: "Mineirão, Pampulha", startsAt: at(6, 16), source: .poster, checkedAt: at(-2, 9)),
            ]
        default:
            return [
                ShowEvent(id: "s-jp1", placeId: nil, kind: .exhibition, title: "Daidō Moriyama — A Retrospective",
                          venue: "Museu · Ebisu", startsAt: at(-30, 10), runsUntil: at(92, 18), source: .board, checkedAt: at(-1, 9)),
                ShowEvent(id: "s-jp2", placeId: "j28", kind: .exhibition, title: "teamLab Borderless",
                          venue: "Azabudai Hills", startsAt: at(1, 14), source: .board, checkedAt: at(-1, 9)),
                ShowEvent(id: "s-jp3", placeId: nil, kind: .show, title: "Billboard Live Tokyo · show",
                          venue: "Roppongi", startsAt: at(2, 19), priceText: "¥ 9.800", source: .link, checkedAt: at(-3, 9)),
                ShowEvent(id: "s-jp4", placeId: nil, kind: .match, title: "FC Tokyo × Kashima · jogo",
                          venue: "Estádio Ajinomoto, Chōfu", startsAt: at(6, 14), source: .poster, checkedAt: at(-2, 9)),
                ShowEvent(id: "s-jp5", placeId: nil, kind: .exhibition, title: "Exposição coletiva · fotografia",
                          venue: "Museu · Ebisu", startsAt: at(6, 10), runsUntil: at(85, 18), source: .poster, checkedAt: at(-2, 9)),
            ]
        }
    }
}
#endif

/// Em release, o provedor do ambiente como está; em DEBUG, com os exemplos dos prints por baixo.
@MainActor
enum EmCartazProvider {
    static func resolve(_ base: any ShowEventsProviding) -> any ShowEventsProviding {
        #if DEBUG
        SampleShowEvents.enabled ? SampleShowEvents(base: base) : base
        #else
        base
        #endif
    }
}
