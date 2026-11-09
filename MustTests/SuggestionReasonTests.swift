import Testing
@testable import Must

/// Motivo de uma linha "Agora vale" (prompt 32 §2): uma linha, sem jargão do ranker, igual em Hoje e no Explorar.
struct SuggestionReasonTests {
    private func card(_ kind: Suggestion.Kind = .must, meta: String, reasons: [String], trust: String? = nil) -> Suggestion {
        Suggestion(id: "x", kind: kind, style: .ink, label: "", trailing: "240 m", title: "Fuunji", meta: meta, reasons: reasons,
                   placeId: "p", eventId: nil, coordinate: nil, url: nil, score: 1, urgencyMinutes: nil, trust: trust)
    }

    @Test func mustAbertoViraAbertoAte() {
        let line = SuggestionReason.line(card(meta: "fecha 22:00 · ramen", reasons: ["perto", "no board", "hora certa", "seu gosto"]))
        #expect(line == "seu Must · aberto até 22:00")
    }

    @Test func semJargaoDoRankerEComAvisoCurto() {
        let line = SuggestionReason.line(card(meta: "ramen", reasons: ["perto", "no board", "hora certa"],
                                              trust: "horário estimado · local aproximado"))
        #expect(line == "seu Must · ramen · horário a confirmar")
        for jargon in ["no board", "hora certa", "seu gosto", "local aproximado"] { #expect(!line.contains(jargon)) }
    }

    @Test func urgenteVemPrimeiro() {
        let line = SuggestionReason.line(card(.closing, meta: "fecha 14:30", reasons: ["fecha em 30 min", "perto", "no board"]))
        #expect(line == "fecha em 30 min · seu Must · aberto até 14:30")
    }

    @Test func eventoUsaOQueEle() {
        let line = SuggestionReason.line(card(.event, meta: "Sunplaza · 19:00", reasons: ["perto"]))
        #expect(line == "Sunplaza · 19:00")
    }
}
