import Foundation
import SwiftData

// Grupo da viagem (prompt 32): quem viaja junto, votações "A ou B?" e a divisão dos gastos. Tudo no container da viagem,
// aditivo (campos com valor padrão = migração leve). Sem servidor: o grupo só existe no aparelho; o que sai vai pelo
// WhatsApp/compartilhar do iOS.

/// Um companheiro de viagem. Só o nome (os de Presentes entram como sugestão).
@Model
final class Companion {
    @Attribute(.unique) var id: String = UUID().uuidString
    var name: String = ""
    var order: Int = 0
    var createdAt: Date = Date.now

    init(name: String, order: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.order = order
        self.createdAt = .now
    }
}

/// "A ou B?": dois Musts, o voto de cada pessoa e o vencedor.
@Model
final class PlacePoll {
    @Attribute(.unique) var id: String = UUID().uuidString
    var placeAId: String = ""
    var placeBId: String = ""
    var createdAt: Date = Date.now
    /// JSON `{"Ana":"A","Bia":"B"}`.
    var votesData: Data?
    /// Vencedor marcado à mão ("A"/"B"); vazio = o que tem mais votos.
    var pickedRaw: String = ""
    /// O vencedor já foi pro dia.
    var addedToDay: Bool = false

    init(a: String, b: String) {
        self.id = UUID().uuidString
        self.placeAId = a
        self.placeBId = b
        self.createdAt = .now
    }

    var votes: [String: PollSide] {
        get { votesData.flatMap { try? JSONDecoder().decode([String: PollSide].self, from: $0) } ?? [:] }
        set { votesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var picked: PollSide? {
        get { PollSide(rawValue: pickedRaw) }
        set { pickedRaw = newValue?.rawValue ?? "" }
    }

    /// Tocar no mesmo voto desfaz.
    func vote(_ person: String, _ side: PollSide) {
        var v = votes
        if v[person] == side { v[person] = nil } else { v[person] = side }
        votes = v
    }

    var winner: PollSide? { PollLogic.winner(votes: votes, picked: picked) }

    func placeId(_ side: PollSide) -> String { side == .a ? placeAId : placeBId }
}

enum PollSide: String, Codable, Sendable, CaseIterable {
    case a = "A", b = "B"
    var other: PollSide { self == .a ? .b : .a }
}

enum PollLogic {
    static func tally(_ votes: [String: PollSide]) -> (a: Int, b: Int) {
        (votes.values.filter { $0 == .a }.count, votes.values.filter { $0 == .b }.count)
    }

    /// Escolha à mão manda; senão quem tem mais votos; empate = ninguém ainda.
    static func winner(votes: [String: PollSide], picked: PollSide?) -> PollSide? {
        if let picked { return picked }
        let t = tally(votes)
        if t.a == t.b { return nil }
        return t.a > t.b ? .a : .b
    }

    /// Texto pronto pro WhatsApp.
    static func message(a: String, b: String, areaA: String?, areaB: String?, minutesA: Int?, minutesB: Int?) -> String {
        func line(_ tag: String, _ name: String, _ area: String?, _ min: Int?) -> String {
            var extra = [area, min.map { "\($0) min" }].compactMap { $0 }.joined(separator: " · ")
            if !extra.isEmpty { extra = " (\(extra))" }
            return "\(tag) \(name)\(extra)"
        }
        return "A ou B?\n\(line("A", a, areaA, minutesA))\n\(line("B", b, areaB, minutesB))\nResponde A ou B."
    }
}
