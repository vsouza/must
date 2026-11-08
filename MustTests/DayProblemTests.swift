import Foundation
import Testing
@testable import Must

/// Relatório do viajante, problema 7 e correções pequenas: dia de chegada, de troca de cidade, último dia; "Boa tarde";
/// hero sem foto; "saia às" do voo só no dia; chegada e terminal.
@MainActor
struct DayProblemTests {
    private let region = Region.jp
    private var cal: Calendar { region.calendar }

    private func at(_ day: Int, _ h: Int = 0, _ m: Int = 0, month: Int = 11) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
    }

    private var tokyo: City {
        City(id: "tokyo1", name: "Tóquio", from: at(11), to: at(15), tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76,
             lodging: CityLodging(name: "Hotel Gracery", neighborhood: "Shinjuku", checkIn: at(11, 15), checkOut: at(15, 11)))
    }
    private var kyoto: City {
        City(id: "kyoto", name: "Kyoto", from: at(15), to: at(20), tz: "Asia/Tokyo", currency: "JPY", lat: 35.01, lng: 135.76,
             lodging: CityLodging(name: "Machiya Gion", checkIn: at(15, 15), checkOut: at(20, 10)))
    }
    private var tokyo2: City {
        City(id: "tokyo2", name: "Tóquio", from: at(20), to: at(24), tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76)
    }

    /// GRU → NRT, pousa 11 nov 15:40 (Tóquio).
    private var inbound: FlightSegment {
        FlightSegment(number: "LA 8084", from: "GRU", to: "NRT", departs: at(10, 6), arrives: at(11, 15, 40), arrivalTerminal: "2")
    }
    /// HND → GRU, sai 24 nov 18:25.
    private var outbound: FlightSegment {
        FlightSegment(number: "LA 8085", from: "HND", to: "GRU", departs: at(24, 18, 25), arrives: at(24, 23, 0))
    }

    private func detect(_ day: Int, _ h: Int = 9, saveForEnd: Int = 0, cities: [City]? = nil) -> DayProblem? {
        DayProblem.detect(on: at(day, h), now: at(day, h), region: region, cities: cities ?? [tokyo, kyoto, tokyo2],
                          legs: [inbound, outbound], tripEnd: at(24), saveForEnd: saveForEnd)
    }

    // MARK: Chegada

    @Test func diaDeChegada() throws {
        let p = try #require(detect(11, 9))
        #expect(p.kind == .arrival && p.light)
        #expect(p.headline == "Pouso 15:40 NRT T2 · hotel em Shinjuku · sem plano pesado hoje")
        #expect(p.hero == "pouso 15:40")
    }

    @Test func depoisDePousarDizPousou() throws {
        let p = try #require(detect(11, 17))
        #expect(p.headline.hasPrefix("Pousou 15:40 NRT"))
    }

    @Test func chegadaSemHotelPedeOCadastro() throws {
        var bare = tokyo
        bare.lodging = nil
        let p = try #require(detect(11, 9, cities: [bare, kyoto, tokyo2]))
        #expect(p.headline.contains("cadastre o hotel"))
    }

    @Test func vooDeIdaQueSaiDoBrasilNaoEChegadaNoBrasil() {
        // O voo de volta pousa em GRU (BR): não é dia de chegada na viagem ao Japão.
        #expect(DayProblem.arrivalLeg(on: at(24), region: region, legs: [inbound, outbound]) == nil)
        #expect(DayProblem.arrivalLeg(on: at(11), region: region, legs: [inbound, outbound])?.number == "LA 8084")
    }

    // MARK: Troca de cidade

    @Test func diaDeTrem() throws {
        let p = try #require(detect(15, 8))
        #expect(p.kind == .transfer)
        #expect(p.headline == "Trem pra Kyoto · mala · check-out 11h · check-in 15h")
        #expect(p.hero == "trem pra Kyoto")
        #expect(!p.light)
    }

    @Test func trocaSemCheckOutCadastrado() throws {
        var t = tokyo
        t.lodging = nil
        let p = try #require(detect(15, 8, cities: [t, kyoto, tokyo2]))
        #expect(p.headline.hasPrefix("Trem pra Kyoto · mala · check-out do hotel"))
    }

    @Test func diaNormalNaoTemProblema() {
        #expect(detect(13, 9) == nil)
        #expect(detect(17, 9) == nil)
    }

    @Test func tokyo1ETokyo2ContamComoMesmaCidade() {
        let a = City(id: "tokyo1", name: "Tóquio", from: at(1), to: at(5), tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76)
        let b = City(id: "tokyo2", name: "Tóquio", from: at(5), to: at(9), tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76)
        #expect(DayProblem.detect(on: at(5, 9), now: at(5, 9), region: region, cities: [a, b], legs: [], tripEnd: at(9)) == nil)
    }

    // MARK: Último dia

    @Test func ultimoDiaComVooHoje() throws {
        let p = try #require(detect(24, 8, saveForEnd: 3))
        #expect(p.kind == .lastDay)
        // 18:25 − 3 h − 1 h de trajeto = 14:25.
        #expect(p.headline == "Último dia: fica pro fim (3) · tax-free · saia pro aeroporto às 14:25")
        #expect(p.leaveAt == at(24, 14, 25))
        #expect(p.hero == "saia às 14:25")
    }

    @Test func vesperaComVooAmanha() throws {
        let p = try #require(DayProblem.detect(on: at(23, 9), now: at(23, 9), region: region, cities: [tokyo, kyoto, tokyo2],
                                               legs: [inbound, outbound], tripEnd: at(24)))
        #expect(p.kind == .lastDay)
        #expect(p.headline.contains("voo amanhã 18:25 HND"))
        #expect(p.leaveAt == nil)
    }

    @Test func ultimoDiaSemVooCadastradoUsaADataDaViagem() throws {
        let p = try #require(DayProblem.detect(on: at(24, 9), now: at(24, 9), region: region, cities: [tokyo2], legs: [], tripEnd: at(24)))
        #expect(p.kind == .lastDay)
        #expect(p.headline.hasPrefix("Último dia:"))
        #expect(!p.headline.contains("aeroporto"))
    }

    // MARK: Textos

    @Test func capaDiaProblemaMandaNaLinhaPrincipal() throws {
        let p = try #require(detect(11, 9))
        let line = SuggestCopy.stateLine(region: region, now: at(11, 15, 30), plan: nil, openNearby: 3, problem: p)
        #expect(line == "15:30 · Pouso 15:40 NRT T2 · hotel em Shinjuku · sem plano pesado hoje")
    }

    @Test func bomDiaViraBoaTardeDepoisDoMeioDia() {
        #expect(DayText.greeting(at(15, 9), region: region) == "Bom dia.")
        #expect(DayText.greeting(at(15, 12), region: region) == "Boa tarde.")
        #expect(DayText.greeting(at(15, 17, 59), region: region) == "Boa tarde.")
        #expect(DayText.greeting(at(15, 18), region: region) == "Boa noite.")
        #expect(DayText.wakeWord(at(15, 9), region: region) == "acordou")
        #expect(DayText.wakeWord(at(15, 15, 30), region: region) == "agora")
    }

    @Test func heroSemFotoMostraAProximaAcao() {
        let stop = SuggestPlanStop(id: "s5", placeId: nil, label: "Shinjuku Gyoen", action: "saia 15:46", lat: nil, lng: nil, lateSince: nil)
        #expect(CapaSuggestState.heroAction(problem: nil, plan: stop, adjusted: false, region: region) == "saia às 15:46 · Shinjuku Gyoen")
        let arrive = SuggestPlanStop(id: "s4", placeId: nil, label: "Fuunji", action: "chegue 14:35", lat: nil, lng: nil, lateSince: nil)
        #expect(CapaSuggestState.heroAction(problem: nil, plan: arrive, adjusted: false, region: region) == "chegue às 14:35 · Fuunji")
        #expect(CapaSuggestState.heroAction(problem: nil, plan: nil, adjusted: false, region: region) == nil)
        let problem = DayProblem(kind: .arrival, headline: "x", title: "Dia de chegada", hero: "pouso 15:40", light: true, leaveAt: nil)
        #expect(CapaSuggestState.heroAction(problem: problem, plan: stop, adjusted: false, region: region) == "pouso 15:40")
    }

    // MARK: Voo

    @Test func saiaAsDoVooSoNoDiaDoVoo() {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        let leave = at(24, 14, 25)
        #expect(FlightRules.leaveChipApplies(leave: leave, now: at(24, 8), zone: zone))
        #expect(!FlightRules.leaveChipApplies(leave: leave, now: at(10, 8), zone: zone))
        #expect(!FlightRules.leaveChipApplies(leave: leave, now: at(23, 22), zone: zone))
    }

    @Test func vooMostraChegadaETerminal() {
        #expect(FlightRules.arrivalChip(inbound, fallback: region.timeZone) == "pouso NRT 15:40 · terminal 2")
        var noTerminal = inbound
        noTerminal.arrivalTerminal = nil
        #expect(FlightRules.arrivalChip(noTerminal, fallback: region.timeZone) == "pouso NRT 15:40")
        var unknown = inbound
        unknown.arrives = nil
        #expect(FlightRules.arrivalChip(unknown, fallback: region.timeZone) == nil)
    }

    @Test func terminalDePousoVemDaAPI() throws {
        let json = """
        [{"status":"Expected","departure":{"airport":{"iata":"GRU"},"terminal":"3","gate":"B12","scheduledTime":{"local":"2026-11-10 22:06+00:00"}},
          "arrival":{"airport":{"iata":"NRT"},"terminal":"2","scheduledTime":{"local":"2026-11-11 15:40+09:00"}}}]
        """
        let parsed = try AeroDataBoxParser.parse(Data(json.utf8), departureIATA: "GRU")
        let report = try #require(parsed)
        #expect(report.terminal == "3")
        #expect(report.arrivalTerminal == "2")
    }

    @Test func segmentoAntigoSemTerminalDePousoAindaLe() throws {
        let data = try JSONEncoder.board(timeZone: .gmt).encode(inbound)
        let any = try JSONSerialization.jsonObject(with: data)
        var object = try #require(any as? [String: Any])
        object.removeValue(forKey: "arrivalTerminal")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.board.decode(FlightSegment.self, from: old)
        #expect(decoded.arrivalTerminal == nil)
        #expect(decoded.number == "LA 8084")
    }
}
