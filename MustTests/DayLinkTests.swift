import Foundation
import Testing
@testable import Must

/// Link do dia (prompt 25 · B.2): o dia vai inteiro dentro de `must://d/<payload>` (JSON → zlib → base64url) e volta igual,
/// sem servidor. Payload quebrado, cortado ou gigante não abre nada.
@MainActor
struct DayLinkTests {
    private var qa: DayPlan { DayEngineStub.qaDay }

    private func shared() -> SharedDay {
        SharedDay(plan: qa, region: .jp, areaName: "Shinjuku", cityName: "Tóquio",
                  coordinates: ["j05": (35.6896, 139.6995), "j104": (35.6852, 139.7101), "j01": (35.6440, 139.6990)])
    }

    @Test func idaEVoltaDevolveAsParadasEOsHorarios() throws {
        let day = shared()
        let url = try DayLink.url(day)
        #expect(url.scheme == "must")
        #expect(url.host() == "d")
        let payload = try #require(DayLink.payload(from: url))
        let back = try DayLink.decode(payload)
        #expect(back == day)
        let plan = try #require(back.plan())
        #expect(plan.date == qa.date)
        #expect(plan.dayNumber == 3)
        #expect(plan.stops.count == qa.stops.count)
        for (a, b) in zip(plan.stops, qa.stops) {
            #expect(a.start == b.start)
            #expect(a.end == b.end)
            #expect(a.label == b.label)
            #expect(a.kind == b.kind)
            #expect(a.placeId == b.placeId)
            #expect(a.tag == b.tag)
        }
    }

    @Test func soParadasHorariosENomesSemFotoNemPreco() throws {
        let payload = try DayLink.payload(shared())
        let packed = try #require(DayLink.unbase64url(payload))
        let json = try #require(DayLink.decompress(packed))
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("http"))
        #expect(!text.contains("22.000"))     // nota da reserva (preço) fica fora
        #expect(!text.contains("omakase"))    // notas ficam fora
        #expect(text.contains("Udatsu Sushi"))
    }

    @Test func linkCurtoOBastanteProWhatsApp() throws {
        let payload = try DayLink.payload(shared())
        #expect(payload.count < 1_200, "payload com \(payload.count) caracteres")
        #expect(payload.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }, "base64url sem + / =")
    }

    @Test func coordenadaDoBoardEntraArredondada() throws {
        let day = shared()
        let fuunji = try #require(day.s.first { $0.i == "j05" })
        #expect(fuunji.y == 35.6896)
        #expect(fuunji.x == 139.6995)
        #expect(day.s.first { $0.i == nil }?.y == nil) // micro-parada sem coordenada
    }

    @Test func payloadQuebradoNaoAbre() {
        #expect(throws: DayLink.Failure.notBase64) { try DayLink.decode("não é base64!") }
        #expect(throws: DayLink.Failure.tooLong) { try DayLink.decode(String(repeating: "A", count: DayLink.maxPayload + 1)) }
        #expect(throws: (any Error).self) { try DayLink.decode("AAAA") }
        // Cortado no meio (o WhatsApp às vezes corta link longo).
        let payload = (try? DayLink.payload(shared())) ?? ""
        #expect(throws: (any Error).self) { try DayLink.decode(String(payload.prefix(payload.count / 2))) }
    }

    @Test func diaVazioOuRegiaoDesconhecidaNaoAbre() throws {
        var day = shared()
        day.s = []
        #expect(throws: DayLink.Failure.notADay) { try DayLink.decode(try DayLink.payload(day)) }
        day = shared()
        day.r = "xx"
        #expect(throws: DayLink.Failure.notADay) { try DayLink.decode(try DayLink.payload(day)) }
    }

    @Test func payloadDoLink() {
        #expect(DayLink.payload(from: URL(string: "must://d/abc_-9")!) == "abc_-9")
        #expect(DayLink.payload(from: URL(string: "must://d/")!) == nil)
        #expect(DayLink.payload(from: URL(string: "must://lugar/j01")!) == nil)
        #expect(DayLink.payload(from: URL(string: "https://d/abc")!) == nil)
    }

    @Test func routerAbreODiaRecebidoNaAbaHoje() throws {
        let router = AppRouter()
        router.sheet = .assistant
        router.handle(url: try DayLink.url(shared()), region: .bh)
        #expect(router.sheet == nil)
        #expect(router.tab == .hoje)
        guard case .diaRecebido(let payload)? = router.paths[.hoje]?.last else {
            Issue.record("não empilhou o dia recebido")
            return
        }
        #expect(try DayLink.decode(payload).t == "Shinjuku + Tsukiji")
    }

    @Test func horarioDepoisDaMeiaNoiteContinuaNoMesmoDia() throws {
        // Golden Gai até 23:30; um bar até 01:00 é o mesmo dia (minuto > 1440).
        var plan = qa
        plan.stops[8].end = plan.stops[8].end.addingTimeInterval(90 * 60)
        let day = SharedDay(plan: plan, region: .jp, areaName: nil, cityName: nil)
        #expect(day.s[8].e > 1440)
        let back = try #require(try DayLink.decode(try DayLink.payload(day)).plan())
        #expect(back.stops[8].end == plan.stops[8].end)
    }
}
