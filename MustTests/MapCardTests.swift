import Foundation
import Testing
@testable import Must

/// Card do pino (prompt 27 §2.a): não pede foto nova em dado móvel (usa a do disco); textos do card.
struct MapCardTests {
    private let ref = PlacePhotoRef(name: "places/x/photos/1", author: "Kenji S.")
    private let file = URL(fileURLWithPath: "/tmp/full.jpg")
    private let small = URL(fileURLWithPath: "/tmp/thumb.jpg")

    private func net(_ status: Connectivity.Status, wifi: Bool, expensive: Bool) -> PrefetchPolicy.Network {
        PrefetchPolicy.Network(status: status, wifi: wifi, expensive: expensive)
    }

    @Test func dadoMovelNuncaPedeFotoNova() {
        let cellular = net(.online, wifi: false, expensive: true)
        // Nada no disco: placeholder, nada de rede.
        #expect(MapCardPhoto.source(refs: [ref], network: cellular, full: { _ in nil }, thumb: { _ in nil }) == .none)
        // Só a miniatura no disco: ela, sem buscar a grande.
        #expect(MapCardPhoto.source(refs: [ref], network: cellular, full: { _ in nil }, thumb: { _ in small }) == .disk(small))
        // Modo de Pouco Dados no Wi-Fi e offline: idem.
        #expect(MapCardPhoto.source(refs: [ref], network: net(.constrained, wifi: true, expensive: false),
                                    full: { _ in nil }, thumb: { _ in nil }) == .none)
        #expect(MapCardPhoto.source(refs: [ref], network: net(.offline, wifi: false, expensive: false),
                                    full: { _ in nil }, thumb: { _ in nil }) == .none)
    }

    @Test func discoPrimeiroEWiFiBusca() {
        let wifi = net(.online, wifi: true, expensive: false)
        #expect(MapCardPhoto.source(refs: [ref], network: wifi, full: { _ in file }, thumb: { _ in small }) == .disk(file))
        #expect(MapCardPhoto.source(refs: [ref], network: net(.online, wifi: false, expensive: true), full: { _ in file },
                                    thumb: { _ in nil }) == .disk(file))
        #expect(MapCardPhoto.source(refs: [ref], network: wifi, full: { _ in nil }, thumb: { _ in small }) == .fetch(placeholder: small))
        #expect(MapCardPhoto.source(refs: [], network: wifi) == .none)
        #expect(MapCardPhoto.credit(ref) == "Google · Kenji S.")
    }

    @Test func amigosNoMaximoDois() {
        let a = FriendVisit(id: "1", name: "Ana", initials: "AN", when: "mar 2025", note: "tsukemen frio, com ovo")
        let p = FriendVisit(id: "2", name: "Pedro", initials: "PE", when: "out 2024")
        let c = FriendVisit(id: "3", name: "Carol", initials: "CA", when: "jan 2026")
        #expect(MapCardFacts.friendsLine([a, p, c]) == "Ana e Pedro foram · “tsukemen frio, com ovo”")
        #expect(MapCardFacts.friendsLine([p]) == "Pedro foi · out 2024")
        #expect(MapCardFacts.friendsLine([]) == nil)
    }

    @MainActor @Test func fichaDeTresCamposComDistancia() {
        let place = Place(id: "j05", name: "Fuunji", cityId: "tokyo1", lat: 35.6875, lng: 139.6975)
        place.queueMinutes = 20
        place.price = 1_250
        let cells = MapCardFacts.cells(place, region: .jp, now: Date(), here: nil, walkMaxKm: 1.5)
        #expect(cells.map(\.label) == ["fila agora", "preço", "distância"])
        #expect(cells[0].value == "~20 min")
        let bare = Place(id: "x", name: "Sem nada", cityId: "tokyo1", lat: 35.6875, lng: 139.6975)
        let few = MapCardFacts.cells(bare, region: .jp, now: Date(), here: nil, walkMaxKm: 1.5)
        #expect(few.count == 3)
        #expect(few.contains { $0.label == "distância" })
        #expect(MapCardFacts.compact(3_100, locale: Locale(identifier: "pt_BR")) == "3,1 mil")
        #expect(MapCardFacts.spec(area: "Shinjuku", pin: (2, 9, "hoje"), list: "eat") == ["Shinjuku · agora", "pino 2 de 9 · hoje"])
    }

    @MainActor @Test func buscaPorNomeDoBoardOuVontade() {
        let nagi = Place(id: "j9", name: "Ramen Nagi", cityId: "tokyo1", lat: 35.69, lng: 139.70)
        let inima = Place(id: "p9", name: "Museu Inimá de Paula", cityId: "bh", lat: -19.92, lng: -43.94)
        #expect(MapView.boardNameHit("inimá", in: [nagi, inima])?.id == "p9")
        #expect(MapView.boardNameHit("Ramen Nagi", in: [nagi, inima])?.id == "j9")
        // "ramen" é vontade (prato): vai pra busca, não abre o Ramen Nagi.
        #expect(MapView.boardNameHit("ramen", in: [nagi, inima]) == nil)
        #expect(MapView.boardNameHit("o melhor lámen perto de mim agora", in: [nagi, inima]) == nil)
    }
}
