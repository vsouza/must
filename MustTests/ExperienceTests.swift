import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 14 · C (fatia 4): colar link de experiência (og:tags, extrator, fallback regex) e a lista com conflito.
struct ExperienceLinkTests {
    /// Página de Klook (fixture): og:tags + o texto visível que o extrator lê.
    static let fixture = """
    <html><head>
    <title>Sushi Making Class with a Chef in Tsukiji | Klook</title>
    <meta property="og:title" content="Sushi Making Class with a Chef in Tsukiji | Klook">
    <meta property="og:description" content="Aula de 3 horas, em inglês, grupo até 8 pessoas. Ponto de encontro: Tsukiji Outer Market, Gate 1.">
    <meta property="og:image" content="https://images.example.com/tsukiji.jpg">
    <meta property="og:site_name" content="Klook">
    </head><body>
    <p>From ¥12,000 per person</p>
    <p>Duration: 3h</p>
    <p>Meeting point: Tsukiji Outer Market, Gate 1</p>
    </body></html>
    """

    static let url = URL(string: "https://www.klook.com/activity/123-sushi-tsukiji/")!

    @Test func readsOpenGraphTags() {
        let link = ExperienceLinkReader.parse(Self.fixture, url: Self.url)
        #expect(link.title == "Sushi Making Class with a Chef in Tsukiji")
        #expect(link.imageURL == URL(string: "https://images.example.com/tsukiji.jpg"))
        #expect(link.siteName == "Klook")
        #expect(link.description.contains("grupo até 8"))
        #expect(link.supplier == .klook)
    }

    @Test func regexExtractorReadsPriceDurationGroupLanguageAndMeetingPoint() {
        let link = ExperienceLinkReader.parse(Self.fixture, url: Self.url)
        let draft = ExperienceExtractor.parse(link, region: .jp)
        #expect(draft.via == "palavras-chave")
        #expect(draft.name == "Sushi Making Class with a Chef in Tsukiji")
        #expect(draft.info.priceFrom == 12_000)
        #expect(draft.info.currency == nil) // ¥ é a moeda da região: não repete
        #expect(draft.info.durationMinutes == 180)
        #expect(draft.info.groupMax == 8)
        #expect(draft.info.languages == ["inglês"])
        #expect(draft.info.meetingPoint == "Tsukiji Outer Market, Gate 1")
        #expect(draft.info.supplier == .klook)
        #expect(draft.info.imageURL != nil)
        #expect(draft.session == nil) // a página não traz data: nada é inventado
    }

    @Test func modelOutputOnlyCountsWhenThePageSaysIt() {
        let link = ExperienceLinkReader.parse(Self.fixture, url: Self.url)
        let invented = ExtractedExperience(title: "Aula de sushi", supplier: "Klook", price: 9_999, currency: "JPY", durationMinutes: 0,
                                           meetingPoint: "Shibuya Scramble", date: "2026-11-15", time: "10:00", languages: ["japonês"])
        let draft = ExperienceExtractor.map(invented, link: link, region: .jp)
        #expect(draft?.info.priceFrom == 12_000) // o preço da página (regex) manda; o 9.999 do modelo não aparece na página
        #expect(draft?.info.meetingPoint == "Tsukiji Outer Market, Gate 1") // o regex manda quando acha
        #expect(draft?.info.languages == ["inglês"]) // japonês não está na página; o inglês veio do texto
        #expect(draft?.session == nil) // 10:00 não aparece na página
        #expect(draft?.via == "no aparelho")
    }

    @Test func modelFillsPriceAndSessionWhenThePageHasThem() throws {
        let link = ExperienceLink(url: Self.url, title: "Tour de izakayas em Shinjuku", description: "", imageURL: nil, siteName: nil,
                                  pageText: "Preço: 9.800 ienes. Dia 2026-11-15 às 19:30 (sessão).")
        let generated = ExtractedExperience(title: "Tour de izakayas em Shinjuku", supplier: "", price: 9_800, currency: "JPY",
                                            durationMinutes: 180, meetingPoint: "", date: "2026-11-15", time: "19:30", languages: [])
        let draft = try #require(ExperienceExtractor.map(generated, link: link, region: .jp))
        #expect(draft.info.priceFrom == 9_800)
        #expect(draft.info.durationMinutes == 180)
        #expect(draft.session != nil)
        let at = try #require(draft.session?.at)
        #expect(BoardDates(timeZone: Region.jp.timeZone).timeString(at) == "19:30")
    }

    @Test func numbersMatchWithThousandSeparatorsOnly() {
        #expect(ExperienceExtractor.numberAppears(12_000, in: "¥12,000 por pessoa"))
        #expect(ExperienceExtractor.numberAppears(12_000, in: "R$ 12.000"))
        #expect(ExperienceExtractor.numberAppears(12_000, in: "12000"))
        #expect(!ExperienceExtractor.numberAppears(120, in: "¥12,000"))
        #expect(!ExperienceExtractor.numberAppears(12, in: "12000"))
    }

    @Test func supplierComesFromTheDomainAndOtherSitesKeepTheirName() {
        #expect(ExperienceSupplier.detect(URL(string: "https://www.viator.com/tours/Tokyo/x/d334-123")!) == .viator)
        #expect(ExperienceSupplier.detect(URL(string: "https://www.getyourguide.com.br/tokyo-t1/")!) == .getYourGuide)
        #expect(ExperienceSupplier.detect(URL(string: "https://www.airbnb.com.br/experiences/1")!) == .airbnb)
        #expect(ExperienceSupplier.detect(URL(string: "https://www.sympla.com.br/evento/x")!) == .other)
        #expect(ExperienceSupplier.badge(.other, url: URL(string: "https://www.sympla.com.br/evento/x")!) == "Sympla")
        #expect(ExperienceSupplier.badge(.klook, url: nil) == "Klook")
    }

    @Test func titleLosesTheSiteSuffix() {
        #expect(ExperienceLinkReader.cleanTitle("Aula de sushi em Tsukiji | Viator") == "Aula de sushi em Tsukiji")
        #expect(ExperienceLinkReader.cleanTitle("Oi | x") == "Oi | x")
    }
}

/// Lista de experiências: ordem por data, busca e aviso de conflito com âncora (reserva, ingresso).
@MainActor
struct ExperienceListTests {
    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func conflictWithAReservationShowsInTheList() throws {
        let container = try Self.container()
        let context = container.mainContext
        let region = Region.jp
        let dates = BoardDates(timeZone: region.timeZone)
        let day = try #require(dates.day(from: "2026-11-15"))

        let eat = MustList(id: "eat", name: "eat", icon: .mustsLista, color: .eat)
        let experiences = MustList(id: "exp", name: "do", icon: .mustsLista, color: .night, kind: .experience)
        context.insert(eat)
        context.insert(experiences)

        let udatsu = Place(id: "udatsu", name: "Udatsu", cityId: "tokyo1")
        udatsu.list = eat
        udatsu.reservation = Reservation(at: try #require(dates.time("19:00", on: day)), party: 2)
        context.insert(udatsu)

        let tour = Place(id: "tour", name: "Tour de izakayas", cityId: "tokyo1")
        tour.list = experiences
        tour.extra = PlaceExtra(experience: ExperienceInfo(supplier: .getYourGuide, durationMinutes: 180,
                                                           sessions: [EventSession(at: try #require(dates.time("19:30", on: day)), title: "saída 19:30")]))
        context.insert(tour)

        let sushi = Place(id: "sushi", name: "Aula de sushi", cityId: "tokyo1")
        sushi.list = experiences
        sushi.extra = PlaceExtra(experience: ExperienceInfo(supplier: .viator, durationMinutes: 180,
                                                            sessions: [EventSession(at: try #require(dates.time("10:00", on: day)), title: "10:00")]))
        context.insert(sushi)

        let now = day.addingTimeInterval(9 * 3600)
        let rows = ExperienceListModel.rows(places: [udatsu, tour, sushi], query: "", chip: .any, region: region, now: now)
        #expect(rows.map(\.place.id) == ["sushi", "tour"]) // por data
        let row = try #require(rows.first { $0.place.id == "tour" })
        #expect(row.conflicts == ["conflita: Udatsu 19:00"])
        #expect(rows.first { $0.place.id == "sushi" }?.conflicts.isEmpty == true)
    }

    @Test func searchFiltersTheSavedOnes() throws {
        let container = try Self.container()
        let context = container.mainContext
        let region = Region.jp
        let list = MustList(id: "exp", name: "do", icon: .mustsLista, color: .night, kind: .experience)
        context.insert(list)
        let sushi = Place(id: "s", name: "Aula de sushi com chef", cityId: "tokyo1")
        sushi.list = list
        sushi.extra = PlaceExtra(experience: ExperienceInfo(supplier: .viator))
        let teamlab = Place(id: "t", name: "teamLab Borderless", cityId: "tokyo1")
        teamlab.list = list
        teamlab.extra = PlaceExtra(experience: ExperienceInfo(supplier: .klook))
        context.insert(sushi)
        context.insert(teamlab)
        let found = ExperienceListModel.rows(places: [sushi, teamlab], query: "sushi", chip: .any, region: region, now: Date())
        #expect(found.map(\.place.id) == ["s"])
        let byBadge = ExperienceListModel.rows(places: [sushi, teamlab], query: "klook", chip: .any, region: region, now: Date())
        #expect(byBadge.map(\.place.id) == ["t"])
    }

    @Test func savingWithoutAMustDoListCreatesIt() throws {
        let container = try Self.container()
        let context = container.mainContext
        let draft = ExperienceDraft(name: "Photowalk em Yanaka", info: ExperienceInfo(supplier: .airbnb, priceFrom: 6_500, currency: "USD"),
                                    session: nil, via: "palavras-chave")
        let place = ExperienceStore.add(draft, region: .jp, context: context)
        #expect(place.list?.kind == .experience)
        #expect(place.list?.name == "do")
        #expect(place.price == nil) // USD não entra no orçamento em iene
        #expect(place.extra?.experience?.supplier == .airbnb)
        // Segunda gravação usa a mesma lista.
        let second = ExperienceStore.add(draft, region: .jp, context: context)
        let lists = try context.fetch(FetchDescriptor<MustList>())
        #expect(lists.filter { $0.kind == .experience }.count == 1)
        #expect(second.list?.id == place.list?.id)
    }
}
