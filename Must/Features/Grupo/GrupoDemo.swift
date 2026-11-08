#if DEBUG
import Foundation
import SwiftData

/// Exemplo do Grupo pros prints (`-debugScreen grupo*`): duas pessoas, gastos divididos e uma votação com dois lugares do board.
@MainActor
enum GrupoDemo {
    static func ensure(context: ModelContext, region: Region) {
        PresenteDemo.ensure(context: context, region: region)
        guard ((try? context.fetch(FetchDescriptor<Companion>())) ?? []).isEmpty else { return }
        context.insert(Companion(name: "Ana", order: 0))
        context.insert(Companion(name: "Bia", order: 1))
        let k = Settlement.decimals(currency: region.currency) == 0 ? 1.0 : 1.0 / 40
        let now = AppClock.now
        func add(_ amount: Double, paidBy: String, split: String, category: ExpenseCategory) {
            let e = Expense(at: now, amount: (amount * k).rounded(), category: category)
            e.paidBy = paidBy
            e.splitWith = split
            context.insert(e)
        }
        add(6400, paidBy: "", split: Settlement.everyone, category: .food)
        add(4200, paidBy: "Ana", split: Settlement.everyone, category: .transit)
        add(1800, paidBy: "Bia", split: Settlement.join([Settlement.me, "Bia"]), category: .coffee)
        let places = ((try? context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.name)]))) ?? []).filter { !$0.isDone }
        if places.count >= 2, ((try? context.fetch(FetchDescriptor<PlacePoll>())) ?? []).isEmpty {
            let poll = PlacePoll(a: places[0].id, b: places[1].id)
            poll.vote(Settlement.me, .a)
            poll.vote("Ana", .a)
            poll.vote("Bia", .b)
            context.insert(poll)
        }
        try? context.save()
    }

    static func firstPollId(context: ModelContext) -> String? {
        (try? context.fetch(FetchDescriptor<PlacePoll>()))?.first?.id
    }

    static func firstPlaceId(context: ModelContext) -> String? {
        (try? context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.name)])))?.first?.id
    }
}
#endif
