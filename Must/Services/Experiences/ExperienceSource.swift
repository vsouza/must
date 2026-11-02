import Foundation

/// Consulta a uma fonte de experiências com API (busca por texto e por dia).
struct ExperienceQuery: Sendable {
    var text: String
    var lat: Double?
    var lng: Double?
    var radiusKm: Double = 3
    /// Meia-noite do dia desejado, no fuso da região.
    var day: Date?
    var region: Region
}

/// Uma experiência devolvida por uma API (o formato comum; cada fonte converte o seu).
struct ExperienceOffer: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var supplier: ExperienceSupplier
    var url: URL?
    var imageURL: URL?
    var durationMinutes: Int?
    var priceFrom: Double?
    var currency: String?
    var rating: Double?
    var reviewCount: Int?
    /// Horários com vaga, quando a fonte devolve (`/availability`).
    var sessions: [EventSession]
}

/// Fonte de experiências com API (decisão de 02/11/2026: **protocolo só**, sem cliente).
/// Viator e GetYourGuide plugam aqui depois, atrás de flag e de chave. Sem chave, a fonte não existe.
/// Enquanto isso, experiência entra colando o link (`ExperienceLinkReader`) ou à mão.
protocol ExperienceSource: Sendable {
    var supplier: ExperienceSupplier { get }
    var isConfigured: Bool { get }
    func search(_ query: ExperienceQuery) async throws -> [ExperienceOffer]
}
