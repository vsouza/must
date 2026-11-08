import Foundation

/// Leitura completa de um item (prompt 31 · 6): ler (camada de texto do PDF › OCR do Vision › QR/barras › passe), extrair
/// com regras determinísticas e, se o aparelho tem Apple Intelligence, deixar o modelo completar o que ficou incerto.
/// Sem modelo (simulador, aparelho sem suporte) o resultado é o das regras. Nada sai do aparelho.
enum TicketPipeline {
    static func run(_ source: TicketSource, region: Region, useModel: Bool = true) async throws -> ExtractedTicket {
        let reading = try await TicketReader.read(source)
        return await extract(reading, region: region, useModel: useModel)
    }

    static func extract(_ reading: TicketReading, region: Region, useModel: Bool = true) async -> ExtractedTicket {
        let base = TicketExtractor.extract(reading, region: region)
        guard useModel else { return base }
        return await TicketModelExtractor.enrich(base, text: reading.text, region: region)
    }
}
