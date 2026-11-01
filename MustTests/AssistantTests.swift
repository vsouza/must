import CoreLocation
import Foundation
import Testing
@testable import Must

/// Retrato do Japão em 15 nov 18:42, em Naka-Meguro, com o dia aceito.
private func tokyoSnapshot() throws -> AssistantSnapshot {
    final class Token {}
    let board = try BoardCodec.decode(Data(contentsOf: Region.jp.seedURL(in: Bundle(for: Token.self))!))
    let colors = Dictionary(uniqueKeysWithValues: board.lists.map { ($0.id, $0.color) })
    let catalog = board.places.map { SolverPlace($0, color: colors[$0.listId]!) }
    let d = BoardDates(timeZone: Region.jp.timeZone)
    let day = d.day(from: "2026-11-15")!
    func place(_ id: String) -> SolverPlace { catalog.first { $0.id == id }! }
    func at(_ hhmm: String) -> Date { d.time(hhmm, on: day)! }
    let stops: [AssistantSnapshot.StopInfo] = [
        .init(id: "s1", place: place("j13"), at: at("08:30"), done: true, isAnchor: false, isException: false),
        .init(id: "s2", place: place("j05"), at: at("11:30"), done: true, isAnchor: false, isException: false),
        .init(id: "s3", place: place("j09"), at: at("15:00"), done: true, isAnchor: false, isException: false),
        .init(id: "s4", place: place("j01"), at: at("19:00"), done: false, isAnchor: true, isException: true),
        .init(id: "s5", place: place("j11"), at: at("21:30"), done: false, isAnchor: false, isException: false),
    ]
    return AssistantSnapshot(
        region: .jp, now: at("18:42"), here: CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985), areaName: "Naka-Meguro",
        cityId: "tokyo1", cityName: "Tóquio", catalog: catalog,
        listNames: Dictionary(uniqueKeysWithValues: board.lists.map { ($0.id, "Must \($0.name)") }),
        stops: stops, dayKind: .free, budget: 15_000, spentDay: 7_650, spentException: 22_000,
        weatherToday: DayWeather(tempMin: 9, tempMax: 13, code: 0, precipProb: 5, sunrise: nil, sunset: nil), weatherTomorrow: nil,
        lastTrain: LastTrain(label: "Último Hibiya Ginza → Naka-Meguro", time: "00:12"), fxRate: 0.036, walkMaxKm: 1.5
    )
}

struct FallbackAssistantTests {
    /// O caso do Verificar do prompt 08, sem modelo.
    @Test func tiredSwapBarNearDinnerAndSpent() throws {
        let s = try tokyoSnapshot()
        let reply = FallbackAssistant.answer("tô cansado, troca o bar de hoje por algo perto do jantar e me diz quanto já fui", snapshot: s)
        #expect(reply.text.contains("¥ 7.650"))
        #expect(reply.text.contains("¥ 22.000"))
        #expect(reply.text.contains("¥ 29.650"))
        let swaps = reply.actions.filter { if case .swap(let stop, _) = $0.kind { stop == "s5" } else { false } }
        #expect(!swaps.isEmpty && swaps.count <= 2)
        // Só lugares do board, mesmo papel do bar, fora do dia, na cidade do dia.
        let inDay = Set(s.stops.map(\.place.id))
        #expect(swaps.allSatisfy { [.listen, .drink].contains($0.place.role) && $0.place.sub != "Café" && !inDay.contains($0.place.id) && $0.place.cityId == "tokyo1" })
        #expect(swaps.contains { $0.place.id == "j12" }) // Bar Trench, como no design
        #expect(reply.quickReplies.first?.hasPrefix("Trocar pelo") == true)
    }

    @Test func neverSwapsAReservation() throws {
        let s = try tokyoSnapshot()
        let target = AssistantEngine.targetStop(s, text: "troca o jantar")
        #expect(target?.isAnchor != true)
    }

    @Test func lastTrainAndWeather() throws {
        let s = try tokyoSnapshot()
        #expect(FallbackAssistant.answer("qual o último metrô pra casa?", snapshot: s).text.contains("00:12"))
        #expect(FallbackAssistant.answer("vai chover hoje?", snapshot: s).text.contains("5% de chance"))
    }

    @Test func openNowWithoutHoursSaysSo() throws {
        let s = try tokyoSnapshot()
        let reply = FallbackAssistant.answer("o que está aberto perto de mim?", snapshot: s)
        #expect(reply.text.contains("sem horário confirmado") || reply.text.contains("Abertos agora"))
        #expect(reply.actions.allSatisfy { if case .go = $0.kind { true } else { false } })
    }

    @Test func unknownQuestionExplainsWhatItCanDo() throws {
        #expect(FallbackAssistant.answer("me conta uma piada", snapshot: try tokyoSnapshot()).text.hasPrefix("Consigo"))
    }

    @Test func suggestionsComeFromState() throws {
        let list = FallbackAssistant.suggestions(try tokyoSnapshot())
        #expect(list.count == 4)
        #expect(list.contains("Qual o último metrô pra casa?"))
    }
}

struct IntentParserTests {
    @Test func mapsGeneratedIntentAndKeepsOnlyBoardNames() {
        let g = GeneratedDayIntent(kind: "temples", turnOn: ["eat", "drink"], turnOff: ["shop"], budget: 8000, walk: "low",
                                   mustInclude: ["Fuunji", "Restaurante Inventado"], mustExclude: [], preferSubs: ["Ramen"],
                                   startEarly: true, mealsException: false, splurge: false)
        let i = IntentParser.map(g, placeNames: ["Fuunji", "Nakano Broadway"])
        #expect(i.kind == .temples && i.walk == .low && i.budget == 8000 && i.startEarly == true)
        #expect(i.roles[.eat] == .on && i.roles[.shop] == .off)
        #expect(i.mustInclude == ["Fuunji"]) // nome inventado é descartado
    }

    @Test func noneMeansUnset() {
        let g = GeneratedDayIntent(kind: "none", turnOn: [], turnOff: [], budget: 0, walk: "none", mustInclude: [], mustExclude: [],
                                   preferSubs: [], startEarly: false, mealsException: false, splurge: false)
        let i = IntentParser.map(g, placeNames: [])
        #expect(i.kind == nil && i.walk == nil && i.budget == nil && i.startEarly == nil)
    }

    @Test func mergeFillsGapsFromRegex() {
        let regex = RegexIntentParser.parse("templo cedo, ramen, café e andar pouco")
        var model = DayIntent()
        model.kind = .temples
        let merged = IntentParser.merge(model, regex)
        #expect(merged.kind == .temples && merged.walk == .low && merged.startEarly == true)
        #expect(merged.preferSubs.contains("Ramen"))
    }

    @Test func parseWithoutModelFallsBackToRegex() async {
        let i = await IntentParser.parse("dia de compras, sem andar muito", placeNames: [], useModel: false)
        #expect(i.kind == .shopping)
    }
}

struct PlaceExtractionAITests {
    @Test func modelOutputCannotInventPlaces() {
        let caption = "📍 Menya Kaijin em Shinjuku, ramen de peixe"
        let generated = [
            GeneratedPlace(name: "Menya Kaijin", nameLocal: "", area: "", category: "eat", hint: "ramen de peixe"),
            GeneratedPlace(name: "Ichiran", nameLocal: "", area: "", category: "eat", hint: "inventado"),
        ]
        let places = AIPlaceExtractor.map(generated, text: caption, knownAreas: ["Shinjuku"])
        #expect(places.map(\.name) == ["Menya Kaijin"])
        #expect(places.first?.area == "Shinjuku")
        #expect(places.first?.category == .eat && places.first?.sub == "Ramen")
    }

    @Test func parsesClaudeStructuredOutput() throws {
        let inner = #"{"places":[{"name":"Bar Benfiddich","nameLocal":"","area":"Nishi-Shinjuku","category":"drink","hint":"coquetéis de ervas"}]}"#
        let escaped = inner.replacingOccurrences(of: "\"", with: "\\\"")
        let json = #"{"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"\#(escaped)"}]}"#
        let places = try CloudBoost.parse(Data(json.utf8), text: "fomos no Bar Benfiddich ontem", knownAreas: [])
        #expect(places.map(\.name) == ["Bar Benfiddich"])
        #expect(places.first?.category == .drink)
    }

    @Test func claudeRefusalIsAnError() {
        let json = #"{"stop_reason":"refusal","content":[]}"#
        #expect(throws: ServiceError.self) { try CloudBoost.parse(Data(json.utf8), text: "", knownAreas: []) }
    }

    @Test func mapsLinkSkipsModels() async {
        let caption = Caption(source: .maps, title: "Xapuri", text: "Xapuri", placeName: "Xapuri")
        let (places, via) = await AIPlaceExtractor.extract(from: caption, options: .init(onDevice: true, cloudBoost: false, knownAreas: []))
        #expect(places.map(\.name) == ["Xapuri"] && via == "link do Maps")
    }
}

struct AssistantSearchTests {
    @Test func searchByWordsAndCheapFirst() throws {
        let s = try tokyoSnapshot()
        let found = AssistantEngine.search(s, query: "sushi barato em Tóquio")
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.sub == "Sushi" || $0.name.lowercased().contains("sushi") })
        let costs = found.prefix(3).map(\.cost)
        #expect(costs == costs.sorted())
    }
}

struct AssistantSuggestionTests {
    @Test func suggestsFromBoardCheapestFirst() throws {
        let reply = FallbackAssistant.answer("me sugere um lugar pra comer sushi barato em Tóquio", snapshot: try tokyoSnapshot())
        #expect(reply.recognized)
        #expect(reply.text.hasPrefix("Do seu board"))
        #expect(reply.actions.first?.place.id == "j02") // Sushi no Midori, ¥3.500 — o mais barato em Tóquio 1
    }
}
