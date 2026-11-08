import CoreLocation
import Foundation
import Testing
@testable import Must

/// Respondedor determinístico das perguntas do Quero…/Assistente (sem Foundation Models).
/// Cenário: Tóquio, domingo 15 nov 2026, 15:00, em Shinjuku. Ramen perto (aberto 11–21), museu longe (fecha 17:00),
/// loja sem horário confirmado e um jantar reservado às 18:30 em Ginza.
@MainActor
struct QuestionAnswererTests {
    private let region = Region.jp
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006)

    private func hours(_ open: Int, _ close: Int) -> PlaceHours {
        PlaceHours(weekdayText: nil, periods: (0...6).map {
            .init(open: .init(day: $0, hour: open, minute: 0), close: .init(day: $0, hour: close, minute: 0))
        }, fetchedAt: nil)
    }

    private func place(_ id: String, _ name: String, lat: Double, lng: Double, price: Double? = nil, hours: PlaceHours? = nil,
                       notes: String = "", color: MustColor = .eat, saveForEnd: Bool = false, area: String? = "Shinjuku",
                       cityId: String = "tokyo1") -> SolverPlace {
        SolverPlace(id: id, name: name, listId: "l-\(color.rawValue)", listColor: color, sub: nil, cityId: cityId, area: area, lat: lat, lng: lng,
                    price: price, windows: [.lunch], hours: hours, reservation: nil, saveForEnd: saveForEnd, allowBudgetException: false,
                    queueMinutes: nil, notes: notes, sourceKind: nil, done: false)
    }

    private func at(_ hh: Int, _ mm: Int) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: hh, minute: mm))!
    }

    private func snapshot(now: Date? = nil, here: CLLocationCoordinate2D? = nil, withAnchor: Bool = true) throws -> AssistantSnapshot {
        var s = try tokyoSnapshot()
        let ramen = place("p1", "Fuunji Ramen", lat: 35.6905, lng: 139.6990, price: 1_250, hours: hours(11, 21), notes: "pedir tsukemen")
        let museu = place("p2", "Museu Nezu", lat: 35.6620, lng: 139.7219, price: 1_300, hours: hours(10, 17), color: .see, area: "Aoyama")
        let loja = place("p3", "Loja Sem Horário", lat: 35.6940, lng: 139.7035, color: .shop)
        let longe = place("p4", "Fushimi Inari", lat: 34.9671, lng: 135.7727, color: .temple, area: "Fushimi", cityId: "kyoto")
        let fim = place("p5", "Kabukichō Torre", lat: 35.6950, lng: 139.7030, notes: "só no fim", saveForEnd: true)
        let sushi = place("p6", "Sushi Saito", lat: 35.6717, lng: 139.7640, price: 22_000, hours: hours(12, 23), area: "Ginza")
        s.catalog = [ramen, museu, loja, longe, fim, sushi]
        s.listNames = ["l-eat": "Must eat", "l-see": "Must see", "l-shop": "Must shop", "l-temple": "Must see"]
        s.now = now ?? at(15, 0)
        s.here = here ?? shinjuku
        s.areaName = "Shinjuku"
        s.cityId = "tokyo1"
        s.stops = withAnchor
            ? [.init(id: "s1", place: sushi, at: at(18, 30), done: false, isAnchor: true, isException: false)]
            : []
        return s
    }

    private func ask(_ q: String, _ s: AssistantSnapshot) -> QuestionAnswer { QuestionAnswerer.answer(q, snapshot: s) }

    // MARK: Classificação

    @Test func classifica() {
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("Dá tempo de ir no Gyoen?")) == .timeFor)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("quanto custa o Museu Nezu?")) == .price)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("quanto é o ingresso do teamLab?")) == .price)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("que horas fecha o Fuunji?")) == .hours)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("tá aberto agora?")) == .hours)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("como chego em Shibuya?")) == .route)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("vale a pena o Museu Nezu?")) == .worth)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("o que eu faço agora?")) == .nowNearby)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("o que tem perto?")) == .nowNearby)
        #expect(QuestionAnswerer.classify(QueroQuestion.normalize("me conta uma piada")) == .unknown)
    }

    // MARK: Reconhecer o lugar

    @Test func achaLugarSemAcentoECaixa() throws {
        let s = try snapshot()
        #expect(QuestionAnswerer.findPlace(in: QueroQuestion.normalize("DÁ TEMPO DE KABUKICHO TORRE?"), snapshot: s)?.id == "p5")
        #expect(QuestionAnswerer.findPlace(in: QueroQuestion.normalize("quanto custa o museu nezu"), snapshot: s)?.id == "p2")
        #expect(QuestionAnswerer.findPlace(in: QueroQuestion.normalize("abre cedo o fuunji?"), snapshot: s)?.id == "p1")
    }

    @Test func naoInventaLugar() throws {
        let s = try snapshot()
        #expect(QuestionAnswerer.findPlace(in: QueroQuestion.normalize("dá tempo de ir no Gyoen?"), snapshot: s) == nil)
        #expect(QuestionAnswerer.findPlace(in: QueroQuestion.normalize("quanto custa o restaurante famoso?"), snapshot: s) == nil)
        #expect(QuestionAnswerer.findPlace(in: QueroQuestion.normalize("como chego no bar?"), snapshot: s) == nil)
    }

    // MARK: Dá tempo

    @Test func daTempoComAncora() throws {
        let s = try snapshot()
        let a = ask("dá tempo de ir no Fuunji?", s)
        #expect(a.kind == .timeFor && a.recognized && a.placeId == "p1")
        #expect(a.text.hasPrefix("Dá:"))
        #expect(a.text.contains("min a pé") || a.text.contains("min de trem"))
        #expect(a.text.contains("fica 1 h 15"))
        #expect(a.text.contains("pro Sushi Saito das 18:30"))
        #expect(a.text.contains("sai às"))
    }

    @Test func naoDaTempoPassaDaSaida() throws {
        var s = try snapshot(now: at(17, 30))
        s.catalog[1].hours = hours(10, 23)
        let a = ask("dá tempo de ir no Museu Nezu?", s)
        #expect(a.text.hasPrefix("Não dá:"))
        #expect(a.text.contains("Motivo"))
        #expect(a.text.contains("passa"))
        #expect(a.text.contains("Sushi Saito"))
    }

    @Test func naoDaTempoFechado() throws {
        let s = try snapshot(now: at(16, 40), withAnchor: false)
        let a = ask("dá tempo do Museu Nezu?", s)
        #expect(a.text.hasPrefix("Não dá:"))
        #expect(a.text.contains("fechado") || a.text.contains("fecha às 17:00"))
    }

    @Test func fechaAntesDeAcabarAVisita() throws {
        let s = try snapshot(now: at(15, 55), withAnchor: false)
        let a = ask("dá tempo de ir no Museu Nezu?", s)
        #expect(a.text.contains("fecha às 17:00"))
        #expect(a.text.contains("sobram"))
    }

    @Test func horarioEstimadoSeAvisa() throws {
        let s = try snapshot(withAnchor: false)
        let a = ask("dá tempo de ir na Loja Sem Horário?", s)
        #expect(a.text.contains("horário estimado"))
        #expect(a.text.hasPrefix("Dá, pelo que sei:"))
    }

    @Test func daTempoSemOrigemExplica() throws {
        var s = try snapshot(withAnchor: false)
        s.here = nil
        let a = ask("dá tempo de ir no Fuunji?", s)
        #expect(a.text.contains("Não sei de onde você parte"))
    }

    @Test func daTempoUsaProximaParadaQuandoSemGPS() throws {
        var s = try snapshot()
        s.here = nil
        let a = ask("dá tempo de ir no Fuunji?", s)
        #expect(a.text.contains("min"))
        #expect(!a.text.contains("Não sei de onde"))
    }

    @Test func daTempoUsaDayClock() throws {
        let s = try snapshot()
        let clock = DayClock.make(plan: DayEngineStub.qaDay, doneIds: [], at: s.now, region: region)
        let a = QuestionAnswerer.answer("dá tempo de ir no Fuunji?", snapshot: s, clock: clock)
        #expect(a.recognized && a.kind == .timeFor)
        #expect(a.text.contains("min"))
    }

    // MARK: Preço

    @Test func precoDoBoard() throws {
        let a = ask("quanto custa o Fuunji?", try snapshot())
        #expect(a.kind == .price && a.recognized)
        #expect(a.text.contains("¥") && a.text.contains("1.250"))
    }

    @Test func precoSemDadoDizSemPreco() throws {
        let a = ask("quanto custa a Loja Sem Horário?", try snapshot())
        #expect(a.text.contains("sem preço guardado"))
    }

    @Test func precoDeIngressoPago() throws {
        var s = try snapshot()
        s.catalog[5].tickets = [Ticket(at: at(18, 30), paid: 44_000, people: 2)]
        let a = ask("quanto é o Sushi Saito?", s)
        #expect(a.text.contains("22.000") && a.text.contains("44.000"))
    }

    @Test func precoSemLugarNaoInventa() throws {
        let a = ask("quanto custa o restaurante famoso?", try snapshot())
        #expect(!a.recognized)
        #expect(a.text.contains("Não achei esse lugar"))
        #expect(!a.text.contains("¥"))
    }

    // MARK: Horário

    @Test func horarioConfirmadoAberto() throws {
        let a = ask("que horas fecha o Fuunji?", try snapshot())
        #expect(a.kind == .hours && a.recognized)
        #expect(a.text.contains("Aberto agora, fecha às 21:00"))
        #expect(!a.text.contains("estimado"))
    }

    @Test func horarioFechadoAgora() throws {
        let a = ask("tá aberto o Museu Nezu?", try snapshot(now: at(18, 0), withAnchor: false))
        #expect(a.text.contains("Fechado agora"))
        #expect(a.text.contains("abre"))
    }

    @Test func horarioNaoConfirmadoDiz() throws {
        let a = ask("que horas abre a Loja Sem Horário?", try snapshot())
        #expect(a.text.contains("sem horário confirmado"))
        #expect(a.text.contains("horário estimado"))
        #expect(!a.text.contains("Aberto agora"))
    }

    // MARK: Como chego

    @Test func comoChegoEmLugar() throws {
        let a = ask("como chego no Museu Nezu?", try snapshot())
        #expect(a.kind == .route && a.recognized && a.placeId == "p2")
        #expect(a.text.hasPrefix("Até Museu Nezu:"))
        #expect(a.text.contains("min"))
        #expect(a.text.contains("trem") || a.text.contains("a pé"))
    }

    @Test func comoChegoEmBairro() throws {
        let s = try snapshot()
        guard let area = AreaCatalog.areas(for: region).first(where: { $0.name != "Shinjuku" && $0.cityId == "tokyo" }) else { return }
        let a = ask("como chego em \(area.name)?", s)
        #expect(a.kind == .route && a.recognized)
        #expect(a.text.contains(area.name))
    }

    @Test func comoChegoSemOrigem() throws {
        var s = try snapshot(withAnchor: false)
        s.here = nil
        let a = ask("como chego no Museu Nezu?", s)
        #expect(a.text.contains("Não sei de onde você parte"))
    }

    // MARK: Vale a pena

    @Test func valeAPenaUsaNotaEFicaProFim() throws {
        let a = ask("vale a pena o Kabukichō Torre?", try snapshot())
        #expect(a.kind == .worth && a.recognized)
        #expect(a.text.contains("só no fim"))
        #expect(a.text.contains("fica pro fim"))
    }

    @Test func valeAPenaOutraCidade() throws {
        let a = ask("vale a pena Fushimi Inari?", try snapshot())
        #expect(a.text.contains("outra cidade"))
    }

    @Test func valeAPenaSemNotaAdmite() throws {
        let a = ask("vale a pena o Museu Nezu?", try snapshot())
        #expect(a.text.contains("Não tenho nota"))
    }

    @Test func valeAPenaMostraReserva() throws {
        let a = ask("vale a pena o Sushi Saito?", try snapshot())
        #expect(a.text.contains("está no dia de hoje às 18:30"))
    }

    // MARK: Agora / perto

    @Test func agoraSemRelogioUsaProximaDoDia() throws {
        let a = ask("o que eu faço agora?", try snapshot())
        #expect(a.kind == .nowNearby && a.recognized)
        #expect(a.text.contains("Sushi Saito") && a.text.contains("18:30"))
    }

    @Test func agoraComRelogio() throws {
        var s = try snapshot()
        let clock = DayClock.make(plan: DayEngineStub.qaDay, doneIds: [], at: at(14, 30), region: region)
        s.now = at(14, 30)
        let a = QuestionAnswerer.answer("o que eu faço agora?", snapshot: s, clock: clock)
        #expect(a.recognized)
        #expect(a.text.hasPrefix("Agora:") || a.text.hasPrefix("O dia começa") || a.text.contains("Sem dia"))
    }

    @Test func pertoSemDiaListaAbertos() throws {
        let a = ask("o que tem perto?", try snapshot(withAnchor: false))
        #expect(a.recognized)
        #expect(a.text.contains("Fuunji") || a.text.contains("Loja Sem Horário"))
        #expect(!a.text.contains("Museu Nezu"))
        #expect(!a.text.contains("Fushimi"))
    }

    // MARK: Desconhecida

    @Test func desconhecidaOfereceAssistente() throws {
        let a = ask("me conta uma piada", try snapshot())
        #expect(!a.recognized && a.kind == .unknown)
        #expect(a.text.contains("Continuar no Assistente"))
        #expect(a.text.contains("quanto custa"))
    }

    // MARK: ChatModel

    @Test func chatSemModeloUsaORespondedor() async throws {
        let chat = ChatModel()
        await chat.send("dá tempo de ir no Fuunji?", snapshot: try snapshot(), useModel: false)
        let reply = try #require(chat.messages.last)
        #expect(reply.role == .assistant)
        #expect(reply.text.hasPrefix("Dá:"))
    }

    @Test func daTempoDeLugarForaDoBoardNaoViraPrevisao() async throws {
        let chat = ChatModel()
        await chat.send("dá tempo de ir no Disk Union?", snapshot: try snapshot(), useModel: false)
        let text = chat.messages.last?.text ?? ""
        #expect(text.contains("Não achei esse lugar"))
        #expect(!text.contains("previsão"))
    }

    @Test func chatMantemFallbackDeGasto() async throws {
        let chat = ChatModel()
        await chat.send("quanto gastei hoje?", snapshot: try tokyoSnapshot(), useModel: false)
        #expect(chat.messages.last?.text.contains("¥ 7.650") == true)
    }
}
