import Foundation

/// Pinos do mapa montados uma vez por mudança (Rodada 21 · fatia 1, A.2). O `body` do mapa lê os pinos
/// mais de uma vez (cena e "Perto de você"); antes cada leitura refazia o trabalho de todos os lugares.
/// Fica fora do `@Observable` de propósito: escrever aqui dentro de um `body` não redesenha.
@MainActor
final class PinsMemo {
    /// O que, se mudar, pede pinos novos. As camadas ligadas não entram: os pinos são todos e a camada filtra depois.
    struct Key: Hashable {
        /// Conjunto de lugares (ids, horário, reserva, 済, bairro, lista, coordenada): `PlacesRevision`.
        var revision: Int
        /// Minuto do relógio (o aberto/fechando muda por minuto).
        var minute: Int
        var timeZone: String
        /// Paradas de hoje e de amanhã com 済 (id da parada, feito, lugar).
        var today: [String]
        var tomorrow: [String]
        var focusPlaceId: String?
        var hasSelection: Bool
        var cityName: String?
        /// Posição de quem está no mapa (a legenda "14 min a pé" depende dela) e o raio de "a pé".
        var here: String
        var walkMaxKm: Double
    }

    /// Quantas vezes os pinos foram montados de verdade (pros testes).
    private(set) var buildCount = 0
    private var key: Key?
    private var value: [MapPin] = []

    func pins(for key: Key, build: () -> [MapPin]) -> [MapPin] {
        if key == self.key { return value }
        let built = build()
        value = built
        self.key = key
        buildCount += 1
        return built
    }
}
