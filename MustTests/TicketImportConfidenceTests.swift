import Foundation
import Testing
@testable import Must

@MainActor
struct TicketImportConfidenceTests {
    private func model(title: String = "Tour", meta: [TicketField: FieldMeta]) -> TicketImportModel {
        let m = TicketImportModel()
        var d = TicketDraft(at: Date(timeIntervalSince1970: 1_800_000_000))
        d.title = title
        d.meta = meta
        m.draft = d
        return m
    }

    @Test func tudoAltoLiberaSalvarEmDestaque() {
        let m = model(meta: [.title: .init(confidence: 0.95, origin: "lido do texto"), .when: .init(confidence: 0.9, origin: "do passe")])
        #expect(m.isAllConfident)
    }

    @Test func umCampoEmDuvidaDesligaODestaque() {
        let m = model(meta: [.title: .init(confidence: 0.55, origin: "lido do texto"), .when: .init(confidence: 0.9, origin: "do passe")])
        #expect(!m.isAllConfident)
    }

    @Test func semLeituraDeQuandoNaoEhConfiante() {
        let m = model(meta: [.title: .init(confidence: 0.95, origin: "lido do texto")])
        #expect(!m.isAllConfident)
    }

    @Test func semTituloNaoSalva() {
        let m = model(title: "", meta: [.title: .init(confidence: 0.95, origin: "x"), .when: .init(confidence: 0.9, origin: "x")])
        #expect(!m.isAllConfident)
    }
}
