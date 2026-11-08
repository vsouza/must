import CoreLocation
import Foundation

// "Agora vale" (prompt 26 §2): tipos do ranker local. Tudo valor (nada de `@Model`), pra rodar fora do main e nos testes.

/// Um Must do board já reduzido ao que o ranker precisa.
struct SuggestPlace: Equatable, Sendable {
    var id: String
    var name: String
    /// "drink", "eat"… (nome da lista, sem "Must").
    var listName: String
    /// `MustColor.rawValue` da lista.
    var color: String
    var kind: ListKind
    var sub: String?
    var lat: Double
    var lng: Double
    var done: Bool
    var state: OpenState
    /// `DayWindow.rawValue`: morning, lunch, afternoon, dinner, night.
    var windows: Set<String>
    /// Tem horário do Google (`state` é de verdade, não `.unknown`).
    var hasHours: Bool { state != .unknown }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    /// Cobre de chuva: museu, galeria, café, livraria, loja.
    var isIndoor: Bool {
        if kind == .photo { return false }
        if kind == .art || color == "shop" || color == "coffee" { return true }
        let text = ((sub ?? "") + " " + name).lowercased()
        return ["museu", "museum", "galeria", "café", "cafe", "kissaten", "livraria", "biblioteca", "cinema"].contains { text.contains($0) }
    }
}

/// A parada do dia aceito que está valendo agora.
struct SuggestPlanStop: Hashable, Sendable {
    var id: String
    var placeId: String?
    var label: String
    /// "saia 14:35".
    var action: String
    var lat: Double?
    var lng: Double?
    /// Passou do fim previsto: desde quando devia estar nela.
    var lateSince: Date?
    /// Parada longe de onde você está: minutos até lá (só quando ≥ 10), pro "a 18 min daqui".
    var away: Int? = nil
}

/// Luz boa de hoje (ou de amanhã): janela do golden.
struct SuggestLight: Hashable, Sendable {
    var start: Date
    var end: Date
    var isToday: Bool
}

struct SuggestInputs: Sendable {
    var region: Region
    var now: Date
    /// GPS; sem GPS, o bairro do hotel / centro da cidade.
    var here: CLLocationCoordinate2D?
    var places: [SuggestPlace]
    var plan: SuggestPlanStop?
    var events: [ShowEvent] = []
    /// Fora do board (Google, Wikipedia, Foursquare), do cache: só pra "indicado".
    var indicated: [NearbyPlace] = []
    /// Nomes (minúsculos) dos lugares do board, pra não indicar o que você já tem.
    var boardNames: Set<String> = []
    /// Chuva provável nas próximas 2 h (minutos até começar).
    var rainInMinutes: Int?
    var light: SuggestLight?
    /// Gosto por cor de lista: 0–2 (as listas que você mais usa).
    var taste: [String: Int] = [:]
    var dismissed: Set<String> = []
    /// Sugerido antes (há mais de 1 h): −2.
    var shownEarlier: Set<String> = []
}

struct Suggestion: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case plan, must, closing, event, light, rain, indicated }
    /// Tinta = Must; laranja = evento; papel = o resto.
    enum Style: String, Sendable { case ink, orange, paper }

    var id: String
    var kind: Kind
    var style: Style
    /// "MUST DRINK · ABERTO".
    var label: String
    /// "240 m".
    var trailing: String?
    var title: String
    var meta: String
    var reasons: [String]
    var placeId: String?
    var eventId: String?
    var coordinate: CLLocationCoordinate2D?
    var url: URL?
    var score: Double
    /// Minutos até fechar/começar (desempate: o que acaba antes).
    var urgencyMinutes: Int?

    var reasonLine: String { reasons.joined(separator: " · ") }

    static func == (a: Suggestion, b: Suggestion) -> Bool { a.id == b.id && a.score == b.score && a.label == b.label && a.meta == b.meta }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
