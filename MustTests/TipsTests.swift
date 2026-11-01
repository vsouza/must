import Foundation
import Testing
@testable import Must

struct TipsParsingTests {
    @Test func googleReviewsKeepOriginalAndTranslation() throws {
        let json = """
        {"rating": 4.7, "userRatingCount": 1248, "reviews": [
          {"name": "places/x/reviews/1", "rating": 4, "relativePublishTimeDescription": "há 5 meses",
           "text": {"text": "Pontualidade total; chegue 10 min antes.", "languageCode": "pt-BR"},
           "originalText": {"text": "予約時間厳守。10分前に着くのがベスト。", "languageCode": "ja"},
           "authorAttribution": {"displayName": "Tabelog-er", "uri": "https://maps.google.com/x"},
           "publishTime": "2026-06-01T10:00:00.000Z"},
          {"name": "places/x/reviews/2", "rating": 5, "text": {"text": "Uni from Hokkaido!", "languageCode": "en"},
           "originalText": {"text": "Uni from Hokkaido!", "languageCode": "en"}, "authorAttribution": {"displayName": "Marcus L."}}
        ]}
        """
        let batch = try GoogleReviewsTips.parse(Data(json.utf8))
        #expect(batch.rating == 4.7)
        #expect(batch.ratingCount == 1248)
        #expect(batch.tips.count == 2)
        let jp = batch.tips[0]
        #expect(jp.isJapanese)
        #expect(jp.quote.hasPrefix("予約"))
        #expect(jp.translation == "Pontualidade total; chegue 10 min antes.")
        #expect(jp.author == "Tabelog-er")
        #expect(jp.date != nil)
        #expect(batch.tips[1].originalText == nil) // mesmo texto: sem "original"
        #expect(batch.tips[1].translation == nil)
    }

    @Test func foursquareMatchAndTips() throws {
        let search = #"{"results": [{"fsq_place_id": "abc", "name": "Outro"}, {"fsq_place_id": "def", "name": "Mercado Central"}]}"#
        #expect(FoursquareTips.bestMatch(Data(search.utf8), name: "Mercado Central") == "def")
        let tips = #"[{"id": "t1", "text": "Doce de leite da banca 12", "created_at": "2025-03-01T12:00:00.000Z", "agree_count": 7}, {"id": "t2", "text": ""}]"#
        let batch = try FoursquareTips.parseTips(Data(tips.utf8))
        #expect(batch.tips.count == 1)
        #expect(batch.tips[0].votes == 7)
    }

    @Test func redditKeepsOnlyCommentsThatMentionThePlace() {
        let json = """
        [{"data": {"children": []}},
         {"data": {"children": [
           {"kind": "t1", "data": {"name": "t1_a", "body": "Udatsu was the highlight, bring cash", "score": 214, "author": "tokyo_eats", "created_utc": 1760000000,
             "replies": {"data": {"children": [{"kind": "t1", "data": {"name": "t1_b", "body": "agree about udatsu", "score": 12, "author": "x"}}]}}}},
           {"kind": "t1", "data": {"name": "t1_c", "body": "Go to Sukiyabashi instead", "score": 500, "author": "y"}}
         ]}}]
        """
        // Exige o nome do board no comentário ("Sukiyabashi" fica de fora mesmo com mais votos).
        let short = RedditTips.comments(Data(json.utf8), mentioning: ["Udatsu"], subreddit: "JapanTravel")
        #expect(short.map(\.id) == ["t1_a", "t1_b"])
        #expect(short.first?.author == "u/tokyo_eats")
    }

    @Test func captionAlwaysFirstThenUseful() {
        let tips = [
            Tip(id: "a", source: .google, text: "ok", rating: 3),
            Tip(id: "b", source: .reddit, text: "Muito útil, detalhada, com o que pedir e quando ir, e quanto custa.", votes: 300),
            Tip(id: "c", source: .caption, text: "de onde veio"),
        ]
        #expect(TipsModel.sorted(tips, by: .useful).map(\.id) == ["c", "b", "a"])
    }

    @Test func sourceCaptionBecomesFirstCard() async throws {
        let q = TipsQuery(id: "j01", name: "Udatsu Sushi", city: "Tóquio", region: .jp, lat: 0, lng: 0,
                          sourceKind: .instagram, sourceCaption: "Pede o uni extra.", sourceAuthor: "@gustavo.viaja", sourceSavedAt: "2026-10-02")
        let batch = try await SourceCaptionTips().tips(for: q)
        #expect(batch.tips.first?.source == .caption)
        #expect(batch.tips.first?.author == "@gustavo.viaja")
        #expect(batch.tips.first?.date != nil)
    }

    @Test func cacheServesFreshAndDropsAfter30Days() async {
        let cache = TipsCache()
        let q = TipsQuery(id: "test-\(UUID().uuidString.prefix(6))", name: "X", city: "BH", region: .bh, lat: 0, lng: 0)
        await cache.store(TipsBatch(tips: [Tip(id: "1", source: .google, text: "a")], fetchedAt: Date()), q, .google)
        #expect(await cache.batch(q, .google)?.tips.count == 1)
        await cache.store(TipsBatch(tips: [Tip(id: "1", source: .google, text: "a")], fetchedAt: Date().addingTimeInterval(-2 * 86400)), q, .google)
        #expect(await cache.batch(q, .google) == nil)                          // passou de 24 h
        #expect(await cache.batch(q, .google, allowStale: true) != nil)        // sem rede, ainda serve
        await cache.store(TipsBatch(tips: [], fetchedAt: Date().addingTimeInterval(-31 * 86400)), q, .google)
        #expect(await cache.batch(q, .google, allowStale: true) == nil)        // 30 dias: apaga
    }
}

struct TipsSummaryParseTests {
    @Test func parsesPlainTextFallback() {
        let s = TipsAI.parse("RESUMO: Vá **cedo** e prove o **fígado com jiló**.\nTEMAS: cedo|3|positive; caro|2|negative; queijo|1|neutral")
        #expect(s?.summary == "Vá **cedo** e prove o **fígado com jiló**.")
        #expect(s?.themes.map(\.word) == ["cedo", "caro", "queijo"])
        #expect(s?.themes[1].sentiment == .negative)
        #expect(s?.themes[0].count == 3)
    }
}
