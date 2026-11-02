import CoreLocation
import Foundation

/// O que se sabe do ingresso pra achar o lugar dele no board. Vem da leitura e, se houve, do Places.
struct TicketCandidate: Equatable, Sendable {
    /// Título lido (ou nome do fornecedor).
    var title: String
    /// `placeId` do Places, se a busca conferiu o ponto de encontro.
    var placeId: String?
    var lat: Double?
    var lng: Double?
    /// Ponto de encontro ou endereço como veio no ingresso.
    var address: String?
}

/// Um lugar do board que pode ser o do ingresso. O `score` é a confiança do casamento (0–1).
struct TicketMatch: Equatable, Identifiable, Sendable {
    enum Reason: String, Sendable {
        case placeId = "mesmo lugar no Places"
        case coordinate = "mesmo ponto no mapa"
        case address = "mesmo endereço"
        case name = "nome parecido"
    }

    var placeId: String
    var name: String
    var area: String?
    var score: Double
    var reason: Reason

    var id: String { placeId }
    var percent: Int { Int((score * 100).rounded()) }
}

/// Casa o ingresso com um `Place` do board (prompt 15 · A): placeId, depois coordenada, depois endereço, e só então o nome.
/// Nome parecido sozinho nunca vira o lugar escolhido (fica como sugestão de baixa confiança).
@MainActor
enum TicketMatcher {
    /// Acima disso o lugar já vem marcado em "Vincular a".
    static let autoLinkScore = 0.8
    /// Mesmo ponto: a até 150 m (o ponto de encontro costuma ser a entrada do prédio).
    static let coordinateRadius: CLLocationDistance = 150
    static let addressThreshold = 0.5

    /// Todos os lugares com alguma chance, do mais provável pro menos (empate: nome).
    static func rank(_ candidate: TicketCandidate, places: [Place]) -> [TicketMatch] {
        places.compactMap { place -> TicketMatch? in
            guard let scored = score(candidate, against: place) else { return nil }
            return TicketMatch(placeId: place.id, name: place.name, area: place.area, score: scored.score, reason: scored.reason)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
    }

    /// O lugar a marcar sozinho: só com placeId, coordenada ou endereço forte.
    static func best(_ candidate: TicketCandidate, places: [Place]) -> TicketMatch? {
        rank(candidate, places: places).first { $0.score >= autoLinkScore }
    }

    static func score(_ candidate: TicketCandidate, against place: Place) -> (score: Double, reason: TicketMatch.Reason)? {
        var best: (score: Double, reason: TicketMatch.Reason)?
        func offer(_ score: Double, _ reason: TicketMatch.Reason) {
            if best == nil || score > best!.score { best = (score, reason) }
        }

        if let id = candidate.placeId, let placeId = place.placeId, id == placeId {
            offer(0.98, .placeId)
        }
        if let lat = candidate.lat, let lng = candidate.lng, !place.approx, place.lat != 0 || place.lng != 0 {
            let distance = CLLocation(latitude: lat, longitude: lng).distance(from: CLLocation(latitude: place.lat, longitude: place.lng))
            if distance <= coordinateRadius { offer(0.9, .coordinate) }
        }
        if let address = candidate.address, !address.isEmpty {
            let placeAddress = [place.extra?.experience?.meetingPoint, place.area].compactMap { $0 }.joined(separator: " ")
            let overlap = dice(tokens(address), tokens(placeAddress))
            if overlap >= addressThreshold { offer(0.6 + 0.3 * overlap, .address) }
        }
        if PlaceMatcher.similar(place.name, candidate.title) { offer(0.55, .name) }
        return best
    }

    /// Palavras do endereço que importam (sem acento, sem "portão", "de", "gate"…).
    static func tokens(_ text: String) -> Set<String> {
        let stop: Set<String> = [
            "the", "and", "with", "from", "gate", "entrance", "exit", "meeting", "point", "portao", "entrada", "saida", "ponto",
            "encontro", "para", "por", "com", "dos", "das", "del", "perto", "near", "ao", "lado",
        ]
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter }.map(String.init)
        return Set(words.filter { $0.count >= 3 && !stop.contains($0) })
    }

    /// Coeficiente de Dice entre dois conjuntos de palavras: 1 = iguais, 0 = nada em comum.
    static func dice(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return 2 * Double(a.intersection(b).count) / Double(a.count + b.count)
    }
}
