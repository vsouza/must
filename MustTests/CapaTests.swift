import CoreGraphics
import Foundation
import Testing
@testable import Must

/// Capa do dia v8 (prompt 23 §2 · 01): conteúdo, gestos e quando usa foto.
@MainActor
struct CapaTests {
    private let plan = DayEngineStub.qaDay
    private var tokyo: Calendar { Region.jp.calendar }

    private func at(_ h: Int, _ m: Int, region: Region = .jp, day: Int = 15) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    private func inputs(plan: DayPlan?, now: Date, region: Region = .jp) -> CapaContent.Inputs {
        CapaContent.Inputs(region: region, now: now, plan: plan,
                           dayNow: plan.flatMap { DayEngineStub().now(in: $0, at: now) },
                           areaName: plan == nil ? nil : "Shinjuku", cityName: "Tóquio", tripDay: (5, 14),
                           tempText: "18°", sky: "sol", sunset: at(16, 38), spentToday: nil)
    }

    @Test func capaDoDiaDeQA() {
        let c = CapaContent.build(inputs(plan: plan, now: at(14, 20)))
        #expect(c.topLeft == ["Dom · 15 nov", "dia 3 de 14"])
        #expect(c.topRight == ["Tóquio · 18° sol", "pôr do sol 16:38"])
        #expect(c.midLeft == ["9 paradas", "3 âncoras · 4 micro"])
        #expect(c.midRight == ["gasto ¥ 4.250", "de ¥ 12.000"])
        #expect(c.area == "Shinjuku")
        #expect(c.evening == "e Golden Gai à noite")
        #expect(c.numeral == "3")
        #expect(c.country == "Japão")
        #expect(c.agora?.title.hasPrefix("Agora · ") == true)
        #expect(c.agora?.line.hasPrefix("Fuunji · saia ") == true)
        #expect(c.hasPlan)
    }

    @Test func semPlanoMostraOBairroEOMontar() {
        var i = inputs(plan: nil, now: at(14, 20))
        i.areaName = "Shinjuku"
        let c = CapaContent.build(i)
        #expect(!c.hasPlan)
        #expect(c.agora == nil)
        #expect(c.area == "Shinjuku")
        #expect(c.numeral == "5") // dia da viagem
    }

    @Test func diaAcabouLevaPraBoaNoite() {
        let c = CapaContent.build(inputs(plan: plan, now: at(23, 50)))
        #expect(c.agora?.dayOver == true)
    }

    @Test func foraDaViagemUsaODiaDoMesEFimDeSemana() {
        var i = inputs(plan: nil, now: at(14, 35, region: .bh, day: 7), region: .bh)
        i.tripDay = nil
        i.cityName = "Belo Horizonte"
        let c = CapaContent.build(i)
        #expect(c.numeral == "7")
        #expect(c.topLeft[1] == "fim de semana")
        #expect(c.country == "Brasil")
    }

    @Test func noiteOuGolden() {
        #expect(CapaContent.evening(plan, region: .jp) == "e Golden Gai à noite")
        var day = plan
        day.stops = day.stops.filter { Region.jp.calendar.component(.hour, from: $0.start) < 18 }
        #expect(CapaContent.evening(day, region: .jp) == "e Shinjuku Gyoen no golden")
    }

    // MARK: Gestos

    @Test func gestoPeloEixoDominante() {
        #expect(CapaSwipe.from(CGSize(width: 10, height: -120)) == .up)
        #expect(CapaSwipe.from(CGSize(width: 5, height: 90)) == .down)
        #expect(CapaSwipe.from(CGSize(width: -100, height: 20)) == .left)
        #expect(CapaSwipe.from(CGSize(width: 100, height: -30)) == .right)
        #expect(CapaSwipe.from(CGSize(width: 20, height: 30)) == nil)
    }

    @Test func praBaixoDependeDaHora() {
        #expect(CapaSwipe.route(for: .down, now: at(7, 20), region: .jp) == .bomDia)
        #expect(CapaSwipe.route(for: .down, now: at(9, 59), region: .jp) == .bomDia)
        #expect(CapaSwipe.route(for: .down, now: at(14, 20), region: .jp) == nil)
        #expect(CapaSwipe.route(for: .down, now: at(21, 0), region: .jp) == .boaNoite)
        #expect(CapaSwipe.route(for: .down, now: at(0, 30), region: .jp) == .boaNoite)
        #expect(CapaSwipe.route(for: .up, now: at(14, 20), region: .jp) == .linha(date: tokyo.startOfDay(for: at(14, 20))))
        #expect(CapaSwipe.route(for: .left, now: at(14, 20), region: .jp) == .dicas)
        #expect(CapaSwipe.route(for: .right, now: at(14, 20), region: .jp) == .bolso)
    }
}
