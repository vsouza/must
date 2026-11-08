import Foundation
import Testing
@testable import Must

/// Corpus de ingressos (prompt 31 · 6): mede o acerto por campo e garante metas mínimas.
/// `TEST_RUNNER_TICKET_REPORT_PATH` grava a tabela em Markdown; `TEST_RUNNER_TICKET_CORPUS_DIR` exporta os arquivos.
@MainActor
struct TicketCorpusTests {
    static func run(_ ticket: TicketCase, form: TicketForm) async -> TicketScore {
        let source = TicketCorpus.source(ticket, form: form)
        let start = Date()
        let extracted: ExtractedTicket
        do {
            extracted = try await TicketPipeline.run(source, region: ticket.region, useModel: false)
        } catch {
            return TicketScore(caseID: ticket.id, kindLabel: ticket.label, form: form, hits: [:], seconds: 0)
        }
        return TicketScoring.score(ticket, form: form, extracted: extracted, seconds: Date().timeIntervalSince(start))
    }

    static func runAll() async -> [TicketScore] {
        var scores: [TicketScore] = []
        for ticket in TicketCorpus.all {
            for form in TicketForm.allCases { scores.append(await run(ticket, form: form)) }
        }
        return scores
    }

    @Test func corpusReport() async throws {
        if let dir = ProcessInfo.processInfo.environment["TICKET_CORPUS_DIR"] { TicketCorpus.export(to: URL(fileURLWithPath: dir)) }
        let scores = await Self.runAll()
        let table = TicketScoring.markdown(scores, title: "Acerto por campo no corpus (\(scores.count) arquivos)")
        print(table)
        if let path = ProcessInfo.processInfo.environment["TICKET_REPORT_PATH"] {
            try table.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #expect(scores.count == TicketCorpus.all.count * TicketForm.allCases.count)
        // Metas mínimas por campo (o corpus é sintético e limpo; no aparelho, foto real fica abaixo disso).
        let goals: [TicketField2: Double] = [.titulo: 0.9, .data: 0.95, .hora: 0.9, .local: 0.9, .assento: 0.9, .portao: 0.9,
                                             .codigo: 0.95, .qr: 0.95, .nome: 0.9]
        for (field, goal) in goals {
            let values = scores.compactMap { $0.hits[field] }
            let rate = Double(values.filter { $0 }.count) / Double(max(values.count, 1))
            #expect(rate >= goal, "\(field.rawValue): \(rate) < \(goal)")
        }
    }
}
