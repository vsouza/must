import CoreLocation
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Must

/// O corte (prompt 30, etapa 1): divisão board × fora, limite do arrasto, passo a passo, cutucão e cache do tratamento.
@MainActor
struct CorteTests {
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)

    private func input(board: [WantBoardPlace], anyDistance: Bool) -> WantSearchInput {
        WantSearchInput(intent: WantParser.parseLocal("café")!, region: .jp, center: shinjuku, cityGroup: "tokyo", online: false,
                        board: board, now: Date(), boardAnyDistance: anyDistance)
    }

    private func result(_ id: String, origin: WantResult.Origin, lat: Double, lng: Double, until: String? = nil) -> WantResult {
        WantResult(id: "\(origin.rawValue):\(id)", name: id, lat: lat, lng: lng, origin: origin, boardPlaceId: origin == .board ? id : nil,
                   until: until)
    }

    private func row(_ r: WantResult, minutes: Int, fits: Bool) -> QueroRow {
        let at = Date()
        let slot = fits ? DayFit.Slot(start: at, end: at.addingTimeInterval(1500), after: nil, before: nil, travelIn: 5, detour: 0) : nil
        return QueroRow(result: r, minutes: minutes, slot: slot, meta: "", otherDay: fits ? nil : "sáb · Ginza", areaId: nil)
    }

    // MARK: Board a qualquer distância

    @Test func boardEntraLongeSoComACrianca() {
        let far = WantBoardPlace(id: "far", name: "Café Longe", lat: 35.30, lng: 139.50, listId: "drink")
        let near = WantBoardPlace(id: "near", name: "Café Perto", lat: 35.6915, lng: 139.7010, listId: "drink")
        let category = WantCategory.match("café")
        let cut = WantSearch.boardResults(input(board: [far, near], anyDistance: false), category: category)
        #expect(cut.map(\.id) == ["board:near"])
        let all = WantSearch.boardResults(input(board: [far, near], anyDistance: true), category: category)
        #expect(Set(all.map(\.id)) == ["board:far", "board:near"])
    }

    @Test func boardDeOutraCidadeNuncaEntra() throws {
        let container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let tokyo = Place(id: "t1", name: "Café Tóquio", cityId: "tokyo1", lat: 35.69, lng: 139.70)
        let kyoto = Place(id: "k1", name: "Café Kyoto", cityId: "kyoto", lat: 35.01, lng: 135.76)
        context.insert(tokyo); context.insert(kyoto)
        let board = QueroEnv.board([tokyo, kyoto], cityGroup: AreaCatalog.cityGroup(forCityId: "tokyo1"), now: Date(), timeZone: Region.jp.timeZone)
        #expect(board.map(\.id) == ["t1"])
    }

    // MARK: Divisão e ordem

    @Test func divideBoardEForaEOrdenaDaHoje() {
        let board = [
            row(result("lento", origin: .board, lat: 35.50, lng: 139.60), minutes: 40, fits: true),
            row(result("naoDa", origin: .board, lat: 35.692, lng: 139.701), minutes: 3, fits: false),
            row(result("rapido", origin: .board, lat: 35.60, lng: 139.65), minutes: 15, fits: true),
        ]
        let outside = [
            row(result("g1", origin: .places, lat: 35.6915, lng: 139.7010), minutes: 2, fits: true),
            row(result("longe", origin: .places, lat: 35.75, lng: 139.80), minutes: 30, fits: true),
        ]
        let split = CorteSplit.split(board + outside, origin: shinjuku, region: .jp, walkMaxKm: 1.5)
        #expect(split.board.map(\.row.result.name) == ["rapido", "lento", "naoDa"])
        #expect(split.outside.map(\.row.result.name) == ["g1"])
        #expect(split.board.allSatisfy(\.isBoard) && split.outside.allSatisfy { !$0.isBoard })
        #expect(split.board.last?.action == .later("sáb"))
        #expect(split.outside.first?.action == .addToBoard)
        #expect(split.board.first?.action == .go)
    }

    @Test func distanciaGrande() {
        #expect(CorteSplit.distanceParts(850).value == "850" && CorteSplit.distanceParts(850).unit == "m")
        #expect(CorteSplit.distanceParts(2_100).unit == "km")
    }

    // MARK: Arrasto

    @Test func limiteDoArrastoAbreOuVolta() {
        let pull = CutPull()
        pull.drag(translation: 60)
        #expect(pull.phase == .pulling && pull.offset == 60)
        pull.release()
        #expect(pull.phase == .closed && pull.offset == 0)
        pull.drag(translation: 109)
        #expect(!pull.isOpen)
        pull.drag(translation: 140)
        #expect(pull.isOpen && pull.offset == CutPull.limit && pull.openedTicks == 1)
        pull.drag(translation: 20)
        #expect(pull.offset == CutPull.limit)
        pull.close()
        #expect(pull.phase == .closed)
        pull.drag(translation: -30)
        #expect(pull.offset == 0)
    }

    @Test func rotuloDaRegua() {
        #expect(CutPull.label(phase: .closed, offset: 0) == "↓ quero")
        #expect(CutPull.label(phase: .pulling, offset: 80) == "↓ mais um pouco")
        #expect(CutPull.label(phase: .open, offset: 110) == "↑ fechar")
        #expect(CutPull.label(phase: .closed, offset: 0, noun: "quero café") == "↓ quero café")
    }

    @Test func fendaCrescePuxando() {
        let rest = CorteLayout.heights(stage: .rest, pull: 0, rest: 400)
        #expect(rest.band == 400 && rest.slit == 0)
        let mid = CorteLayout.heights(stage: .rest, pull: 55, rest: 400)
        #expect(mid.band < 400 && mid.slit > 0)
        #expect(CorteLayout.heights(stage: .result, pull: 0, rest: 400).slit == 0)
    }

    // MARK: Cache do tratamento

    @Test func mesmaChaveNaoReprocessa() async {
        let dir = URL.temporaryDirectory.appending(path: "cut-test-\(UUID().uuidString)")
        let cache = CutImageCache(directory: dir)
        let key = CutTreatment.key(source: "x", tint: 0xD7000F)
        let first = await cache.image(key: key) { CutTreatment.render(photo: nil, tint: 0xD7000F) }
        let second = await cache.image(key: key) { CutTreatment.render(photo: nil, tint: 0xD7000F) }
        #expect(first != nil && second != nil)
        #expect(await cache.renders == 1)
        // Outro processo (cache novo na mesma pasta) lê do disco.
        let other = CutImageCache(directory: dir)
        let again = await other.image(key: key) { nil }
        #expect(again != nil)
        #expect(await other.renders == 0)
        // Outra cor = outra chave.
        #expect(CutTreatment.key(source: "x", tint: 0x007A33) != key)
    }

    @Test func tratamentoPintaDeCorEComTrama() throws {
        let image = try #require(CutTreatment.render(photo: nil, tint: 0xD7000F))
        #expect(image.size.width > 100)
    }
}
