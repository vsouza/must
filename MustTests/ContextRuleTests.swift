import Foundation
import Testing
@testable import Must

/// Prompt 32 §3: contexto estável. Datas fixas, nunca `Date()`.
@MainActor
struct ContextRuleTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    private let t0 = Date(timeIntervalSince1970: 1_794_538_800)

    private func area(_ id: String) -> Area {
        Area(id: id, name: id.capitalized, nameLocal: nil, cityId: "tokyo", centroid: .init(lat: 35.69, lng: 139.70),
             polygon: nil, stationIds: [], aliases: [], neighbors: [], stampText: nil, stampSub: nil, heroPhotoRef: nil)
    }

    private func fix(_ s: TimeInterval, acc: Double = 30, speed: Double = 0, lat: Double = 35.69, lng: Double = 139.70) -> LocationFix {
        LocationFix(latitude: lat, longitude: lng, horizontalAccuracy: acc, speed: speed, timestamp: t0.addingTimeInterval(s))
    }

    /// Alimenta leituras a cada 30 s de 0 até `upTo` e devolve a última resposta.
    private func run(_ p: inout ArrivalProposer, upTo: TimeInterval, area: String = "nakano", shown: String? = "shinjuku",
                     inside: Bool = true, acc: Double = 30, speed: Double = 0) -> String? {
        var out: String?
        var s: TimeInterval = 0
        while s <= upTo {
            out = p.feed(fix(s, acc: acc, speed: speed), areaId: area, shownAreaId: shown, insideTripCity: inside)
            s += 30
        }
        return out
    }

    @Test func parado2minComPrecisaoBoaPropoe() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 120) == "nakano")
    }

    @Test func umMinutoNaoPropoe() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 60) == nil)
    }

    @Test func andando2msNaoPropoe() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 300, speed: 2) == nil)
    }

    @Test func metroPrecisaoRuimNuncaPropoe() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 600, acc: 300) == nil)
    }

    @Test func metroBairrosTrocandoNuncaPropoe() {
        var p = ArrivalProposer()
        var out: String?
        for i in 0..<20 { out = p.feed(fix(Double(i) * 30), areaId: i.isMultiple(of: 2) ? "a" : "b", shownAreaId: "x", insideTripCity: true) ?? out }
        #expect(out == nil)
    }

    @Test func leituraRuimNoMeioReiniciaAJanela() {
        var p = ArrivalProposer()
        _ = p.feed(fix(0), areaId: "nakano", shownAreaId: nil, insideTripCity: true)
        _ = p.feed(fix(60, acc: 400), areaId: "nakano", shownAreaId: nil, insideTripCity: true)
        #expect(p.feed(fix(120), areaId: "nakano", shownAreaId: nil, insideTripCity: true) == nil)
        #expect(p.feed(fix(240), areaId: "nakano", shownAreaId: nil, insideTripCity: true) == "nakano")
    }

    @Test func velocidadeDesconhecidaComPosicaoParadaVale() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 120, speed: -1) == "nakano")
    }

    @Test func velocidadeDesconhecidaComPosicaoVariandoNaoVale() {
        var p = ArrivalProposer()
        var out: String?
        for i in 0...6 {
            out = p.feed(fix(Double(i) * 30, speed: -1, lng: 139.70 + Double(i) * 0.001), areaId: "nakano", shownAreaId: nil, insideTripCity: true)
        }
        #expect(out == nil)
    }

    @Test func dispensadoNaoPropoePorUmaHoraEDepoisVolta() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 120) == "nakano")
        p.dismiss("nakano", now: t0.addingTimeInterval(120))
        #expect(p.feed(fix(150), areaId: "nakano", shownAreaId: "shinjuku", insideTripCity: true) == nil)
        #expect(p.feed(fix(3_500), areaId: "nakano", shownAreaId: "shinjuku", insideTripCity: true) == nil)
        #expect(p.feed(fix(3_800), areaId: "nakano", shownAreaId: "shinjuku", insideTripCity: true) == "nakano")
    }

    @Test func foraDaCidadeNuncaPropoe() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 600, inside: false) == nil)
    }

    @Test func mesmoBairroMostradoNaoPropoe() {
        var p = ArrivalProposer()
        #expect(run(&p, upTo: 300, shown: "nakano") == nil)
    }

    // MARK: Modelo

    private func model() -> TodayContextModel {
        TodayContextModel(defaults: UserDefaults(suiteName: "ctx-test-\(UUID().uuidString)")!)
    }

    private func update(_ m: TodayContextModel, stop: Area?, now: Date) {
        m.update(tripId: "jp", areas: [area("nakano"), area("shinjuku"), area("ginza")], dayStop: stop, baseAreaId: nil, baseName: "Tóquio",
                 now: now, calendar: cal)
    }

    @Test func ordemMaoParadaConfirmadoBase() {
        let m = model()
        update(m, stop: nil, now: t0)
        #expect(m.context.source == .base)
        update(m, stop: area("shinjuku"), now: t0)
        #expect(m.context.source == .dayStop && m.context.areaId == "shinjuku")
        m.choose(area("ginza"), now: t0)
        #expect(m.context.source == .manual && m.context.areaId == "ginza")
        // nova parada não apaga a escolha à mão do dia
        update(m, stop: area("nakano"), now: t0.addingTimeInterval(600))
        #expect(m.context.areaId == "ginza" && m.context.source == .manual)
        // outro dia, sem parada: o último confirmado
        update(m, stop: nil, now: t0.addingTimeInterval(86_400 * 2))
        #expect(m.context.source == .confirmed && m.context.areaId == "ginza")
    }

    @Test func maoExpiraNaViradaDoDiaNoFusoDaRegiao() {
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 23, minute: 50))!
        let early = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 0, minute: 10))!
        let manual = ManualContext(areaId: "nakano", name: "Nakano", chosenAt: late)
        func inputs(_ now: Date) -> ContextInputs {
            ContextInputs(manual: manual, dayStop: nil, lastConfirmed: nil, baseAreaId: nil, baseName: "Tóquio", now: now, calendar: cal)
        }
        #expect(ContextRule.resolve(inputs(late.addingTimeInterval(60))).source == .manual)
        #expect(ContextRule.resolve(inputs(early)).source == .base)
    }

    @Test func aceitarViraContextoEUltimoConfirmado() {
        let m = model()
        update(m, stop: area("shinjuku"), now: t0)
        for i in 0...4 { m.feed(fix(Double(i) * 30), area: area("nakano"), insideTripCity: true) }
        #expect(m.proposal?.id == "nakano")
        m.acceptProposal(now: t0.addingTimeInterval(120))
        #expect(m.context.areaId == "nakano" && m.proposal == nil)
        update(m, stop: nil, now: t0.addingTimeInterval(86_400 * 2))
        #expect(m.context.areaId == "nakano" && m.context.source == .confirmed)
    }
}
