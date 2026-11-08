import CoreLocation
import Foundation
import Testing
@testable import Must

/// Relatório do viajante, problema 3: o app só afirma o que sabe. Horário/coordenada confirmados (Google) × estimados (seed).
@MainActor
struct DataConfidenceTests {
    private let region = Region.jp
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)

    private func hours() -> PlaceHours {
        let all = (0..<7).map { PlaceHours.Period(open: .init(day: $0, hour: 9, minute: 0), close: .init(day: $0, hour: 21, minute: 0)) }
        return PlaceHours(weekdayText: nil, periods: all, fetchedAt: nil)
    }

    // MARK: Lugar

    @Test func seedSemHorarioNemCoordenadaEEstimado() {
        let p = Place(id: "j1", name: "Ramen", cityId: "tokyo1", lat: 35.69, lng: 139.70)
        p.approx = true
        #expect(p.trust == PlaceTrust(hoursConfirmed: false, coordConfirmed: false))
        #expect(p.trust.microLabel == "horário estimado · local aproximado")
        #expect(p.trust.isConfirmed == false)
    }

    @Test func soUmDosDoisFalta() {
        let p = Place(id: "j1", name: "Ramen", cityId: "tokyo1", lat: 35.69, lng: 139.70)
        #expect(p.trust.microLabel == "horário estimado")      // coordenada ok (approx falso), sem horário
        p.hours = hours()
        p.approx = true
        #expect(p.trust.microLabel == "local aproximado")
    }

    @Test func confirmadoNaoTemRotulo() {
        let p = Place(id: "j1", name: "Ramen", cityId: "tokyo1", lat: 35.69, lng: 139.70)
        p.hours = hours()
        #expect(p.trust.isConfirmed)
        #expect(p.trust.microLabel == nil)
        // Horário vazio (sem períodos) não é confirmado.
        p.hours = PlaceHours(weekdayText: ["seg: fechado"], periods: [], fetchedAt: nil)
        #expect(p.trust.hoursConfirmed == false)
    }

    @Test func linhaDeConfirmacaoDeAjustes() {
        let c = BoardConfidence(total: 105, confirmed: 94)
        #expect(c.headline == "105 lugares · 94 confirmados")
        #expect(c.pending == 11)
        #expect(c.detail(onWiFi: false) == "sincronizar no Wi-Fi · faltam 11")
        #expect(c.detail(onWiFi: true) == "toque pra sincronizar os 11 que faltam")
        #expect(BoardConfidence(total: 3, confirmed: 3).detail(onWiFi: true) == "tudo confirmado no Google")
        #expect(BoardConfidence(total: 1, confirmed: 1).headline == "1 lugar · 1 confirmado")
        #expect(BoardConfidence(total: 0, confirmed: 0).detail(onWiFi: true) == "nada no board ainda")
        let a = Place(id: "a", name: "A", cityId: "t")
        a.hours = hours()
        let b = Place(id: "b", name: "B", cityId: "t")
        b.approx = true
        #expect(BoardConfidence([a, b]) == BoardConfidence(total: 2, confirmed: 1))
    }

    @Test func seedDoJapaoComecaQuaseTodoEstimado() throws {
        let board = try BoardCodec.decode(Data(contentsOf: Region.jp.seedURL(in: Bundle(for: DayFixtures.Token.self))!))
        let approx = board.places.filter { $0.approx == true }.count
        #expect(approx > board.places.count / 2, "o seed do Japão é majoritariamente chute: a tela precisa dizer")
    }

    // MARK: Índice da capa

    private func suggestPlace(state: OpenState, approx: Bool) -> SuggestPlace {
        SuggestPlace(id: "p", name: "Ramen", listName: "eat", color: "eat", kind: .place, sub: nil,
                     lat: shinjuku.latitude + 0.001, lng: shinjuku.longitude, done: false, state: state, windows: ["lunch"], approx: approx)
    }

    private func cards(_ p: SuggestPlace) -> [Suggestion] {
        let noon = region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12, minute: 20))!
        return SuggestionEngine.mustCards(SuggestInputs(region: region, now: noon, here: shinjuku, places: [p]))
    }

    @Test func abertoAgoraSoComHorarioConfirmado() throws {
        let confirmed = try #require(cards(suggestPlace(state: .open(until: "21:00"), approx: false)).first)
        #expect(confirmed.label.hasSuffix("ABERTO"))
        #expect(confirmed.trust == nil)
        let guess = try #require(cards(suggestPlace(state: .unknown, approx: true)).first)
        #expect(!guess.label.contains("ABERTO"))
        #expect(guess.label.hasSuffix("HORÁRIO NÃO CONFIRMADO"))
        #expect(guess.trust == "horário estimado · local aproximado")
        let line = CorteIndexLine(guess)
        #expect(line.trust == "horário estimado · local aproximado")
    }

    @Test func numeralNaoContaHorarioDesconhecidoComoAberto() {
        let open = suggestPlace(state: .open(until: "21:00"), approx: false)
        var unknown = suggestPlace(state: .unknown, approx: true)
        unknown.id = "q"; unknown.name = "Outro"
        let counts = CorteCount.counts(places: [open, unknown], indicated: [], here: shinjuku)
        #expect(counts.open == 1)
        #expect(counts.unconfirmed == 1)
        #expect(CorteCount.openWithin10(places: [open, unknown], indicated: [], here: shinjuku) == 1)
    }

    // MARK: "Dá hoje" e "não dá hoje" com motivo

    private func row(until: String?, minutes: Int, fits: Bool) -> QueroRow {
        let r = WantResult(id: "board:x", name: "Café", lat: 35.69, lng: 139.70, origin: .board, boardPlaceId: "x", until: until)
        let at = Date()
        let slot = fits ? DayFit.Slot(start: at, end: at.addingTimeInterval(1500), after: nil, before: nil, travelIn: 5, detour: 0) : nil
        return QueroRow(result: r, minutes: minutes, slot: slot, meta: "", otherDay: nil, areaId: nil)
    }

    private func at(_ h: Int, _ m: Int) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: h, minute: m))!
    }

    @Test func dahojeSoAfirmaAbertoComHorario() {
        #expect(CorteSplit.reason(row(until: "19h", minutes: 8, fits: true), isBoard: true) == "do seu board · aberto até 19h")
        #expect(CorteSplit.reason(row(until: nil, minutes: 8, fits: true), isBoard: true) == "do seu board · horário não confirmado")
    }

    @Test func naoDaHojeSempreTemMotivo() {
        // Chega depois de fechar: "a 26 min e fecha 17h".
        #expect(CorteSplit.reason(row(until: "17h", minutes: 26, fits: false), isBoard: true, now: at(16, 40), region: region)
                == "a 26 min e fecha 17h")
        // Fecha cedo, mas dava pra chegar: o dia é que não cabe.
        #expect(CorteSplit.reason(row(until: "15h", minutes: 5, fits: false), isBoard: true, now: at(10, 0), region: region)
                == "fecha 15h · não cabe no dia")
        // Sem horário: diz que não sabe, nunca "não dá hoje" seco.
        #expect(CorteSplit.reason(row(until: nil, minutes: 5, fits: false), isBoard: true, now: at(10, 0), region: region)
                == "dia cheio · horário não confirmado")
        let r = CorteSplit.line(row(until: "15h", minutes: 26, fits: false), meters: 2_100, origin: shinjuku, region: region,
                                walkMaxKm: 1.5, now: at(14, 50))
        #expect(!r.reason.isEmpty && r.reason != "não dá hoje")
    }

    @Test func lugarSemHorarioDizNaoConfirmado() {
        let p = Place(id: "j1", name: "Ramen", cityId: "tokyo1", lat: 35.69, lng: 139.70)
        #expect(PlaceFicha.openTag(p, region: region, now: at(12, 0)) == "horário não confirmado")
        #expect(PlaceFicha.coordTag(p) == nil)
        p.approx = true
        #expect(PlaceFicha.coordTag(p) == "local aproximado")
        p.windowsRaw = ["lunch"]
        #expect(PlaceFicha.hours(p, region: region, now: at(12, 0)).hasSuffix("estimado"))
        p.hours = hours()
        #expect(PlaceFicha.openTag(p, region: region, now: at(12, 0)) == "aberto até 21:00")
    }
}
