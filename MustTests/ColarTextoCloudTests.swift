import Foundation
import SwiftData
import Testing
@testable import Must

/// Colar texto, rodada 21 · fatia 3: reforço na nuvem (Haiku, uma tentativa, stub) e nomes em japonês (`nameLocal`).
/// Nenhuma chamada real: o endpoint é um host `.netstub.test` servido pelo `NetStub` (URLProtocol).
@MainActor
struct ColarTextoCloudTests {
    static func stubbedHTTP(host: String, connectivity: Connectivity.Status = .online) -> HTTP {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetStub.self]
        return HTTP(session: URLSession(configuration: config), retries: 0, breaker: nil, inFlight: nil,
                    connectivity: { connectivity }, pause: { _ in }, jitter: { 1 })
    }

    static func endpoint(_ host: String) -> URL {
        URL(string: "https://\(host)/v1/messages")!
    }

    /// Resposta da Messages API com o JSON do esquema de texto dentro do bloco de texto.
    static func reply(_ payload: String) -> Data {
        let body: [String: Any] = [
            "stop_reason": "end_turn",
            "content": [["type": "text", "text": payload]],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static let payload = """
    {"days":[{"title":"Dia 1 — Shibuya","area":"Shibuya","items":["Fuunji"]}],\
    "places":[{"name":"Fuunji","nameLocal":"風雲児","area":"Shibuya","category":"eat","sub":"Tsukemen","why":"fila grande"},\
    {"name":"Lugar Inventado","nameLocal":"","area":"","category":"eat","sub":"","why":""}],\
    "tips":[{"text":"chegue cedo","kind":"general","placeName":""}]}
    """

    // MARK: Pedido

    @Test func textRequestUsesHaikuLowEffortAndNoThinking() throws {
        let body = CloudBoost.textRequestBody("Dia 1 — Shibuya\nFuunji (風雲児)")
        let model = try #require(body["model"] as? String)
        #expect(model == "claude-haiku-5-5")
        #expect(model == CloudBoost.model)
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "low")
        #expect(body["thinking"] == nil)
        #expect((body["max_tokens"] as? Int ?? .max) <= CloudBoost.textMaxTokens)
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect((schema["required"] as? [String]) == ["days", "places", "tips"])
    }

    @Test func textRequestNeverSendsMoreThanTheCap() throws {
        let long = String(repeating: "Fuunji. ", count: 5_000)
        let body = CloudBoost.textRequestBody(String(long.prefix(CloudBoost.textMaxLength)))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)
        #expect(content.count <= CloudBoost.textMaxLength + "Texto:\n".count)
    }

    // MARK: Gatilho

    @Test func cloudOnlyWhenTheLocalParserFindsLessThanTwoPlaces() {
        let none = TravelTextDraft()
        #expect(TravelTextExtractor.needsCloud(none))
        let one = TravelTextDraft(places: [ExtractedPlace(name: "Fuunji", hint: "x")])
        #expect(TravelTextExtractor.needsCloud(one))
        let two = TravelTextDraft(places: [ExtractedPlace(name: "Fuunji", hint: "x"), ExtractedPlace(name: "Ichiran", hint: "x")])
        #expect(!TravelTextExtractor.needsCloud(two))
    }

    // MARK: Resposta

    @Test func answerBecomesTheSameDraftShapeAndDropsNamesOutsideTheText() throws {
        let data = Self.reply(Self.payload)
        let draft = try TravelTextExtractor.draft(fromCloud: data, text: "Dia 1 — Shibuya\nFuunji é ótimo.", knownAreas: [])
        #expect(draft.via == "reforço na nuvem")
        #expect(draft.places.map(\.name) == ["Fuunji"])
        #expect(draft.places.first?.nameLocal == "風雲児")
        #expect(draft.days.first?.items == ["Fuunji"])
        #expect(draft.tips.first?.text == "chegue cedo")
    }

    @Test func badAnswerThrowsInsteadOfInventingPlaces() {
        let refusal = try! JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": []])
        #expect(throws: ServiceError.self) { try TravelTextExtractor.draft(fromCloud: refusal, text: "x", knownAreas: []) }
    }

    // MARK: Rede (stub, uma tentativa)

    @Test func extractTextPostsOnceToTheStubAndReadsTheAnswer() async throws {
        let host = "colar-ok.netstub.test"
        NetStub.register(host, [.ok(Self.reply(Self.payload))])
        let data = try await CloudBoost.extractText("Dia 1 — Shibuya\nFuunji", key: "chave-de-teste",
                                                    http: Self.stubbedHTTP(host: host), endpoint: Self.endpoint(host))
        #expect(NetStub.hits(host) == 1)
        let draft = try TravelTextExtractor.draft(fromCloud: data, text: "Dia 1 — Shibuya\nFuunji", knownAreas: [])
        #expect(draft.places.map(\.name) == ["Fuunji"])
    }

    @Test func aFailedTextRequestIsNeverRetried() async {
        let host = "colar-erro.netstub.test"
        NetStub.register(host, [.error(.timedOut), .ok(Self.reply(Self.payload))])
        await #expect(throws: (any Error).self) {
            _ = try await CloudBoost.extractText("Fuunji", key: "chave-de-teste",
                                                 http: Self.stubbedHTTP(host: host), endpoint: Self.endpoint(host))
        }
        #expect(NetStub.hits(host) == 1)
    }

    @Test func offlineDoesNotTouchTheNetwork() async {
        let host = "colar-offline.netstub.test"
        NetStub.register(host, [.ok(Self.reply(Self.payload))])
        await #expect(throws: (any Error).self) {
            _ = try await CloudBoost.extractText("Fuunji", key: "chave-de-teste",
                                                 http: Self.stubbedHTTP(host: host, connectivity: .offline), endpoint: Self.endpoint(host))
        }
        #expect(NetStub.hits(host) == 0)
    }

    @Test func noKeyMeansNoCall() async {
        let host = "colar-sem-chave.netstub.test"
        NetStub.register(host, [.ok(Self.reply(Self.payload))])
        await #expect(throws: (any Error).self) {
            _ = try await CloudBoost.extractText("Fuunji", key: nil, http: Self.stubbedHTTP(host: host), endpoint: Self.endpoint(host))
        }
        #expect(NetStub.hits(host) == 0)
    }

    // MARK: Fila

    @Test func queuedTextRequestIsKeptUntilTheAnswerIsReady() throws {
        let container = try ColarTextoTests.container()
        let context = ModelContext(container)
        #expect(TravelTextCloud.done(for: "k1", context: context) == nil)
        TravelTextCloud.enqueue("Dia 1\nFuunji", key: "k1", context: context)
        // Ainda não feito: a fila guarda o texto, não a resposta.
        #expect(TravelTextCloud.done(for: "k1", context: context) == nil)
        let item = try #require(Outbox.undone(context).first { $0.ref == "k1" })
        #expect(item.outboxKind == .cloudText)
        item.result = Self.reply(Self.payload)
        item.done = true
        try context.save()
        #expect(TravelTextCloud.done(for: "k1", context: context) != nil)
        TravelTextCloud.forget("k1", context: context)
        #expect(TravelTextCloud.done(for: "k1", context: context) == nil)
    }

    // MARK: nameLocal

    @Test func parenthesesAfterTheNameCaptureJapanese() {
        let text = "- Fuunji (風雲児): tsukemen com fila grande."
        #expect(TravelTextParser.nameLocal(for: "Fuunji", in: text) == "風雲児")
        let draft = TravelTextParser.parse("Dia 1 — Shibuya\n- Fuunji (風雲児): tsukemen com fila grande.")
        #expect(draft.places.first { $0.name == "Fuunji" }?.nameLocal == "風雲児")
    }

    @Test func japaneseBeforeTheNameCaptureToo() {
        let draft = TravelTextParser.parse("Dia 1 — Shibuya\n- 風雲児 Fuunji: tsukemen com fila grande.")
        let place = draft.places.first { $0.name == "Fuunji" }
        #expect(place != nil)
        #expect(place?.nameLocal == "風雲児")
    }

    @Test func latinWordsInParenthesesAreNotANameLocal() {
        #expect(TravelTextParser.nameLocal(for: "Fuunji", in: "Fuunji (tsukemen, 風雲児)") == nil)
        #expect(TravelTextParser.nameLocal(for: "Fuunji", in: "Fuunji (tsukemen de peixe)") == nil)
        #expect(TravelTextParser.nameLocal(for: "Fuunji", in: "Fuunji sem nada") == nil)
    }

    @Test func nameLocalFillsAnExistingPlaceWhenTheSecondMentionHasIt() {
        let draft = TravelTextParser.parse("Dia 1\n- Fuunji: bom.\n- Fuunji (風雲児): de novo.")
        let places = draft.places.filter { $0.name == "Fuunji" }
        #expect(places.count == 1)
        #expect(places.first?.nameLocal == "風雲児")
    }
}
