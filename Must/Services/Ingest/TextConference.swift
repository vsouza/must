import CoreLocation
import Foundation
import SwiftData

/// Lugar de um texto colado, com o resultado da conferência no Places (prompt 18 · E.23).
/// Sem rede, a lista vai pra fila de saída (`OutboxKind.conferText`); quando a rede volta, o `Outbox` confere e
/// guarda o mesmo JSON com placeId e coordenada. O Colar texto aplica o resultado da próxima vez que abre o texto.
struct ConferredPlace: Codable, Sendable, Equatable {
    /// Nome como o texto escreveu (chave pra casar de volta).
    var key: String
    /// Nome oficial do Places (ou o próprio `key` enquanto não conferido).
    var name: String
    var area: String?
    var placeId: String?
    var lat: Double?
    var lng: Double?
    /// `MustColor.rawValue` vindo do `primaryType` do Places.
    var category: String?
    var sub: String?
}

@MainActor
enum TextConference {
    /// Chave estável do texto (FNV-1a 64): o mesmo texto colado acha a mesma conferência depois.
    static func key(for text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Põe a conferência na fila (uma por texto: pedir de novo não duplica).
    static func enqueue(_ places: [ExtractedPlace], key: String, context: ModelContext) {
        let item = Outbox.enqueue(.conferText, ref: key, context: context)
        guard item.result == nil else { return }
        let pending = places.map {
            ConferredPlace(key: $0.name, name: $0.name, area: $0.area, placeId: nil, lat: nil, lng: nil, category: nil, sub: nil)
        }
        item.result = try? JSONEncoder().encode(pending)
        try? context.save()
    }

    /// Conferência já feita pela fila pra este texto (nil = ainda não).
    static func done(for key: String, context: ModelContext) -> [ConferredPlace]? {
        let done = (try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.done }))) ?? []
        guard let item = done.last(where: { $0.ref == key && $0.outboxKind == .conferText }), let data = item.result else { return nil }
        return try? JSONDecoder().decode([ConferredPlace].self, from: data)
    }

    /// Tira da fila o que já foi usado (o texto foi salvo).
    static func forget(_ key: String, context: ModelContext) {
        let done = (try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.done }))) ?? []
        for item in done where item.ref == key && item.outboxKind == .conferText {
            context.delete(item)
        }
    }

    /// Confere a lista no Places (chamado pela fila quando volta a rede). Quem não acha sai sem placeId.
    static func conference(_ pending: [ConferredPlace], provider: any PlacesProviding, near: CLLocationCoordinate2D) async -> [ConferredPlace] {
        var out: [ConferredPlace] = []
        for item in pending {
            let candidate = ExtractedPlace(name: item.name, area: item.area, hint: "texto colado")
            let found = await PlaceResolver.resolve(candidate, provider: provider, near: near)
            out.append(ConferredPlace(key: item.key, name: found.name, area: item.area, placeId: found.placeId,
                                      lat: found.lat, lng: found.lng, category: found.category?.rawValue, sub: found.sub))
        }
        return out
    }

    /// Aplica a conferência feita aos lugares do texto (casa pelo nome que o texto usou).
    static func apply(_ conferred: [ConferredPlace], to places: [ExtractedPlace]) -> [ExtractedPlace] {
        places.map { place in
            let key = PlaceMatcher.normalize(place.name)
            guard let c = conferred.first(where: { PlaceMatcher.normalize($0.key) == key }), let id = c.placeId else { return place }
            var out = place
            out.placeId = id
            out.lat = c.lat
            out.lng = c.lng
            if PlaceMatcher.normalize(c.name) != key {
                out.aliases = ([place.name] + place.aliases).filter { $0 != c.name }
                out.name = c.name
            }
            if let color = c.category.flatMap(MustColor.init(rawValue:)) { out.category = color }
            out.sub = c.sub ?? out.sub
            return out
        }
    }
}
