import Foundation
import Testing
@testable import Must

@Suite("Grupo: acertar contas e votação")
struct GroupTests {
    @Test("Sem divisão nada entra na conta")
    func noSplit() {
        let r = Settlement.settle([.init(amount: 100)], people: ["Ana"])
        #expect(r.transfers.isEmpty)
        #expect(r.balances.isEmpty)
        #expect(r.sharedTotal == 0)
    }

    @Test("Eu pago, divido com todos: Ana me deve metade")
    func twoPeople() {
        let r = Settlement.settle([.init(amount: 6400, splitWith: Settlement.everyone)], people: ["Ana"], decimals: 0)
        #expect(r.transfers == [.init(from: "Ana", to: Settlement.me, amount: 3200)])
        #expect(r.balances["Ana"] == -3200)
        #expect(r.balances[Settlement.me] == 3200)
    }

    @Test("Só eu na viagem: ninguém deve nada")
    func onePerson() {
        let r = Settlement.settle([.init(amount: 50, splitWith: Settlement.everyone)], people: [])
        #expect(r.transfers.isEmpty)
        #expect(r.sharedTotal == 50)
    }

    @Test("Arredondamento: R$ 10,00 por 3 fecha em centavos")
    func rounding() {
        let r = Settlement.settle([.init(amount: 10, splitWith: Settlement.everyone)], people: ["Ana", "Bia"])
        let total = r.transfers.reduce(0) { $0 + $1.amount }
        #expect(abs(total - 6.67) < 0.001 || abs(total - 6.66) < 0.001)
        #expect(abs(r.balances.values.reduce(0, +)) < 0.0001)
    }

    @Test("Pagamentos cruzados se compensam")
    func crossed() {
        let all = Settlement.everyone
        let r = Settlement.settle([
            .init(amount: 3000, paidBy: "", splitWith: all),
            .init(amount: 3000, paidBy: "Ana", splitWith: all),
        ], people: ["Ana"], decimals: 0)
        #expect(r.transfers.isEmpty)
    }

    @Test("Três pessoas: o mínimo de transferências")
    func minimumTransfers() {
        let all = Settlement.everyone
        let r = Settlement.settle([
            .init(amount: 9000, paidBy: "Ana", splitWith: all),
        ], people: ["Ana", "Bia"], decimals: 0)
        #expect(r.transfers.count == 2)
        #expect(Set(r.transfers.map(\.to)) == ["Ana"])
        #expect(r.transfers.allSatisfy { $0.amount == 3000 })
    }

    @Test("Dividido só com alguns")
    func chosen() {
        let r = Settlement.settle([
            .init(amount: 4000, paidBy: "Bia", splitWith: Settlement.join([Settlement.me, "Bia"])),
        ], people: ["Ana", "Bia"], decimals: 0)
        #expect(r.transfers == [.init(from: Settlement.me, to: "Bia", amount: 2000)])
        #expect(r.balances["Ana"] == nil)
    }

    @Test("Pessoa apagada ainda entra na conta")
    func removedPerson() {
        let r = Settlement.settle([.init(amount: 200, paidBy: "Caio", splitWith: Settlement.join([Settlement.me, "Caio"]))], people: [])
        #expect(r.transfers == [.init(from: Settlement.me, to: "Caio", amount: 100)])
    }

    @Test("Casas decimais por moeda")
    func decimals() {
        #expect(Settlement.decimals(currency: "JPY") == 0)
        #expect(Settlement.decimals(currency: "BRL") == 2)
    }

    @Test("Votação: maioria, empate e escolha à mão")
    func poll() {
        #expect(PollLogic.winner(votes: [:], picked: nil) == nil)
        #expect(PollLogic.winner(votes: ["Ana": .a, "Bia": .b], picked: nil) == nil)
        #expect(PollLogic.winner(votes: ["Ana": .a, "Bia": .b, "Caio": .b], picked: nil) == .b)
        #expect(PollLogic.winner(votes: ["Ana": .a], picked: .b) == .b)
        let poll = PlacePoll(a: "x", b: "y")
        poll.vote("Ana", .a)
        #expect(poll.winner == .a)
        poll.vote("Ana", .a)
        #expect(poll.winner == nil)
    }

    @Test("Texto pronto da votação")
    func message() {
        let m = PollLogic.message(a: "Ichiran", b: "Afuri", areaA: "Shibuya", areaB: nil, minutesA: 8, minutesB: nil)
        #expect(m == "A ou B?\nA Ichiran (Shibuya · 8 min)\nB Afuri\nResponde A ou B.")
    }
}
