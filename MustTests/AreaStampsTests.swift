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

    // MARK: Selo sem japonês (v8): sigla latina + nome, nunca kanji

    @Test func siglasDoJapaoSaoOsCodigosJRPedidos() {
        let byId = Dictionary(uniqueKeysWithValues: AreaCatalog.jp.map { ($0.id, $0) })
        let expected = ["shinjuku": "SJK", "shibuya": "SBY", "ueno": "UEN", "harajuku": "HJK", "akihabara": "AKB",
                        "ginza": "GNZ", "asakusa": "ASK"]
        for (id, code) in expected {
            #expect(byId[id]?.seal == code, "\(id)")
        }
        #expect(byId["shinjuku"]?.sealSub == "Shinjuku")
    }

    @Test func todoSeloETresLetrasLatinasUnicasPorCidade() {
        for areas in [AreaCatalog.jp.filter { $0.cityId == "tokyo" }, AreaCatalog.jp.filter { $0.cityId == "kyoto" }, AreaCatalog.bh] {
            let codes = areas.map(\.seal)
            #expect(Set(codes).count == codes.count, "sigla repetida: \(codes)")
            for (area, code) in zip(areas, codes) {
                #expect(code.count == 3, "\(area.id): \(code)")
                #expect(code.unicodeScalars.allSatisfy { ("A"..."Z").contains(Character($0)) }, "\(area.id): \(code)")
                #expect(!StationStamp.usesKanji(area.sealSub), "\(area.id): \(area.sealSub)")
            }
        }
    }

    @Test func stampCodeVemDoJSONComEssaChave() throws {
        let json = #"{"id":"trastevere","name":"Trastevere","cityId":"roma","centroid":{"lat":41.88,"lng":12.47},"#
            + #""stationIds":[],"aliases":[],"neighbors":[],"stampCode":"TRV","stampSub":"Trastevere"}"#
        let area = try JSONDecoder().decode(Area.self, from: Data(json.utf8))
        #expect(area.stampCode == "TRV")
        #expect(area.seal == "TRV")
        #expect(area.sealSub == "Trastevere")
    }

    @Test func semSiglaNaTabelaOSeloDerivaDoNome() {
        var a = area("ginza")
        a.name = "Ginza"
        #expect(a.seal == "GNZ")
        a.name = "Asakusa"
        #expect(a.seal == "ASK")
        a.stampText = "LOU"
        #expect(a.seal == "LOU")
        a.stampCode = "SAV"
        #expect(a.seal == "SAV")
    }

    @Test func seloNuncaMostraKanji() {
        #expect(StationStamp.usesKanji("新宿"))
        #expect(StationStamp.usesKanji("済"))
        #expect(!StationStamp.usesKanji("Kabukichō"))
        #expect(!StationStamp.usesKanji("Funcionários"))
        #expect(StationStamp.code("新宿", sub: "Shinjuku") == "SHN")
        #expect(StationStamp.code("済", sub: nil) == "MUST")
        #expect(StationStamp.code("SJK", sub: "Shinjuku") == "SJK")
    }
}

