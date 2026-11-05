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
}

protocol FriendsProviding: Sendable {
    var isSample: Bool { get }
    func visits(placeId: String) -> [FriendVisit]
}

/// Mock: 0–3 amigos por lugar, sempre os mesmos pro mesmo `placeId` (o agente A completa).
struct MockFriendsSource: FriendsProviding {
    init() {}
    var isSample: Bool { true }
    static let people = [("Ana", "AN"), ("Bruno", "BR"), ("Carol", "CA"), ("Dani", "DA"), ("Edu", "ED")]

    func visits(placeId: String) -> [FriendVisit] {
        let seed = placeId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        let count = seed % 4
        return (0..<count).map { i in
            let p = Self.people[(seed + i * 2) % Self.people.count]
            return FriendVisit(id: "\(placeId)-\(i)", name: p.0, initials: p.1, when: ["mar 2025", "out 2024", "jan 2026"][(seed + i) % 3])
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
