import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// O corte nas outras telas (prompt 30, etapa 2): origem do quero no Lugar, filtro pela lista, régua e barra de abas.
@MainActor
struct CorteEtapa2Tests {
    private func env(board: [WantBoardPlace] = []) -> QueroEnv {
        QueroEnv(region: .jp, now: Date(), plan: nil, center: CLLocationCoordinate2D(latitude: 35.69, longitude: 139.70),
                 origin: CLLocationCoordinate2D(latitude: 35.69, longitude: 139.70), areaName: "Shinjuku", cityGroup: "tokyo",
                 cityId: "tokyo1", online: true, board: board, useModel: false)
    }

    @Test func queroNoLugarSaiDoLugarENaoDoGPS() throws {
        let container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let here = Place(id: "here", name: "Udatsu", cityId: "tokyo1", lat: 35.65, lng: 139.70)
        let other = Place(id: "other", name: "Café Tóquio", cityId: "tokyo1", lat: 35.66, lng: 139.71)
        let kyoto = Place(id: "k1", name: "Café Kyoto", cityId: "kyoto", lat: 35.01, lng: 135.76)
        [here, other, kyoto].forEach { context.insert($0) }
        let e = env().atPlace(here, places: [here, other, kyoto])
        #expect(e.origin.latitude == 35.65 && e.center.latitude == 35.65)
        #expect(e.board.map(\.id) == ["other"]) // sem o próprio lugar e sem outra cidade
        #expect(e.boardAnyDistance)
    }

    @Test func queroNaListaSoLevaOBoardDaLista() {
        let board = [WantBoardPlace(id: "a", name: "A", lat: 35.7, lng: 139.7, listId: "eat"),
                     WantBoardPlace(id: "b", name: "B", lat: 35.7, lng: 139.7, listId: "drink")]
        #expect(env(board: board).scoped(toList: "drink").board.map(\.id) == ["b"])
    }

    @Test func pedidoDaListaUsaOVerboDela() {
        #expect(CorteListWish.wish(listId: "eat", name: "eat").verb == .comer)
        #expect(CorteListWish.wish(listId: "drink", name: "drink").verb == .beber)
        #expect(CorteListWish.wish(listId: "minha", name: "Padarias").text == "padarias")
    }

    @Test func preencheOPedidoSemEnviar() {
        let prefs = CortePrefs(defaults: UserDefaults(suiteName: "corte2-\(UUID())")!)
        let state = CorteState(prefs: prefs, makeModel: { QueroModel(provider: nil) })
        state.open()
        state.preset(CorteListWish.wish(listId: "eat", name: "eat"))
        #expect(state.quero.text == "comer" && state.quero.verbOverride == .comer)
        #expect(state.stage == .asking && state.quero.phase == .idle)
    }

    @Test func reguaDoLugarSoMudaNoMeioDoGesto() {
        let text = "↓ perto daqui, quero…"
        #expect(CutPull.staticLabel(text, phase: .closed, offset: 0) == text)
        #expect(CutPull.staticLabel(text, phase: .pulling, offset: 60) == "↓ mais um pouco")
        #expect(CutPull.staticLabel(text, phase: .open, offset: 110) == "↑ fechar")
    }

    @Test func barraDeAbasSomeEnquantoQualquerQueroEstaAberto() {
        let router = AppRouter()
        #expect(!router.queroOpen)
        router.setQuero("capa", open: true)
        router.setQuero("lista", open: true)
        router.setQuero("capa", open: false)
        #expect(router.queroOpen && router.hidesNavBar)
        router.setQuero("lista", open: false)
        #expect(!router.hidesNavBar)
    }
}
