import CoreLocation
import Foundation
import Testing
@testable import Must

/// `SuggestionEngine` (prompt 26 §2): cenários fixos. Lourdes 18:10 nublado, sem dia montado.
@MainActor
struct SuggestionEngineTests {
    private let region = Region.bh
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: h, minute: m))!
    }
    /// Lourdes.
    private let here = CLLocationCoordinate2D(latitude: -19.9340, longitude: -43.9440)

    /// A `meters` m ao norte de `here`.
    private func place(_ id: String, _ name: String, list: String = "drink", color: String = "drink", kind: ListKind = .place,
                       meters: Double = 240, state: OpenState = .unknown, windows: [String] = ["night"], done: Bool = false,
                       sub: String? = nil) -> SuggestPlace {
        SuggestPlace(id: id, name: name, listName: list, color: color, kind: kind, sub: sub,
                     lat: here.latitude + meters / 1.25 / 111_000, lng: here.longitude, done: done, state: state, windows: Set(windows))
    }

    private func event(_ id: String = "bandsintown:1", minutes: Int = 110, meters: Double = 500) -> ShowEvent {
        ShowEvent(id: id, placeId: nil, kind: .show, title: "Noite Belga", venue: "Bar", lat: here.latitude + meters / 1.25 / 111_000, lng: here.longitude,
                  startsAt: at(18, 10).addingTimeInterval(Double(minutes) * 60), runsUntil: nil, sessions: [], priceText: "R$ 30", url: nil,
                  source: .bandsintown, checkedAt: nil)
    }

    private func inputs(_ places: [SuggestPlace], events: [ShowEvent] = [], now: Date? = nil) -> SuggestInputs {
        SuggestInputs(region: region, now: now ?? at(18, 10), here: here, places: places, events: events,
                      boardNames: Set(places.map { $0.name.lowercased() }))
    }

    @Test func lourdes1810() {
        let cards = SuggestionEngine.suggest(inputs([
            place("p08", "Café com Letras", state: .open(until: "22:00"), windows: ["afternoon", "night"], sub: "Café"),
            place("p04", "Glouton", list: "eat", color: "eat", meters: 420, windows: ["dinner"]),
            place("p09", "Albanos", meters: 700, windows: ["night"]),
            place("x1", "Livraria fechada", list: "shop", color: "shop", meters: 300, state: .closed(opensDay: nil, opensAt: "09:00"), windows: []),
            place("x2", "Já fiz", meters: 100, windows: ["night"], done: true),
            place("far", "Longe demais", meters: 3000, windows: ["night"]),
        ], events: [event()]))
        #expect(cards.count == 4)
        #expect(cards.filter { $0.kind == .event }.count == 1)
        let ids = Set(cards.map(\.id))
        #expect(ids.contains("must:p08") && ids.contains("event:bandsintown:1"))
        #expect(!ids.contains("must:x1") && !ids.contains("must:x2") && !ids.contains("must:far"))
        let cafe = cards.first { $0.id == "must:p08" }
        #expect(cafe?.label == "MUST DRINK · ABERTO")
        #expect(cafe?.trailing == "240 m")
        #expect(cafe?.meta.hasPrefix("fecha 22h") == true)
        #expect(cafe?.reasons.contains("no board") == true && cafe?.reasons.contains("perto") == true)
        #expect(cards.first { $0.kind == .event }?.style == .orange)
    }

    @Test func umEventoNoMaximo() {
        let cards = SuggestionEngine.suggest(inputs([place("a", "A")], events: [event("e1"), event("e2", minutes: 60), event("e3", minutes: 30)]))
        #expect(cards.filter { $0.kind == .event }.count == 1)
    }

    @Test func eventoLongeOuTardeNaoEntra() {
        let cards = SuggestionEngine.suggest(inputs([], events: [event("late", minutes: 300), event("far", meters: 5000)]))
        #expect(cards.filter { $0.kind == .event }.isEmpty)
    }

    @Test func fechaLogoSobe() {
        let cards = SuggestionEngine.suggest(inputs([
            place("a", "Calma", state: .open(until: "23:00"), windows: ["night"]),
            place("b", "Fecha logo", meters: 600, state: .open(until: "18:50"), windows: ["night"]),
        ]))
        #expect(cards.first?.id == "must:b")
        #expect(cards.first?.kind == .closing)
        #expect(cards.first?.label.hasSuffix("FECHA LOGO") == true)
        #expect(cards.first?.reasons.first == "fecha em 40 min")
    }

    @Test func fechamentoDepoisDaMeiaNoite() {
        #expect(SuggestionEngine.minutesUntil("02:00", now: at(23, 30), region: region) == 150)
        #expect(SuggestionEngine.minutesUntil("22:00", now: at(18, 10), region: region) == 230)
    }

    @Test func janelaDoLugarManda_quandoNaoHaHorario() {
        let cards = SuggestionEngine.suggest(inputs([
            place("m", "Café da manhã", color: "coffee", windows: ["morning"]),
            place("n", "Bar da noite", windows: ["night"]),
        ]))
        #expect(cards.map(\.id) == ["must:n"])
        #expect(SuggestionEngine.suggest(inputs([place("m", "Café da manhã", color: "coffee", windows: ["morning"])], now: at(8, 30))).map(\.id) == ["must:m"])
    }

    @Test func planoVemPrimeiro() {
        var i = inputs([place("a", "A", state: .open(until: "19:00"), windows: ["night"])])
        i.plan = SuggestPlanStop(id: "s1", placeId: "p9", label: "Mercado Novo", action: "saia 18:40", lat: nil, lng: nil, lateSince: at(17, 40))
        let cards = SuggestionEngine.suggest(i)
        #expect(cards.first?.kind == .plan)
        #expect(cards.first?.meta == "saia 18:40 · desde 17:40")
    }

    @Test func naoMeSugereIssoHoje() {
        var i = inputs([place("a", "A"), place("b", "B", meters: 600)])
        i.dismissed = ["must:a"]
        #expect(SuggestionEngine.suggest(i).map(\.id) == ["must:b"])
    }

    @Test func repeticaoDesce() {
        var i = inputs([place("a", "A", meters: 200), place("b", "B", meters: 210)])
        #expect(SuggestionEngine.suggest(i).first?.id == "must:a")
        i.shownEarlier = ["must:a"]
        #expect(SuggestionEngine.suggest(i).first?.id == "must:b")
    }

    @Test func chuvaSobeOCoberto() {
        var i = inputs([place("o", "Praça", windows: ["night"], sub: "Praça"), place("m", "Museu", list: "art", color: "see", kind: .art, windows: ["night"], sub: "Museu")])
        i.rainInMinutes = 40
        let cards = SuggestionEngine.suggest(i)
        #expect(cards.first?.id == "must:m")
        #expect(cards.first?.reasons.first == "chuva em 40 min · coberto")
    }

    @Test func luzDeAmanhaComMustPhoto() {
        var i = inputs([place("ph", "Mirante", list: "photo", color: "photo", kind: .photo, meters: 800, windows: [])])
        i.light = SuggestLight(start: at(17, 20).addingTimeInterval(86_400), end: at(17, 58).addingTimeInterval(86_400), isToday: false)
        let card = SuggestionEngine.suggest(i).first
        #expect(card?.kind == .light)
        #expect(card?.label == "MUST PHOTO · GOLDEN amanhã 17:20")
    }

    @Test func indicadoSoQuandoSobraVagaEForaDoBoard() {
        var i = inputs([place("a", "A")])
        let hot = NearbyPlace(name: "Bar Novo", lat: here.latitude + 0.003, lng: here.longitude, sources: [.google, .foursquare], rating: 4.6, ratingCount: 800,
                              openNow: true, category: "bar", popularity: 0.95)
        let onBoard = NearbyPlace(name: "A", lat: here.latitude, lng: here.longitude, sources: [.google], rating: 4.9, ratingCount: 900, openNow: true)
        let wiki = NearbyPlace(name: "Igreja", lat: here.latitude, lng: here.longitude, sources: [.wikipedia])
        i.indicated = [hot, onBoard, wiki]
        let cards = SuggestionEngine.suggest(i)
        #expect(cards.filter { $0.kind == .indicated }.count == 1)
        #expect(cards.last?.title == "Bar Novo")
        #expect(cards.last?.reasons.contains("em alta hoje") == true)
        // Sem vaga (4 cartões já): nada de indicado.
        i = inputs((0..<5).map { place("m\($0)", "M\($0)", meters: 200 + Double($0) * 10) })
        i.indicated = [hot]
        #expect(SuggestionEngine.suggest(i).count == 4)
        #expect(!SuggestionEngine.suggest(i).contains { $0.kind == .indicated })
    }

    @Test func capaNuncaFicaVazia() {
        // Tudo fechado: sem cartão "de verdade", cai nos mais perto do board.
        let cards = SuggestionEngine.suggest(inputs([
            place("a", "A", state: .closed(opensDay: nil, opensAt: "09:00")), place("b", "B", meters: 500, state: .closed(opensDay: nil, opensAt: "09:00")),
        ]))
        #expect(!cards.isEmpty)
        #expect(cards.allSatisfy { $0.kind == .must })
    }

    @Test func semRedeNaoTemEventoMasTemCartao() {
        // Modo avião = sem eventos nem indicados no cache.
        let cards = SuggestionEngine.suggest(inputs([place("a", "A", state: .open(until: "22:00")), place("b", "B", meters: 500, windows: ["night"]),
                                                      place("c", "C", meters: 700, windows: ["night"])]))
        #expect((3...4).contains(cards.count))
        #expect(cards.allSatisfy { $0.kind != .event && $0.kind != .indicated })
    }

    @Test func recalculaRapido() {
        var many: [SuggestPlace] = []
        for n in 0..<600 {
            let state: OpenState = n % 3 == 0 ? .open(until: "22:00") : .unknown
            many.append(place("p\(n)", "P\(n)", meters: Double(100 + n * 5), state: state))
        }
        let i = inputs(many, events: [event()])
        let start = Date()
        _ = SuggestionEngine.suggest(i)
        #expect(Date().timeIntervalSince(start) < 0.2)
    }

    @Test func gostoSoComUmasPoucasListas() {
        let places = [place("a", "A", color: "eat", done: true), place("b", "B", color: "eat", done: true), place("c", "C", color: "drink", done: true),
                      place("d", "D", color: "shop", done: true)]
        #expect(CapaSuggestState.taste(places) == ["eat": 2, "drink": 1])
    }
}

/// Capa longe da cidade do board (GPS em Narita): nunca sugere Must a dezenas de km.
@MainActor
struct SuggestionFarTests {
    @Test func naritaNaoSugereMustA60km() {
        let narita = CLLocationCoordinate2D(latitude: 35.7720, longitude: 140.3929)
        let far = SuggestPlace(id: "k", name: "Kameido Gyoza", listName: "eat", color: "eat", kind: .place, sub: nil,
                               lat: 35.6980, lng: 139.8250, done: false, state: .unknown, windows: [])
        let inputs = SuggestInputs(region: .jp, now: Date(), here: narita, places: [far], events: [], boardNames: ["kameido gyoza"])
        #expect(SuggestionEngine.suggest(inputs).isEmpty)
    }

    @Test func fallbackPertoAindaFunciona() {
        let here = CLLocationCoordinate2D(latitude: 35.6900, longitude: 139.7000)
        let near = SuggestPlace(id: "n", name: "Perto", listName: "eat", color: "eat", kind: .place, sub: nil,
                                lat: 35.6930, lng: 139.7000, done: false, state: .closed(opensDay: nil, opensAt: "09:00"), windows: [])
        let inputs = SuggestInputs(region: .jp, now: Date(), here: here, places: [near], events: [], boardNames: ["perto"])
        #expect(SuggestionEngine.suggest(inputs).map(\.id) == ["must:n"])
    }
}

/// A foto do bloco acompanha o bairro buscado no quero.
@MainActor
struct BlockPhotoTests {
    let capa = URL(string: "https://x/shinjuku.jpg")
    let nakano = URL(string: "https://x/nakano.jpg")

    @Test func bairroBuscadoUsaAFotoDele() {
        #expect(CapaState.blockPhoto(searchedAreaId: "nakano", capaAreaId: "shinjuku", searched: nakano, capa: capa) == nakano)
    }
    @Test func semFotoDoBairroBuscadoFicaSemFoto() {
        #expect(CapaState.blockPhoto(searchedAreaId: "nakano", capaAreaId: "shinjuku", searched: nil, capa: capa) == nil)
    }
    @Test func mesmoBairroOuSemBuscaUsaACapa() {
        #expect(CapaState.blockPhoto(searchedAreaId: "shinjuku", capaAreaId: "shinjuku", searched: nil, capa: capa) == capa)
        #expect(CapaState.blockPhoto(searchedAreaId: nil, capaAreaId: "shinjuku", searched: nakano, capa: capa) == capa)
    }
}
