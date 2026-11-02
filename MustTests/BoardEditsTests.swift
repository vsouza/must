import Foundation
import SwiftData
import Testing
@testable import Must

/// Board (fatia 1): mover, ordenar, ação em lote, apagar, editar lista e a busca da tela.
/// Sobre o seed de BH em memória. Nenhum teste fala com a rede.
@MainActor
struct BoardEditsTests {
    private final class Token {}

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: .bh, bundle: Bundle(for: Token.self))
        return c
    }

    private func list(_ id: String, _ ctx: ModelContext) throws -> MustList {
        try #require(try ctx.fetch(FetchDescriptor<MustList>()).first { $0.id == id })
    }

    private func allLists(_ ctx: ModelContext) throws -> [MustList] {
        try ctx.fetch(FetchDescriptor<MustList>(sortBy: [SortDescriptor(\.order)]))
    }

    /// Lugares de uma lista na ordem do board.
    private func places(in id: String, _ ctx: ModelContext) throws -> [Place] {
        try ctx.fetch(FetchDescriptor<Place>()).filter { $0.list?.id == id }.sorted(by: BoardEdits.manualOrder)
    }

    // MARK: Mover

    @Test func moveBetweenListsKeepsDataAndOrder() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try places(in: "eat", ctx)
        let drink = try list("drink", ctx)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let mover = eat[1]
        mover.sub = "Mineiro"
        mover.area = "Savassi"
        mover.notes = "pedir o combo"
        mover.reservation = Reservation(at: at, party: 2, note: "pede janela")
        mover.done = DoneMark(at: at, spent: 40)
        mover.saveForEnd = true
        mover.price = 60
        try ctx.save()

        let staying = eat.filter { $0.id != mover.id }.map(\.id)
        let drinkBefore = try places(in: "drink", ctx).map(\.id)

        try BoardEdits.move([mover], to: drink, context: ctx)

        #expect(mover.list?.id == "drink")
        #expect(mover.sub == nil, "o sub é da lista de origem")
        #expect(mover.area == "Savassi")
        #expect(mover.notes == "pedir o combo")
        #expect(mover.reservation?.party == 2)
        #expect(mover.reservation?.note == "pede janela")
        #expect(mover.done?.spent == 40)
        #expect(mover.saveForEnd)
        #expect(mover.price == 60)
        // Quem já estava no drink segue na frente; o que chegou vai pro fim.
        let drinkAfter = try places(in: "drink", ctx).map(\.id)
        #expect(drinkAfter == drinkBefore + [mover.id])
        // Quem ficou no eat mantém a ordem.
        let eatAfter = try places(in: "eat", ctx).map(\.id)
        #expect(eatAfter == staying)
    }

    @Test func reorderInsideListPersists() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try places(in: "eat", ctx)
        let first = eat[0].id
        let second = eat[1].id

        // Arrasta o primeiro pra depois do segundo (destino 2 = antes do terceiro).
        try BoardEdits.reorder(eat, from: IndexSet(integer: 0), to: 2, context: ctx)

        let after = try places(in: "eat", ctx).map(\.id)
        #expect(after[0] == second)
        #expect(after[1] == first)
        #expect(after.count == eat.count)
        // Relê a ordem gravada (como ao reabrir a tela).
        let stored = try ctx.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.order)])).filter { $0.list?.id == "eat" }
        #expect(stored.prefix(2).map(\.id) == [second, first])
    }

    // MARK: Lote

    @Test func batchSaveForEndAppliesToEverySelected() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try places(in: "eat", ctx)
        for place in eat { place.saveForEnd = false }
        try ctx.save()

        let picked = Array(eat.prefix(3))
        try BoardEdits.setSaveForEnd(picked, on: true, context: ctx)

        #expect(picked.allSatisfy { $0.saveForEnd })
        #expect(eat.dropFirst(3).allSatisfy { !$0.saveForEnd })
    }

    @Test func batchCityAppliesToEverySelected() throws {
        let c = try container()
        let ctx = c.mainContext
        let picked = Array(try places(in: "drink", ctx).prefix(2))
        try BoardEdits.setCity(picked, cityId: "bh2", context: ctx)
        #expect(picked.allSatisfy { $0.cityId == "bh2" })
    }

    @Test func queueResolveMarksOnlySelected() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try places(in: "eat", ctx)
        try BoardEdits.queueResolve(Array(eat.prefix(2)), context: ctx)
        #expect(eat.prefix(2).allSatisfy { $0.resolveQueued })
        #expect(!eat.dropFirst(2).contains { $0.resolveQueued })
    }

    @Test func batchDeleteRemovesOnlySelected() throws {
        let c = try container()
        let ctx = c.mainContext
        let all = try ctx.fetch(FetchDescriptor<Place>())
        let picked = Array(all.prefix(2))
        let pickedIds = Set(picked.map(\.id))

        try BoardEdits.delete(picked, context: ctx)

        let left = try ctx.fetch(FetchDescriptor<Place>())
        #expect(left.count == all.count - 2)
        #expect(left.allSatisfy { !pickedIds.contains($0.id) })
    }

    // MARK: Listas

    @Test func deleteListMovesItemsToChosenList() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try list("eat", ctx)
        let drink = try list("drink", ctx)
        let movingIds = try places(in: "eat", ctx).map(\.id)
        let total = try ctx.fetchCount(FetchDescriptor<Place>())

        try BoardEdits.deleteList(eat, moveTo: drink, lists: try allLists(ctx), context: ctx)

        let lists = try allLists(ctx)
        #expect(!lists.contains { $0.id == "eat" })
        let totalAfter = try ctx.fetchCount(FetchDescriptor<Place>())
        #expect(totalAfter == total, "nenhum lugar se perde")
        let inDrink = try places(in: "drink", ctx).map(\.id)
        #expect(movingIds.allSatisfy { inDrink.contains($0) })
        #expect(lists.map(\.order) == Array(0..<lists.count), "ordem das listas sem buraco")
    }

    @Test func deleteListWithItemsNeedsTarget() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try list("eat", ctx)
        let before = try ctx.fetchCount(FetchDescriptor<Place>())

        #expect(throws: BoardEdits.EditError.needsTarget) {
            try BoardEdits.deleteList(eat, moveTo: nil, lists: try allLists(ctx), context: ctx)
        }
        let listsAfter = try allLists(ctx)
        #expect(listsAfter.contains { $0.id == "eat" })
        let countAfter = try ctx.fetchCount(FetchDescriptor<Place>())
        #expect(countAfter == before)
    }

    @Test func reorderListsPersistsThroughSeedMerge() throws {
        let c = try container()
        let ctx = c.mainContext
        let shop = try list("shop", ctx)
        try BoardEdits.moveList(shop, by: -100, in: try allLists(ctx), context: ctx)
        let firstBefore = try allLists(ctx).first?.id
        #expect(firstBefore == "shop")

        // Cada abertura do app roda o merge do seed: ele não pode desfazer a ordem que o usuário pôs.
        try RegionStore.mergeSeed(ctx, region: .bh, bundle: Bundle(for: Token.self))
        let firstAfter = try allLists(ctx).first?.id
        #expect(firstAfter == "shop")
    }

    @Test func saveListClearsSubsThatWereRemoved() throws {
        let c = try container()
        let ctx = c.mainContext
        let eat = try list("eat", ctx)
        let first = try places(in: "eat", ctx)[0]
        first.sub = "Mercado"
        try ctx.save()

        try BoardEdits.saveList(eat, name: "comer", kanji: "食", icon: eat.icon, color: eat.color, photo: nil,
                                changePhoto: false, subs: ["Mineiro", "Contemporâneo"], context: ctx)

        #expect(eat.name == "comer")
        #expect(eat.kanji == "食")
        #expect(eat.id == "eat", "o id não muda")
        #expect(eat.subs == ["Mineiro", "Contemporâneo"])
        #expect(first.sub == nil, "sub tirada da lista deixa o lugar sem sub")
    }

    // MARK: Export

    @Test func editsRoundTripThroughExport() throws {
        let c = try container()
        let ctx = c.mainContext
        let codec = BoardCodec(context: ctx, region: .bh)
        let eat = try list("eat", ctx)
        let drink = try list("drink", ctx)
        try BoardEdits.move([try places(in: "eat", ctx)[0]], to: drink, context: ctx)
        try BoardEdits.reorder(try places(in: "eat", ctx), from: IndexSet(integer: 0), to: 3, context: ctx)
        try BoardEdits.moveList(eat, by: 2, in: try allLists(ctx), context: ctx)
        try BoardEdits.setSaveForEnd(Array(try places(in: "drink", ctx).prefix(1)), on: true, context: ctx)

        let exported = try codec.export()
        let fresh = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let other = BoardCodec(context: fresh.mainContext, region: .bh)
        try other.import(board: BoardCodec.decode(BoardCodec.encode(exported)))

        let reexported = try other.export()
        #expect(reexported == exported)
        let placeCount = try other.context.fetchCount(FetchDescriptor<Place>())
        #expect(placeCount == exported.places.count)
    }

    // MARK: Busca e grupos (BoardQuery)

    @Test func searchFindsSourceAndIgnoresAccentAndCase() throws {
        let c = try container()
        let ctx = c.mainContext
        let place = try places(in: "eat", ctx)[0]
        place.source = Source(kind: .instagram, url: "https://www.instagram.com/reel/abc", savedAt: "2026-10-31", author: "@mesa")
        place.notes = "pão de queijo cedinho"
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Place>())

        let reels = all.filter { BoardQuery(text: "Reel").accepts($0) }
        #expect(reels.contains { $0.id == place.id })
        #expect(reels.allSatisfy { $0.source?.kind == .instagram })
        #expect(BoardQuery(text: "PAO DE QUEIJO").accepts(place))
        #expect(!BoardQuery(text: "inexistente").accepts(place))
    }

    @Test func filtersCountsAndDropsEmptyGroupsWhileFiltering() throws {
        let c = try container()
        let ctx = c.mainContext
        let lists = try allLists(ctx)
        let all = try ctx.fetch(FetchDescriptor<Place>())
        let trip = ctx.tripInfo()

        // Seed de BH não tem horário: o chip conta o board inteiro.
        #expect(BoardQuery.count(.noHours, in: all) == all.count)

        var filtered = BoardQuery()
        filtered.filter = .saveForEnd
        let groups = filtered.groups(places: all, lists: lists, trip: trip, region: .bh)
        #expect(groups.allSatisfy { !$0.places.isEmpty })
        #expect(groups.flatMap(\.places).count == BoardQuery.count(.saveForEnd, in: all))
    }

    @Test func cityGroupingKeepsEveryPlace() throws {
        let c = try container()
        let ctx = c.mainContext
        let all = try ctx.fetch(FetchDescriptor<Place>())
        var query = BoardQuery()
        query.grouping = .city
        let groups = query.groups(places: all, lists: try allLists(ctx), trip: ctx.tripInfo(), region: .bh)
        #expect(groups.count == 1, "BH é uma cidade só")
        #expect(groups.first?.places.count == all.count)
        #expect(groups.first?.list == nil, "agrupado por cidade não recebe arrasto")
    }
}
