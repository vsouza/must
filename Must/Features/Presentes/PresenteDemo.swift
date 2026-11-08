#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen presentes` e as outras telas de Presentes: põe, uma vez, a lista de exemplo do QA (Ana, Mãe, Pedro, Lucas).
/// Lojas com coordenada em Shinjuku (onde o GPS simulado dos prints está), pro "perto" aparecer.
@MainActor
enum PresenteDemo {
    static let kitKatId = "demo-gift-kitkat"

    static func ensure(context: ModelContext, region: Region) {
        guard !context.gifts().contains(where: { $0.id.hasPrefix("demo-gift-") }) else { return }
        let now = AppClock.now
        var order = 0
        func add(_ id: String, _ title: String, _ person: String, price: Double, qty: Int = 1, store: String = "", lat: Double? = nil,
                 lng: Double? = nil, placeId: String? = nil, source: GiftSource = .name, bought: Date? = nil, paid: Double? = nil,
                 chain: Bool = false, note: String = "") {
            let gift = Gift(id: "demo-gift-\(id)", title: title, person: person, quantity: qty, estimatedPrice: price, source: source,
                            placeId: region == .jp ? placeId : nil, storeName: store, note: note, order: order)
            order += 1
            gift.storeLat = lat
            gift.storeLng = lng
            gift.chain = chain
            gift.boughtAt = bought
            gift.paidPrice = paid
            if source == .video { gift.sourceLabel = "@tokyosnacks"; gift.videoClip = "0:12–0:19"; gift.sourceURL = "https://www.instagram.com/reel/demo/" }
            context.insert(gift)
        }
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)
        add("faca", "Faca santoku", "Mãe", price: 14_000, store: "Kama-asa Kappabashi", placeId: "j94")
        add("furoshiki", "Furoshiki de algodão", "Mãe", price: 2_200, store: "Tokyu Hands Shinjuku", lat: 35.6906, lng: 139.7020)
        add("kitkat", "Kit Kat de matcha", "Ana", price: 1_200, qty: 3, store: "Don Quijote Shinjuku", lat: 35.6954, lng: 139.7006,
            source: .video, chain: false, note: "O de matcha de Uji, caixa vermelha. Não o de morango.")
        add("caneta", "Caneta Pilot Custom 74", "Ana", price: 2_950, store: "Ginza Itoya", placeId: "j62", bought: twoDaysAgo, paid: 2_950)
        add("disco", "Disco de city pop", "Pedro", price: 2_800, store: "Disk Union Shinjuku", lat: 35.6905, lng: 139.7035, source: .link)
        add("pelucia", "Pelúcia Pikachu", "Lucas", price: 3_500, store: "Pokémon Center Ikebukuro", lat: 35.7295, lng: 139.7186)
        try? context.save()
    }
}
#endif
