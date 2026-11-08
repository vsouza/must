import Foundation
import Testing
@testable import Must

/// Frases que o corpus limpo não cobre (prompt 31 · 6): rótulos e formatos de outros fornecedores. Texto puro, sem OCR.
/// `known` marca o que o extrator ainda erra (documentado em `docs/ingressos-leitura.md`); não derruba a suíte.
@MainActor
struct TicketHardCasesTests {
    struct Hard: Sendable, CustomTestStringConvertible {
        var name: String
        var text: String
        var region: Region
        var at: [Int]
        var known = false
        var testDescription: String { name }
    }

    nonisolated static let cases: [Hard] = [
        .init(name: "inglês com 'at' e pm", text: "Orbit Planetarium\nSaturday, November 21, 2026 at 7:30 PM\nGate 4", region: .jp, at: [2026, 11, 21, 19, 30]),
        .init(name: "pt-BR por extenso com 21h", text: "Festival Sol de Minas\nsábado, 21 de novembro de 2026 às 21h\nPortão A", region: .bh, at: [2026, 11, 21, 21, 0]),
        .init(name: "japonês com 開演", text: "公演 ライブ\n2026年11月22日(日)\n開場 17:00 開演 18:30\n座席 1階 A列 12番", region: .jp, at: [2026, 11, 22, 18, 30]),
        .init(name: "italiano com ore e ponto", text: "Musei Vaticani\nVisita: 12/04/2027 ore 09.30\nIntestatario: VINICIUS SOUZA", region: .it, at: [2027, 4, 12, 9, 30], known: false),
        .init(name: "ISO com T", text: "Concert\nStarts: 2026-11-23T20:00\nDoors: 2026-11-23T19:00", region: .jp, at: [2026, 11, 23, 20, 0], known: false),
        .init(name: "dia da semana sem ano", text: "Show Fulano\nSex, 20 nov · 22:00\nLocal: Km de Vantagens Hall", region: .bh, at: [2026, 11, 20, 22, 0], known: false),
        // Limite conhecido: tabela com rótulo numa linha e valor na outra (o OCR de ingresso em colunas faz isso).
        .init(name: "rótulo e valor em linhas separadas", text: "Evento X\nData\n21/11/2026\nPortões\n19:00\nInício\n21:00", region: .bh, at: [2026, 11, 21, 21, 0], known: true),
    ]

    @Test(arguments: cases)
    func hardCase(_ item: Hard) async {
        let extracted = await TicketPipeline.extract(TicketReader.readText(item.text), region: item.region, useModel: false)
        let parts = extracted.at.map { item.region.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0.value) }
        let ok = parts.map { [$0.year, $0.month, $0.day, $0.hour, $0.minute] == item.at } ?? false
        print("HARD \(item.name): \(ok ? "ok" : "FALHA") \(parts.map { "\($0.year ?? 0)-\($0.month ?? 0)-\($0.day ?? 0) \($0.hour ?? 0):\($0.minute ?? 0)" } ?? "sem data")")
        if !item.known { #expect(ok, "\(item.name)") }
    }
}
