import Foundation
import Testing
@testable import Must

/// Coleção de selos de bairro na Viagem (prompt 18 · D.18): só bairro com must feito ganha selo.
@MainActor
struct AreaStampsTests {
    private func area(_ id: String, city: String = "tokyo") -> Area {
        Area(id: id, name: id.capitalized, nameLocal: nil, cityId: city,
             centroid: .init(lat: 35.0, lng: 139.0), polygon: nil, stationIds: [], aliases: [], neighbors: [],
             stampText: nil, stampSub: nil, heroPhotoRef: nil)
    }

    private func place(_ id: String, area: String?, done: Bool, city: String = "tokyo1") -> AreaPlace {
        AreaPlace(id: id, name: id, areaName: area, cityId: city, lat: 35.0, lng: 139.0, kind: .eat,
                  isDone: done, verified: true, order: 0, hasReservation: false)
    }

    @Test func semMustFeitoNaoTemSelo() {
        let areas = [area("shinjuku"), area("ginza")]
        let places = [place("a", area: "Shinjuku", done: false), place("b", area: "Ginza", done: false)]
        #expect(AreaStamps.earned(areas: areas, places: places).isEmpty)
    }

    @Test func bairroComUmMustFeitoGanhaSeloNaOrdemDaTabela() {
        let areas = [area("shinjuku"), area("ginza"), area("ueno")]
        let places = [
            place("a", area: "Ueno", done: true),
            place("b", area: "Shinjuku", done: false),
            place("c", area: "Shinjuku", done: true),
        ]
        #expect(AreaStamps.earned(areas: areas, places: places).map(\.id) == ["shinjuku", "ueno"])
    }

    @Test func lugarSemBairroNaoGeraSelo() {
        let areas = [area("ginza")]
        // Sem nome e sem coordenada (0,0): nem o centroide próximo liga o lugar a um bairro.
        let places = [AreaPlace(id: "a", name: "a", areaName: nil, cityId: "tokyo1", lat: 0, lng: 0, kind: .eat,
                                isDone: true, verified: true, order: 0, hasReservation: false)]
        #expect(AreaStamps.earned(areas: areas, places: places).isEmpty)
    }

    @Test func bairroDeOutraCidadeNaoContaComoFeito() {
        let areas = [area("bh-savassi", city: "bh")]
        let places = [place("a", area: "Savassi", done: true, city: "tokyo1")]
        #expect(AreaStamps.earned(areas: areas, places: places).isEmpty)
    }

    @Test func nomeComAcentoECaixaDiferentesContamOMesmoBairro() {
        let areas = [area("savassi", city: "bh")]
        let places = [place("a", area: "SAVASSI", done: true, city: "bh")]
        #expect(AreaStamps.earned(areas: areas, places: places).map(\.id) == ["savassi"])
    }
}
