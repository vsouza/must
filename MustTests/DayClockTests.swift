import CoreLocation
import Foundation
import Testing
@testable import Must

/// Relatório do viajante, problemas 1 e 2: um relógio só pra capa, Linha, Agora e Guia; e o plano vivo (atrasou → o resto
/// do dia se refaz sozinho, sem apagar âncora, sem culpa).
@MainActor
struct DayClockTests {
    private let plan = DayEngineStub.qaDay
    private let region = Region.jp

    private func at(_ h: Int, _ m: Int) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: h, minute: m))!
    }

    private func clock(_ h: Int, _ m: Int, done: Set<String> = [], plan custom: DayPlan? = nil) -> DayClock {
        DayClock.make(plan: custom ?? plan, doneIds: done, at: at(h, m), region: region)
    }

    // MARK: Um relógio de verdade

    @Test func as4LeiturasDizemAMesmaCoisaAs1420() throws {
        let c = clock(14, 20)
        let now = try #require(c.now)
        let effective = try #require(c.plan)

        // Capa
        let capa = CapaContent.build(.init(region: region, now: at(14, 20), plan: effective, dayNow: c.now, skippedIds: c.skippedIds,
                                           areaName: "Shinjuku", cityName: "Tóquio", tripDay: (3, 14), tempText: nil, sky: nil,
                                           sunset: nil, spentToday: nil))
        // Agora
        let agora = AgoraContent.build(plan: effective, now: now, at: at(14, 20), region: region, placeNotes: nil, distance: nil,
                                       hidden: c.skippedIds)
        // Linha
        let linhaNow = effective.stops.first { LinhaStopState.of($0, nowId: now.current.id, doneIds: [], skippedIds: c.skippedIds) == .now }
        // Guia
        let stops = effective.stops.filter { !c.skippedIds.contains($0.id) }
        let chapters = GuiaChapters.build(stops: stops, nowStopId: now.current.id, extras: [], calendar: region.calendar, now: at(14, 20))
        let guiaNow = chapters.flatMap(\.items).first(where: \.isNow)

        let leave = region.timeString(now.leaveAt)
        #expect(now.current.id == "s4")
        #expect(capa.agora?.line == "Fuunji · saia \(leave)")
        #expect(agora.title == "Fuunji")
        #expect(region.timeString(agora.time) == leave)
        #expect(linhaNow?.id == "s4")
        #expect(guiaNow?.id == "stop-s4")
        // Nenhuma tela mostra o que ficou pra depois como "agora".
        #expect(guiaNow?.title.hasPrefix("Fuunji") == true)
    }

    @Test func umaSoFonteParaAtualProximaESaiaAs() throws {
        let c = clock(14, 20)
        let now = try #require(c.now)
        #expect(now.next?.id == "s5")
        #expect(c.actionVerb == "saia")
        #expect(c.actionTime == now.leaveAt)
        #expect(c.position == 4)
        #expect(c.phase == .running)
    }

    @Test func feitoMarcadoNaTelaVaiProRelogioDeTodos() throws {
        // s3 marcado como feito: não vira "atrasou".
        let c = clock(14, 20, done: ["s3"])
        #expect(c.adjusted == false)
        #expect(c.now?.current.id == "s4")
        #expect(c.plan?.stops.first { $0.id == "s3" }?.done == true)
    }

    @Test func antesDaPrimeiraParadaDiaOQueFalta() throws {
        var early = plan
        early.stops = early.stops.map { var s = $0; s.done = false; return s }
        let c = clock(7, 0, plan: early)
        #expect(c.phase == .before)
        #expect(c.upcoming?.stop.id == "s1")
        #expect(c.adjusted == false)
    }

    @Test func semDiaEDiaAcabado() {
        let none = DayClock.make(plan: nil, doneIds: [], at: at(10, 0), region: region)
        #expect(none.phase == .noPlan)
        let late = clock(23, 50)
        #expect(late.phase == .finished)
    }

    // MARK: Plano vivo

    @Test func passouDaHoraSemFeitoRefazOResto() throws {
        let c = clock(14, 20)
        #expect(c.adjusted)
        // O micro "Konbini" (12:30, sem feito) passou da hora: ficou pra depois, não "deveria estar".
        #expect(c.skippedIds == ["s3"])
        // Faltam Fuunji, golden, descanso, depachika, jantar e Golden Gai.
        #expect(c.remaining == 6)
        #expect(DayText.adjustedLine(remaining: c.remaining) == "Atrasou? Ajustei: faltam 6 paradas.")
        #expect(DayText.adjustedLine(remaining: 1) == "Atrasou? Ajustei: falta 1 parada.")
    }

    @Test func naoAjustaQuandoNinguemAtrasou() {
        // 12:40: o micro s3 (12:30–12:45) está rolando.
        let c = clock(12, 40)
        #expect(c.adjusted == false)
        #expect(c.now?.current.id == "s3")
    }

    @Test func ancorasNuncaSeMexem() throws {
        // Atrasa feio: 17:50, com tudo do dia sem feito.
        var open = plan
        open.stops = open.stops.map { var s = $0; s.done = false; return s }
        let c = clock(17, 50, plan: open)
        let result = try #require(c.plan)
        for anchor in plan.stops where anchor.kind == .anchor {
            let after = try #require(result.stops.first { $0.id == anchor.id })
            #expect(after.start == anchor.start && after.end == anchor.end, "\(anchor.label) mudou de hora")
        }
        // Reserva das 19:00 e o jantar continuam no relógio.
        let activeIds = Set(c.active?.stops.map(\.id) ?? [])
        #expect(activeIds.contains("s8"))
        // O que passou do golden sem feito (Fuunji, golden) ficou pra depois.
        #expect(c.skippedIds.contains("s4"))
    }

    @Test func musticaForaDeHoraAndaParaFrenteSemPassarDaAncora() throws {
        // Fuunji (14:35) ainda não começou, mas você está a 40 min dele: anda pra frente o necessário.
        var far = plan
        far.stops = far.stops.map { s in
            var s = s
            if s.id == "s4" { s.lat = 35.6896; s.lng = 139.7006 }       // Shinjuku
            if s.id == "s3" { s.lat = 35.6654; s.lng = 139.7707 }       // Tsukiji
            return s
        }
        let c = DayClock.make(plan: far, doneIds: [], at: at(14, 30), region: region,
                              position: CLLocationCoordinate2D(latitude: 35.6654, longitude: 139.7707))
        let fuunji = try #require(c.plan?.stops.first { $0.id == "s4" })
        if c.skippedIds.contains("s4") {
            // Não coube antes do golden (âncora): sai da conta, a âncora fica.
            #expect(c.plan?.stops.first { $0.id == "s5" }?.start == plan.stops[4].start)
        } else {
            #expect(fuunji.start >= at(14, 35))
            #expect(fuunji.end <= plan.stops[4].start)
        }
    }

    @Test func nadaDeOutraCidadeEntra() throws {
        // O ajuste só reordena/atrasa o que já era do dia: nenhum id novo, nenhuma parada fora do plano.
        let c = clock(14, 20)
        let before = Set(plan.stops.map(\.id))
        let after = Set((c.plan?.stops ?? []).map(\.id))
        #expect(after.isSubset(of: before))
        #expect(c.plan?.stops.count == plan.stops.count)
    }

    @Test func ordemContinuaCoerente() throws {
        var open = plan
        open.stops = open.stops.map { var s = $0; s.done = false; return s }
        for (h, m) in [(9, 0), (13, 0), (14, 20), (16, 45), (18, 20)] {
            let c = clock(h, m, plan: open)
            let active = c.active?.stops ?? []
            // Em ordem de início, sem sobreposição entre quem continua.
            for (a, b) in zip(active, active.dropFirst()) {
                #expect(a.start <= b.start, "\(h):\(m) \(a.label) depois de \(b.label)")
                #expect(a.end <= b.start.addingTimeInterval(60), "\(h):\(m) \(a.label) invade \(b.label)")
            }
            // Nada que continua começa antes de agora, salvo o que está rolando.
            if let now = c.now {
                for s in active where s.id != now.current.id { #expect(s.start >= at(h, m) || s.kind == .anchor) }
            }
        }
    }

    @Test func replanEhDeterministico() throws {
        let a = clock(14, 20), b = clock(14, 20)
        #expect(a.plan == b.plan)
        #expect(a.skippedIds == b.skippedIds)
    }

    // MARK: Textos da capa

    @Test func capaDizAjusteEmVezDeDeveria() {
        let line = SuggestCopy.stateLine(region: region, now: at(14, 20), plan: SuggestPlanStop(id: "s4", placeId: nil, label: "Fuunji", action: "saia 15:29", lat: nil, lng: nil, lateSince: nil),
                                         openNearby: 2, adjustedRemaining: 6)
        #expect(line == "14:20 · Atrasou? Ajustei: faltam 6 paradas")
        #expect(!line.contains("deveria"))
    }

    @Test func capaLongeDoPlanoDizOndeE() {
        let stop = SuggestPlanStop(id: "s5", placeId: "j104", label: "Shinjuku Gyoen", action: "saia 16:29", lat: 35.6852, lng: 139.7100,
                                   lateSince: nil, away: 18)
        let line = SuggestCopy.stateLine(region: region, now: at(15, 40), plan: stop, openNearby: 0, awayMinutes: 18)
        #expect(line == "15:40 · agora: Shinjuku Gyoen · a 18 min daqui · saia 16:29")
        // Perto (< 10 min): sem o aviso.
        let near = SuggestCopy.stateLine(region: region, now: at(15, 40), plan: stop, openNearby: 0, awayMinutes: nil)
        #expect(near == "15:40 · agora: Shinjuku Gyoen · saia 16:29")
    }

    @Test func awayMinutesSoQuandoLonge() {
        let nakano = CLLocationCoordinate2D(latitude: 35.7078, longitude: 139.6638)
        let gyoen = SuggestPlanStop(id: "s5", placeId: nil, label: "Gyoen", action: "", lat: 35.6852, lng: 139.7100, lateSince: nil)
        let away = CapaSuggestState.awayMinutes(from: nakano, to: gyoen)
        #expect((away ?? 0) >= 10)
        #expect(CapaSuggestState.awayMinutes(from: CLLocationCoordinate2D(latitude: 35.6853, longitude: 139.7101), to: gyoen) == nil)
        #expect(CapaSuggestState.awayMinutes(from: nakano, to: nil) == nil)
    }

    @Test func numeralETextoContamAMesmaCoisa() {
        let n = SuggestCopy.stateLine(region: region, now: at(18, 10), plan: nil, openNearby: 2, unconfirmed: 6)
        #expect(n == "18:10 · nada marcado · 2 abertos a 10 min · 6 sem horário confirmado")
        #expect(SuggestCopy.stateLine(region: region, now: at(18, 10), plan: nil, openNearby: 1) == "18:10 · nada marcado · 1 aberto a 10 min")
        #expect(SuggestCopy.stateLine(region: region, now: at(18, 10), plan: nil, openNearby: 0) == "18:10 · nada marcado")
    }

    @Test func capaDiaAjustadoMostraFaltam() throws {
        let c = clock(14, 20)
        let capa = CapaContent.build(.init(region: region, now: at(14, 20), plan: c.plan, dayNow: c.now, skippedIds: c.skippedIds,
                                           areaName: "Shinjuku", cityName: "Tóquio", tripDay: (3, 14), tempText: nil, sky: nil,
                                           sunset: nil, spentToday: nil))
        #expect(capa.agora?.title == "Ajustei · faltam 6")
    }
}
