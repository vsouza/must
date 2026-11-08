import Foundation

/// Leitura completa de um item: ler (PDFKit/Vision/passe) e extrair os campos.
enum TicketPipeline {
    static func run(_ source: TicketSource, region: Region) async throws -> ExtractedTicket {
        let reading = try await TicketReader.read(source)
        return TicketExtractor.extract(reading, region: region)
    }
}
