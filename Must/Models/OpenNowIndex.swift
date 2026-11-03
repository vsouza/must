import CoreLocation
import Foundation

/// Abertos-agora e distância de um conjunto de lugares, recalculados só quando mudam as entradas (prompt 18 · A.3).
///
/// Antes, a Lista chamava `openState` dentro do comparador do `sort` (n log n chamadas por redesenho). Agora a tela
/// guarda um `OpenNowIndex` (`@State`) e pede o `Snapshot`: ele só recalcula quando muda o minuto do relógio,
/// a posição (≥ 50 m desde o cálculo anterior), o fuso ou o próprio conjunto de lugares (`PlacesRevision`).
/// Fica fora do `@Observable` de propósito: escrever aqui dentro de um `body` não dispara redesenho.
@MainActor
final class OpenNowIndex {
    /// O que, se mudar, pede um novo cálculo.
    struct Inputs: Equatable {
        /// Minutos desde a época (o relógio conta por minuto; segundos não mudam nada).
        var minute: Int
        var timeZone: String
        /// Revisão do conjunto (ids, horário, reserva, 済…): ver `PlacesRevision`.
        var revision: Int
        var origin: CLLocation?

        static func == (lhs: Inputs, rhs: Inputs) -> Bool {
            lhs.minute == rhs.minute && lhs.timeZone == rhs.timeZone && lhs.revision == rhs.revision
                && sameSpot(lhs.origin, rhs.origin)
        }
    }

    /// Resultado: quem está aberto agora e a distância de cada lugar (sem `Place` dentro, pra ser barato de copiar).
    struct Snapshot {
        var states: [String: OpenState] = [:]
        var distances: [String: CLLocationDistance] = [:]

        func isOpen(_ placeId: String) -> Bool { states[placeId]?.isOpen ?? false }
        func distance(_ placeId: String) -> CLLocationDistance? { distances[placeId] }
    }

    /// Quantas vezes o índice recalculou (pros testes: o modelo só recalcula nos gatilhos).
    private(set) var recomputeCount = 0
    private var inputs: Inputs?
    private var snapshot = Snapshot()

    init() {}

    /// Snapshot pra `places` no instante `now`. Igual ao anterior se nada relevante mudou.
    func snapshot(for places: [Place], now: Date, timeZone: TimeZone, location: CLLocation?) -> Snapshot {
        let current = Inputs(minute: Int(now.timeIntervalSinceReferenceDate / 60), timeZone: timeZone.identifier,
                             revision: PlacesRevision.of(places), origin: location)
        if let inputs, inputs == current { return snapshot }
        var next = Snapshot()
        for place in places {
            next.states[place.id] = place.openState(at: now, timeZone: timeZone)
            if let location { next.distances[place.id] = place.location.distance(from: location) }
        }
        snapshot = next
        inputs = current
        recomputeCount += 1
        return next
    }
}

/// Duas posições contam como "a mesma" enquanto estiverem a menos de 50 m uma da outra (a mesma regra do GPS).
private func sameSpot(_ a: CLLocation?, _ b: CLLocation?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): x.distance(from: y) < LocationService.distanceFilter
    default: false
    }
}

/// Assinatura do conjunto de lugares: muda quando algo que afeta horário, distância ou 済 muda.
/// Lê só campos simples e os bytes do horário (sem decodificar nada).
enum PlacesRevision {
    static func of(_ places: [Place]) -> Int {
        var hasher = Hasher()
        hasher.combine(places.count)
        for place in places {
            hasher.combine(place.id)
            hasher.combine(place.done?.at)
            hasher.combine(place.reservation?.at)
            hasher.combine(place.hoursData)
            hasher.combine(place.area)
            hasher.combine(place.list?.id)
            hasher.combine(place.lat)
            hasher.combine(place.lng)
        }
        return hasher.finalize()
    }
}
