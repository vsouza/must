#if DEBUG
import CoreLocation
import Foundation

/// Amostra do Colar texto (prompt 18 · E): uma resposta "tipo ChatGPT" de Tóquio, com 2 dias, 8 lugares, 2 links e 3 dicas.
/// `-debugScreen colar-texto:amostra` abre a tela com ela; `-debugPlaces fake` confere os lugares com as coordenadas daqui.
/// O mesmo texto está em `MustTests/Fixtures/colar-texto-amostra.txt` (o teste confere que é igual).
enum ColarTextoSample {
    static let text = [
        "Claro! Aqui vai um roteiro de 2 dias em Tóquio, com comida boa e templos sem correria.",
        "",
        "**Dia 1 — Shibuya e Harajuku**",
        "",
        "- **Meiji Jingu**: santuário enorme e silencioso, no meio do bairro.",
        "- **Fuunji** (tsukemen de peixe e frango): tem fila grande, mas anda rápido.",
        "- **Koffee Mameya**: cafeteria de especialidade pequena, perto da Omotesando.",
        "",
        "**Dia 2 — Asakusa e Ueno**",
        "",
        "Comece cedo no Senso-ji (antes das 8h fica vazio). Para o almoço, Asakusa Imahan — sukiyaki, reserve com antecedência. À tarde, Tokyo National Museum e uma volta no Ameyoko. Para fechar, um drink no Bar Gen Yamamoto.",
        "",
        "Compre o Tokyo Subway Ticket de 72h antes de começar o dia 1, porque ele cobre metrô e a maioria dos ônibus.",
        "",
        "Fontes: https://www.instagram.com/p/C8xYz123abc/ e https://maps.app.goo.gl/Qm3PkR7sT1vUu6Ab9",
    ].joined(separator: "\n")

    /// Lugares que o Places "acha" pra amostra (Text Search por nome).
    static let candidates: [PlaceCandidate] = [
        PlaceCandidate(id: "fake-meiji-jingu", name: "Meiji Jingu", address: "Shibuya", lat: 35.6764, lng: 139.6993,
                       primaryType: "shinto_shrine"),
        PlaceCandidate(id: "fake-fuunji", name: "Fuunji", address: "Shibuya", lat: 35.6962, lng: 139.7025,
                       primaryType: "ramen_restaurant"),
        PlaceCandidate(id: "fake-koffee-mameya", name: "Koffee Mameya", address: "Harajuku", lat: 35.6685, lng: 139.7063,
                       primaryType: "cafe"),
        PlaceCandidate(id: "fake-senso-ji", name: "Senso-ji", address: "Asakusa", lat: 35.7148, lng: 139.7967,
                       primaryType: "buddhist_temple"),
        PlaceCandidate(id: "fake-asakusa-imahan", name: "Asakusa Imahan", address: "Asakusa", lat: 35.7128, lng: 139.7937,
                       primaryType: "japanese_restaurant"),
        PlaceCandidate(id: "fake-tokyo-national-museum", name: "Tokyo National Museum", address: "Ueno", lat: 35.7189, lng: 139.7765,
                       primaryType: "museum"),
        PlaceCandidate(id: "fake-ameyoko", name: "Ameyoko", address: "Ueno", lat: 35.7105, lng: 139.7745, primaryType: "market"),
        PlaceCandidate(id: "fake-bar-gen-yamamoto", name: "Bar Gen Yamamoto", address: "Asakusa", lat: 35.7135, lng: 139.7960,
                       primaryType: "bar"),
    ]

    static let details: [String: PlaceDetails] = [:]

    /// Legenda de mentira pros links da amostra (sem rede). Sem lugar novo: o teste de links não depende do Places.
    static func caption(for url: URL) -> Caption {
        Caption(source: LinkResolver.source(of: url), title: "Reel · Asakusa", text: "Senso-ji ao amanhecer, sem fila.", url: url)
    }
}
#endif
