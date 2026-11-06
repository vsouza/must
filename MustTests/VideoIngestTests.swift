import Foundation
import Testing
@testable import Must

/// Texto do vídeo → extrator (falso) → candidatos com a origem (prompt 29). Fixture: reel de comida em BH.
struct VideoIngestTests {
    static let screen = [
        VideoSnippet(origin: .screen, seconds: 4, text: "Mercado Central"),
        VideoSnippet(origin: .screen, seconds: 5, text: "Mercado Central"),
        VideoSnippet(origin: .screen, seconds: 9, text: "Fígado com jiló · R$ 38"),
    ]
    static let speech = [
        VideoSnippet(origin: .speech, seconds: 7, text: "o melhor fígado com jiló fica no Bar do Lulu"),
    ]

    static func fakeExtractor(_ text: String) -> [ExtractedPlace] {
        var out: [ExtractedPlace] = []
        if text.contains("Mercado Central") { out.append(ExtractedPlace(name: "Mercado Central", nameLocal: nil, area: nil, category: .shop, sub: nil, hint: "tela")) }
        if text.contains("Bar do Lulu") { out.append(ExtractedPlace(name: "Bar do Lulu", nameLocal: nil, area: nil, category: .drink, sub: nil, hint: "fala")) }
        return out
    }

    @Test func mergeMarksOriginsAndCollapsesRepeats() {
        let merged = VideoText.merge(caption: "Dica de BH", screen: Self.screen, speech: Self.speech)
        let lines = merged.split(separator: "\n").map(String.init)
        #expect(lines[0] == "[legenda] Dica de BH")
        #expect(lines.contains("[tela 00:04] Mercado Central"))
        #expect(lines.contains("[fala 00:07] o melhor fígado com jiló fica no Bar do Lulu"))
        #expect(lines.filter { $0.contains("Mercado Central") }.count == 1)
    }

    @Test func candidatesCarryWhereTheyWereSeen() async {
        let merged = VideoText.merge(caption: nil, screen: Self.screen, speech: Self.speech)
        let found = await VideoIngest.candidates(merged: merged) { Self.fakeExtractor($0) }
        #expect(found.count == 2)
        #expect(found[0].place.name == "Mercado Central")
        #expect(found[0].origin?.label == "visto na tela 00:04")
        #expect(found[1].place.name == "Bar do Lulu")
        #expect(found[1].origin?.label == "falado 00:07")
    }

    @Test func screenWinsOverSpeechWhenBothMentionThePlace() {
        let both = VideoText.merge(caption: nil,
                                   screen: [VideoSnippet(origin: .screen, seconds: 12, text: "Bar do Lulu")],
                                   speech: [VideoSnippet(origin: .speech, seconds: 3, text: "vamos no Bar do Lulu")])
        #expect(VideoText.origin(of: ["Bar do Lulu"], in: both)?.label == "visto na tela 00:12")
        #expect(VideoText.origin(of: ["Outro Lugar"], in: both) == nil)
    }

    @Test func mergeStaysWithinTheExtractorBudget() {
        let many = (0..<200).map { VideoSnippet(origin: .speech, seconds: Double($0), text: String(repeating: "palavra ", count: 10)) }
        let merged = VideoText.merge(caption: String(repeating: "x", count: 3000), screen: [], speech: many)
        #expect(merged.count <= CaptionFetcher.maxLength)
    }

    @Test func dedupeKeepsTheFullerReadingAtTheFirstInstant() {
        let out = VideoText.dedupe([
            VideoSnippet(origin: .screen, seconds: 2, text: "Udatsu"),
            VideoSnippet(origin: .screen, seconds: 3, text: "Udatsu Sushi"),
            VideoSnippet(origin: .screen, seconds: 4, text: "Udatsu Sushi"),
        ])
        #expect(out.count == 1)
        #expect(out[0].text == "Udatsu Sushi")
        #expect(out[0].seconds == 2)
    }

    @Test func shareInboxHasVideoKind() throws {
        let data = try JSONEncoder().encode(ShareInbox.Item(id: UUID().uuidString, kind: .video, createdAt: .now, fileName: "item.mov", text: nil))
        #expect(String(data: data, encoding: .utf8)?.contains("\"video\"") == true)
    }
}
