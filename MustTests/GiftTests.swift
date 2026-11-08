import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Lista de presentes (prompt 31 · item 7): modelo, agrupar por pessoa, previsto, perto da loja, comprado, leitura de texto,
/// ranker da capa, micro-parada e export/import ida e volta.
@MainActor
struct GiftTests {
    private let region = Region.jp
    private let tz = Region.jp.timeZone
    /// Shinjuku, 15/11/2026 14:20.
    private let here = CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034)
    private var now: Date { region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 14, minute: 20))! }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// `meters` ao norte de `here` (linha reta).
    private func store(_ meters: Double) -> (Double, Double) { (here.latitude + meters / 111_000, here.longitude) }

    private func gift(_ id: String, _ title: String, _ person: String, price: Double = 1_000, qty: Int = 1, meters: Double? = nil,
                      store name: String = "Loja", bought: Bool = false, order: Int = 0) -> Gift {
        let g = Gift(id: id, title: title, person: person, quantity: qty, estimatedPrice: price, storeName: name, order: order)
        if let meters { (g.storeLat, g.storeLng) = (here.latitude + meters / 111_000, here.longitude) }
        if bought { g.boughtAt = now; g.paidPrice = price * Double(qty) }
        return g
    }

    // MARK: Modelo

    @Test func modeloTotaisEPadroes() {
        let g = gift("a", "Kit Kat", "Ana", price: 1_200, qty: 3)
        #expect(g.estimatedTotal == 3_600)
        #expect(g.committedTotal == 3_600)
        #expect(!g.isBought)
        g.boughtAt = now
        g.paidPrice = 3_240
        #expect(g.committedTotal == 3_240)
        #expect(Gift(title: "x", quantity: 0).quantity == 1)
        #expect(Gift(title: "x").personName == GiftLogic.noPerson)
    }

    @Test func persisteNoContainer() throws {
        let c = try container()
        c.mainContext.insert(gift("a", "Faca", "Mãe", price: 14_000))
        try c.mainContext.save()
        let all = c.mainContext.gifts()
        #expect(all.count == 1 && all[0].person == "Mãe" && all[0].estimatedPrice == 14_000)
    }

    // MARK: Agrupar, previsto, faltam

    @Test func agrupaPorPessoaPertoPrimeiroDepoisAlfabetica() {
        let items = [gift("1", "Faca", "Mãe"), gift("2", "Pelúcia", "Lucas"), gift("3", "Kit Kat", "Ana"),
                     gift("4", "Caneta", "Ana", bought: true), gift("5", "Algo", "")]
        let alpha = GiftLogic.groups(items).map(\.person)
        #expect(alpha == ["Ana", "Lucas", "Mãe", GiftLogic.noPerson])
        let perto = GiftLogic.groups(items, nearby: ["2"]).map(\.person)
        #expect(perto == ["Lucas", "Ana", "Mãe", GiftLogic.noPerson])
        // Dentro do grupo, o que falta vem antes do comprado.
        #expect(GiftLogic.groups(items).first { $0.person == "Ana" }?.gifts.map(\.id) == ["3", "4"])
    }

    @Test func totalPrevistoEFaltam() {
        let items = [gift("1", "A", "Ana", price: 1_000, qty: 3), gift("2", "B", "Ana", price: 2_950, bought: true),
                     gift("3", "C", "Pedro", price: 2_800)]
        #expect(GiftLogic.plannedTotal(items) == 3_000 + 2_950 + 2_800)
        #expect(GiftLogic.pendingCount(items) == 2)
        let ana = GiftLogic.groups(items).first { $0.person == "Ana" }
        #expect(ana?.subtotal == 5_950 && ana?.pending == 1)
        #expect(GiftLogic.people(items) == ["Ana", "Pedro"])
    }

    // MARK: Perto da loja

    @Test func pertoAteDezMinutosEPendente() {
        let items = [gift("perto", "A", "Ana", meters: 450), gift("longe", "B", "Ana", meters: 3_000),
                     gift("comprado", "C", "Ana", meters: 100, bought: true), gift("semLoja", "D", "Ana")]
        let found = GiftLogic.nearby(gifts: items, places: [], here: here, now: now, timeZone: tz)
        #expect(found.map(\.giftId) == ["perto"])
        #expect(found.first?.minutes ?? 99 <= 10)
        #expect(GiftLogic.nearby(gifts: items, places: [], here: nil, now: now, timeZone: tz).isEmpty)
        // Sem limite (quero "presente"): todos os pendentes com loja, do mais perto.
        let all = GiftLogic.nearby(gifts: items, places: [], here: here, now: now, timeZone: tz, maxMinutes: .max)
        #expect(all.map(\.giftId) == ["perto", "longe"])
    }

    @Test func lojaDoBoardFechadaNaoEntra() throws {
        let c = try container()
        let place = Place(id: "s1", name: "Disk Union", cityId: "tokyo", lat: store(200).0, lng: here.longitude)
        c.mainContext.insert(place)
        let g = gift("g", "Disco", "Pedro")
        g.placeId = "s1"
        // Sem horário conhecido: não é "fechado".
        #expect(GiftLogic.nearby(gifts: [g], places: [place], here: here, now: now, timeZone: tz).count == 1)
        #expect(GiftLogic.store(of: g, places: [place])?.id == "s1")
        // Aberta só de manhã, todo dia: às 14:20 está fechada e a linha some.
        let morning = (0...6).map { PlaceHours.Period(open: .init(day: $0, hour: 9, minute: 0), close: .init(day: $0, hour: 11, minute: 0)) }
        place.hours = PlaceHours(weekdayText: nil, periods: morning, fetchedAt: nil)
        #expect(GiftLogic.nearby(gifts: [g], places: [place], here: here, now: now, timeZone: tz).isEmpty)
    }

    @Test func pedidoDeQueroReconhecePresenteEPessoa() {
        let people = ["Ana", "Mãe"]
        #expect(GiftLogic.isGiftWant("presente", people: people))
        #expect(GiftLogic.isGiftWant("comprar presente", people: people))
        #expect(GiftLogic.isGiftWant("lembrancinha pra casa", people: people))
        #expect(GiftLogic.isGiftWant("o que falta pra mae", people: people))
        #expect(!GiftLogic.isGiftWant("café", people: people))
    }

    // MARK: Comprado

    @Test func comprarCriaGastoEDesfazerReverte() throws {
        let c = try container()
        let g = gift("g", "Kit Kat", "Ana", price: 1_200, qty: 3)
        c.mainContext.insert(g)
        GiftLogic.markBought(g, paid: 3_240, at: now, context: c.mainContext, store: nil)
        #expect(g.isBought && g.paidPrice == 3_240)
        var expenses = try c.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1 && expenses[0].amount == 3_240 && expenses[0].category == .shop)
        #expect(expenses[0].note.contains("Kit Kat") && expenses[0].note.contains("Ana"))
        GiftLogic.setPaid(g, to: 3_000, context: c.mainContext)
        expenses = try c.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses[0].amount == 3_000 && g.paidPrice == 3_000)
        GiftLogic.undoBought(g, context: c.mainContext)
        #expect(!g.isBought && g.paidPrice == nil)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<Expense>()) == 0)
    }

    @Test func taxFreeSomaPorLojaNoDia() {
        let a = gift("a", "A", "Ana", price: 3_240, store: "Don Quijote", bought: true)
        let b = gift("b", "B", "Pedro", price: 1_000, store: "Don Quijote")
        let other = gift("c", "C", "Lucas", price: 9_000, store: "Uniqlo", bought: true)
        let meter = GiftLogic.taxFree(for: b, among: [a, b, other], on: now, calendar: region.calendar, currency: "JPY", extra: 1_000)
        #expect(meter?.spent == 4_240 && meter?.minimum == 5_000 && meter?.missing == 760 && meter?.reached == false)
        #expect(GiftLogic.taxFree(for: b, among: [a, b], on: now, calendar: region.calendar, currency: "BRL") == nil)
    }

    // MARK: Leitura de texto

    @Test func leituraDeLegendaPreencheNomePrecoQuantidadeELoja() {
        let text = "Kit Kat de matcha no Don Quijote por ¥1.200 cada! Leve 3 caixas 🍵 #japao @tokyosnacks"
        let guess = GiftTextGuess.guess(from: text, stores: [.init(id: "x", name: "Disk Union")])
        #expect(guess.title?.hasPrefix("Kit Kat de matcha") == true)
        #expect(guess.price == 1_200)
        #expect(guess.quantity == 3)
        #expect(guess.storeName == "Don Quijote" && guess.chain)
        #expect(guess.author == "@tokyosnacks")
    }

    @Test func leituraReconheceLojaDoBoardEPrecoBrasileiro() {
        let guess = GiftTextGuess.guess(from: "Disco de city pop na Disk Union, R$ 25,90", stores: [.init(id: "j77", name: "Disk Union")])
        #expect(guess.storeId == "j77" && !guess.chain)
        #expect(guess.price == 25.9)
        #expect(GiftTextGuess.price(in: "1,200円") == 1_200)
        #expect(GiftTextGuess.price(in: "sem preço") == nil)
        #expect(GiftTextGuess.guess(from: "   ").isEmpty)
    }

    // MARK: Capa e dia

    @Test func capaGanhaLinhaLaranjaDaLojaPerto() {
        let near = GiftLogic.nearby(gifts: [gift("a", "Kit Kat de matcha", "Ana", qty: 3, meters: 360, store: "Don Quijote"),
                                            gift("b", "Doce", "Pedro", meters: 360, store: "Don Quijote")],
                                    places: [], here: here, now: now, timeZone: tz)
        var inputs = SuggestInputs(region: region, now: now, here: here, places: [])
        inputs.gifts = near
        let cards = SuggestionEngine.suggest(inputs)
        let card = try? #require(cards.first { $0.kind == .gift })
        #expect(card?.title == "Don Quijote")
        #expect(card?.meta.contains("presente da Ana e Pedro") == true)
        #expect(card.map { CorteIndexLine($0).tone } == .orange)
        // Sem GiftNearby, nada de linha de presente.
        #expect(SuggestionEngine.suggest(SuggestInputs(region: region, now: now, here: here, places: [])).allSatisfy { $0.kind != .gift })
    }

    @Test func microParadaPassaNaLojaPertoDaParadaSemMexerEmAncora() throws {
        let day = region.calendar.startOfDay(for: now)
        func at(_ h: Int, _ m: Int = 0) -> Date { day.addingTimeInterval(Double(h * 60 + m) * 60) }
        func stop(_ id: String, _ from: Int, _ to: Int, lat: Double, lng: Double) -> DayStop {
            DayStop(id: id, placeId: id, kind: .anchor, start: at(from), end: at(to), label: id, note: "", anchor: .reservation, lat: lat, lng: lng)
        }
        let a = (35.6800, 139.7600), b = (35.6820, 139.7620)
        let timeline = [stop("a", 10, 11, lat: a.0, lng: a.1), stop("b", 15, 16, lat: b.0, lng: b.1)]
        let spot = GiftSpot(giftId: "g1", person: "Ana", title: "Kit Kat", quantity: 3, storeName: "Don Quijote", placeId: nil,
                            lat: a.0 + 0.0012, lng: a.1)
        let far = GiftSpot(giftId: "g2", person: "Pedro", title: "Disco", quantity: 1, storeName: "Longe", placeId: nil, lat: a.0 + 0.05, lng: a.1)
        var input = DayComposer.Input(date: day, region: region, stops: [], hotel: CLLocationCoordinate2D(latitude: a.0, longitude: a.1), budget: 10_000)
        input.gifts = [spot, far]
        let sun = SunService.day(day.addingTimeInterval(12 * 3600), input.hotel, timeZone: tz)
        let micro = try #require(MicroStops.make(.gift, timeline: timeline, input: input, sun: sun))
        #expect(micro.micro == .gift && micro.kind == .micro && micro.label == "Passar na Don Quijote")
        #expect(micro.note.contains("presente da Ana"))
        #expect(micro.start >= at(11) && micro.end <= at(15))
        // Só a loja longe: nada entra.
        input.gifts = [far]
        #expect(MicroStops.make(.gift, timeline: timeline, input: input, sun: sun) == nil)
        // Sem presente na lista, a prioridade das micro-paradas nem tenta.
        input.gifts = []
        #expect(!MicroStops.priority(input).contains(.gift))
    }

    // MARK: Export / import

    @Test func exportImportIdaEVolta() throws {
        let origin = try BoardCodecTests.TestBoard(.jp)
        let g1 = gift("g1", "Kit Kat de matcha", "Ana", price: 1_200, qty: 3, meters: 450, store: "Don Quijote")
        g1.source = .video
        g1.sourceURL = "https://www.instagram.com/reel/x/"
        g1.sourceLabel = "@tokyosnacks"
        g1.videoClip = "0:12–0:19"
        g1.note = "caixa vermelha"
        let g2 = gift("g2", "Caneta", "Ana", price: 2_950, store: "Itoya", bought: true)
        g2.chain = true
        origin.context.insert(g1)
        origin.context.insert(g2)
        try origin.context.save()
        let data = try BoardCodec.encode(origin.export())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 3)
        #expect((object["gifts"] as? [[String: Any]])?.count == 2)

        let copy = try BoardCodecTests.TestBoard(.jp)
        try copy.import(board: BoardCodec.decode(data))
        let back = copy.context.gifts()
        #expect(back.map(\.id).sorted() == ["g1", "g2"])
        let r1 = try #require(back.first { $0.id == "g1" })
        #expect(r1.title == "Kit Kat de matcha" && r1.person == "Ana" && r1.quantity == 3 && r1.estimatedPrice == 1_200)
        #expect(r1.source == .video && r1.sourceLabel == "@tokyosnacks" && r1.videoClip == "0:12–0:19" && r1.note == "caixa vermelha")
        #expect(r1.storeName == "Don Quijote" && r1.storeLat != nil && r1.storeLng != nil)
        let r2 = try #require(back.first { $0.id == "g2" })
        #expect(r2.isBought && r2.paidPrice == 2_950 && r2.chain)
        // Importar de novo não duplica.
        try copy.import(board: BoardCodec.decode(data))
        #expect(copy.context.gifts().count == 2)
    }

    @Test func arquivoAntigoSemPresentesContinuaAbrindo() throws {
        for version in [1, 2] {
            let json = version == 1 ? #"{"version": 1, "region": "jp", "lists": [], "places": []}"#
                : #"{"version": 2, "tripId": "jp", "countryCode": "JP", "lists": [], "places": []}"#
            let board = try BoardCodec.decode(Data(json.utf8))
            #expect(board.gifts == nil)
            let target = try BoardCodecTests.TestBoard(.jp)
            try target.import(board: board)
            #expect(target.context.gifts().isEmpty)
        }
        // Sem presentes, o export não traz a chave.
        let empty = try BoardCodecTests.TestBoard(.jp)
        let object = try #require(try JSONSerialization.jsonObject(with: BoardCodec.encode(empty.export())) as? [String: Any])
        #expect(object["gifts"] == nil)
    }
}
