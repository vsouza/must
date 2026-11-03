import Foundation
import SwiftData
import Testing
@testable import Must

/// Colar texto (prompt 18 · E): parser sem modelo, categorias, conferência no Places (fake), fila offline e gravação.
/// Nenhuma chamada real: o Places é `FakePlacesService`, os links não são lidos (`readLinks: false`).
@MainActor
struct ColarTextoTests {
    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    static var fake: FakePlacesService {
        FakePlacesService(candidates: ColarTextoSample.candidates, detailsById: [:])
    }

    static func env(queue: ModelContext?, provider: any PlacesProviding) -> ColarContext {
        ColarContext(board: [], lists: [], city: nil, cityId: "jp-tokyo", tripStart: nil, region: .jp, knownAreas: [],
                     provider: provider, queue: queue, onDevice: false, readLinks: false)
    }

    // MARK: Amostra

    @Test func fixtureIsTheSampleText() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/colar-texto-amostra.txt")
        let fixture = try String(contentsOf: url, encoding: .utf8)
        #expect(fixture.trimmingCharacters(in: .newlines) == ColarTextoSample.text)
    }

    @Test func sampleHasTwoDaysEightPlacesTwoLinksThreeTips() {
        let draft = TravelTextParser.parse(ColarTextoSample.text)
        #expect(draft.days.map(\.number) == [1, 2])
        #expect(draft.days[0].area == "Shibuya e Harajuku")
        #expect(draft.days[0].items == ["Meiji Jingu", "Fuunji", "Koffee Mameya"])
        #expect(draft.days[1].items == ["Senso-ji", "Asakusa Imahan", "Tokyo National Museum", "Ameyoko", "Bar Gen Yamamoto"])
        #expect(draft.places.count == 8)
        #expect(draft.links.count == 2)
        #expect(draft.links.allSatisfy { $0.host()?.contains("instagram") == true || $0.host()?.contains("goo.gl") == true })
        #expect(draft.tips.count == 3)
        #expect(draft.tips.contains { $0.target == .place("Senso-ji") && $0.text.contains("antes das 8h") })
        #expect(draft.tips.contains { $0.target == .place("Asakusa Imahan") && $0.text == "reserve com antecedência" })
        #expect(draft.tips.contains { $0.target == .wallet && $0.text.hasPrefix("Compre o Tokyo Subway Ticket") })
    }

    @Test func classifiesWordsAndLeavesTheRestToPlaces() {
        let draft = TravelTextParser.parse(ColarTextoSample.text)
        let color: [String: MustColor] = Dictionary(uniqueKeysWithValues: draft.places.compactMap { p in p.category.map { (p.name, $0) } })
        #expect(color["Meiji Jingu"] == .temple)
        #expect(color["Fuunji"] == .eat)
        #expect(color["Koffee Mameya"] == .coffee)
        #expect(color["Senso-ji"] == .temple)
        #expect(color["Asakusa Imahan"] == .eat)
        #expect(color["Tokyo National Museum"] == .art)
        #expect(color["Bar Gen Yamamoto"] == .drink)
        #expect(color["Ameyoko"] == nil)
    }

    @Test func displayTextDropsMarkdownAndKeepsLinesApart() {
        let shown = TravelTextParser.displayText("**Dia 1 — Shibuya**\n- **Meiji Jingu**: santuário")
        #expect(shown == "Dia 1 — Shibuya\n- Meiji Jingu: santuário")
    }

    // MARK: Blocos e merge

    @Test func blocksStayUnderTheLimitAndSplitBetweenLines() {
        let line = String(repeating: "Ueno ", count: 20)
        let text = (0..<70).map { "\($0) \(line)" }.joined(separator: "\n")
        let blocks = TravelTextExtractor.blocks(text)
        #expect(blocks.count > 1)
        #expect(blocks.allSatisfy { $0.count <= TravelTextExtractor.blockSize })
        #expect(blocks.joined(separator: "\n") == text)
    }

    @Test func mergeKeepsOnePlacePerNameAndOffsetsDayIndexes() {
        let first = TravelTextParser.parse("Dia 1 — Shibuya\n- Meiji Jingu: santuário")
        let second = TravelTextParser.parse("Dia 2 — Asakusa\n- Meiji Jingu\n- Senso-ji: cedo")
        let merged = TravelTextDraft.merge([first, second])
        #expect(merged.days.count == 2)
        #expect(merged.places.map(\.name) == ["Meiji Jingu", "Senso-ji"])
        #expect(merged.places[0].mentions == 2)
        #expect(merged.places[1].dayIndex == 1)
    }

    // MARK: Carteira

    @Test func ticketTipBecomesRailPassNamedLikeTheTicket() {
        let tip = TravelTip(text: "Compre o Tokyo Subway Ticket de 72h antes de começar o dia 1", target: .wallet)
        #expect(tip.walletName == "Tokyo Subway Ticket 72h")
        #expect(tip.walletKind == .railPass)
        #expect(TravelTip(text: "Use o eSIM antes de sair", target: .wallet).walletKind == .esim)
    }

    // MARK: Análise com Places fake

    @Test func analyzeConfersEightPlacesAndGroupsByDay() async {
        let model = ColarTextoModel()
        await model.analyze(ColarTextoSample.text, env: Self.env(queue: nil, provider: Self.fake))
        #expect(model.phase == .done)
        #expect(model.placesChecked)
        #expect(!model.queued)
        #expect(model.matches.count == 8)
        #expect(model.matches.allSatisfy { $0.located })
        #expect(model.groups.map(\.id) == [0, 1])
        #expect(model.groups[1].matches.count == 5)
        let counts = model.counts
        #expect(counts.eat == 2)
        #expect(counts.see == 3)
        #expect(counts.drink == 2)
        #expect(counts.links == 2)
        #expect(counts.tips == 3)
        // Três de cada dia entram; o resto fica "toque pra ver", desmarcado.
        #expect(model.included.count == 6)
        #expect(model.dayNumbersOn == [1, 2])
        #expect(model.spans().filter { $0.style == .link }.count == 2)
        #expect(model.spans().contains { $0.style == .tip })
    }

    @Test func withoutPlacesEverythingIsPendingButCounted() async {
        let model = ColarTextoModel()
        let offline = FakePlacesService(isConfigured: false, candidates: [], detailsById: [:])
        await model.analyze(ColarTextoSample.text, env: Self.env(queue: nil, provider: offline))
        #expect(!model.placesChecked)
        #expect(model.matches.count == 8)
        #expect(model.included.count == 6)
    }

    // MARK: Fila offline (E.23)

    @Test func offlineQueuesTheConferenceAndDrainAppliesIt() async throws {
        let context = ModelContext(try Self.container())
        let link = Connectivity()
        link.apply(.offline, expensive: false, wifi: false)
        defer { link.apply(.online, expensive: false, wifi: false) }

        let model = ColarTextoModel()
        await model.analyze(ColarTextoSample.text, env: Self.env(queue: context, provider: Self.fake))
        #expect(model.queued)
        #expect(!model.placesChecked)
        #expect(Outbox.waitingCount(context) == 1)
        #expect(model.matches.allSatisfy { !$0.located })

        link.apply(.online, expensive: false, wifi: false)
        let finished = await Outbox.drain(context: context, region: .jp, isOnline: { true }, flightSource: nil,
                                          fetchCaption: { _ in Caption(source: .text, title: nil, text: "", url: nil) },
                                          places: Self.fake)
        #expect(finished == 1)
        #expect(Outbox.waitingCount(context) == 0)

        let again = ColarTextoModel()
        await again.analyze(ColarTextoSample.text, env: Self.env(queue: context, provider: Self.fake))
        #expect(again.placesChecked)
        #expect(!again.queued)
        #expect(again.matches.allSatisfy { $0.located })
    }

    // MARK: Gravação

    @Test func saveWritesPlacesTipsWalletAndTwoDays() async throws {
        let context = ModelContext(try Self.container())
        let model = ColarTextoModel()
        let env = Self.env(queue: context, provider: Self.fake)
        await model.analyze(ColarTextoSample.text, env: env)
        let saved = model.save(env: env, sync: nil, context: context, withDays: true, now: Date(timeIntervalSince1970: 1_793_000_000))
        #expect(saved == 6)

        let places = try context.fetch(FetchDescriptor<Place>())
        #expect(places.count == 6)
        let senso = places.first { $0.name == "Senso-ji" }
        #expect(senso?.notes.contains("antes das 8h") == true)
        let imahan = places.first { $0.name == "Asakusa Imahan" }
        #expect(imahan?.notes.contains("reserve com antecedência") == true)

        let days = try context.fetch(FetchDescriptor<PlannedDay>(sortBy: [SortDescriptor(\.date)]))
        #expect(days.count == 2)
        #expect(days.allSatisfy { $0.accepted && $0.stops.count == 3 })
        #expect(days[0].focusAreaName == "Shibuya e Harajuku")

        let wallet = context.walletItems()
        #expect(wallet.map(\.name) == ["Tokyo Subway Ticket 72h"])
        #expect(wallet.first?.kind == .railPass)
    }
}
