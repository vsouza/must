import Foundation
import SwiftUI

// Contrato da RODADA-23: "amigos que foram" (por enquanto mock determinístico, com a etiqueta "exemplo").

struct FriendVisit: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var initials: String
    /// "mar 2025", "há 2 semanas".
    var when: String
    var note: String?
    /// Nota de 0 a 10 ("9 de 10"). Aditivo ao contrato.
    var rating: Int?
}

protocol FriendsProviding: Sendable {
    var isSample: Bool { get }
    func visits(placeId: String) -> [FriendVisit]
    /// Quantos amigos existem ao todo ("3 de 5 amigos"). Aditivo ao contrato.
    var totalFriends: Int { get }
}

extension FriendsProviding {
    var totalFriends: Int { 5 }
}

/// Mock (prompt 27 · §5): pool fixo de 5 pessoas, de 0 a 3 visitas por lugar, sempre as mesmas pro mesmo `placeId`
/// (FNV-1a do id, não o `Hasher` do Swift, que muda a cada execução). Etiqueta "exemplo · lista fixa" enquanto for mock.
struct MockFriendsSource: FriendsProviding {
    init() {}
    var isSample: Bool { true }
    var totalFriends: Int { Self.people.count }

    struct Person: Sendable, Hashable {
        var name: String
        var initials: String
    }

    static let people = [
        Person(name: "Ana Beatriz", initials: "AB"), Person(name: "Pedro", initials: "PS"), Person(name: "Carol", initials: "CM"),
        Person(name: "Rafa", initials: "RF"), Person(name: "Lu", initials: "LU"),
    ]
    static let whens = ["out 2025", "mar 2024", "abr 2023", "jan 2026", "set 2024", "dez 2025", "jul 2023"]
    static let notes = [
        "Vá cedo, enche rápido.", "Vale pelo clima, não pela pressa.", "Levei meia hora de fila e valeu.", "Peça o que o pessoal da mesa ao lado pediu.",
        "Dá pra encaixar entre dois lugares do bairro.", "Reserve pelo site, no balcão não tem vaga.", "Melhor no fim da tarde.", "Fica lotado depois das 20h.",
    ]

    /// Hash estável (FNV-1a 64 bits) do id.
    static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    func visits(placeId: String) -> [FriendVisit] {
        let h = Self.hash(placeId)
        let count = Int(h % 4)
        let first = Int((h >> 8) % UInt64(Self.people.count))
        // Passo 2 com 5 pessoas: nunca repete a mesma pessoa no lugar.
        return (0..<count).map { i in
            let person = Self.people[(first + i * 2) % Self.people.count]
            let bits = h >> UInt64(16 + i * 8)
            return FriendVisit(id: "\(placeId)-\(i)", name: person.name, initials: person.initials,
                               when: Self.whens[Int(bits % UInt64(Self.whens.count))],
                               note: Self.notes[Int((bits >> 4) % UInt64(Self.notes.count))],
                               rating: 6 + Int((bits >> 2) % 5))
        }
    }
}

private struct FriendsKey: EnvironmentKey {
    static var defaultValue: any FriendsProviding { MockFriendsSource() }
}

extension EnvironmentValues {
    var friends: any FriendsProviding {
        get { self[FriendsKey.self] }
        set { self[FriendsKey.self] = newValue }
    }
}
