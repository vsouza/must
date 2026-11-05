import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Bairros (prompt 18 · C.13): tabelas curadas, ligação lugar → bairro, índice e o card do dia.
@MainActor
struct AreaTests {
    private final class Token {}

    // MARK: Tabelas

    @Test func tabelasDecodificamComTodosOsBairrosPedidos() {
        let jp = AreaCatalog.jp
        let bh = AreaCatalog.bh
        #expect(jp.count == 24)
        #expect(bh.count == 8)
        #expect(Set(jp.map(\.id)).count == jp.count)
        #expect(Set(bh.map(\.id)).count == bh.count)
        let names = Set((jp + bh).map(\.name))
        let required = ["Shinjuku", "Shibuya", "Harajuku", "Nakano", "Shin-Okubo", "Naka-Meguro", "Ebisu", "Asakusa", "Ueno",
                        "Ginza", "Tsukiji", "Yanaka", "Shimokitazawa", "Kichijoji", "Akihabara", "Roppongi", "Daikanyama",
                        "Koenji", "Gion", "Higashiyama", "Arashiyama", "Fushimi", "Kawaramachi", "Kyoto Station",
                        "Savassi", "Lourdes", "Funcionários", "Centro", "Santa Tereza", "Pampulha", "Santo Agostinho",
                        "Mangabeiras"]
        for name in required { #expect(names.contains(name), "falta \(name)") }
    }

    /// v8 (selos sem japonês): o selo é a sigla latina; o kanji fica só no `nameLocal` (mostrar a alguém).
    @Test func japaoTemKanjiEBHTemSiglaEAnoDaCidade() {
        for area in AreaCatalog.jp {
            let kanji = try? #require(area.nameLocal)
            #expect(kanji.map { !$0.unicodeScalars.allSatisfy(\.isASCII) } == true, "\(area.name) sem kanji")
            #expect(area.stampCode?.count == 3)
            #expect(area.seal == area.stampCode)
            #expect(area.stampSub == area.name)
        }
        for area in AreaCatalog.bh {
            #expect(area.nameLocal == nil)
            #expect(area.stampCode?.count == 3)
            #expect(area.stampSub == "BH · 1897")
            #expect(area.seal == area.stampCode)
        }
    }

    /// Todo vizinho aponta pra uma área que existe na mesma cidade.
    @Test func vizinhosApontamParaAreaExistente() {
        for areas in [AreaCatalog.jp, AreaCatalog.bh] {
            let ids = Set(areas.map(\.id))
            for area in areas {
                for neighbor in area.neighbors {
                    #expect(ids.contains(neighbor.areaId), "\(area.id) → \(neighbor.areaId) não existe")
                }
            }
        }
    }

    /// Ida e volta têm o mesmo sentido: se A → B leva m minutos, B → A leva quase os mesmos.
    @Test func vizinhosSaoSimetricosComTempoParecido() {
        let all = AreaCatalog.jp + AreaCatalog.bh
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for area in all {
            for neighbor in area.neighbors {
                let back = byId[neighbor.areaId]?.neighbors.first { $0.areaId == area.id }
                #expect(back != nil, "\(neighbor.areaId) não aponta de volta pra \(area.id)")
                if let back {
                    let tolerance = max(3, Double(neighbor.minutes) * 0.4)
                    #expect(abs(Double(back.minutes - neighbor.minutes)) <= tolerance,
                            "\(area.id) ↔ \(neighbor.areaId): \(neighbor.minutes) vs \(back.minutes) min")
                }
            }
        }
    }

    @Test func corDaLinhaVemDoHex() {
        let line = LineRef(code: "JY", name: "JR Yamanote", color: "#80C241")
        #expect(line.rgb == 0x80C241)
        #expect(LineRef(code: "X", name: "", color: "ruim").rgb == 0)
    }

    // MARK: Ligação lugar → bairro

    @Test func nomeDoBoardLigaAoBairroEAliases() {
        let assigner = AreaAssigner(areas: AreaCatalog.jp)
        #expect(assigner.areaId(name: "Shibuya Stream", cityId: "tokyo1", lat: 0, lng: 0) == "shibuya")
        #expect(assigner.areaId(name: "Azabudai Hills", cityId: "tokyo1", lat: 0, lng: 0) == "roppongi")
        #expect(assigner.areaId(name: "Nakameguro", cityId: "tokyo2", lat: 0, lng: 0) == "naka-meguro")
        #expect(assigner.areaId(name: "Shinjuku", cityId: "tokyo2", lat: 0, lng: 0) == "shinjuku")
        #expect(assigner.areaId(name: "Kyoto", cityId: "kyoto", lat: 0, lng: 0) == "kyoto-station")
    }

    @Test func semNomeOuNomeDesconhecidoUsaOCentroideAte1Km2() {
        let assigner = AreaAssigner(areas: AreaCatalog.bh)
        // ~300 m de Savassi, nome que não está na tabela.
        #expect(assigner.areaId(name: "Rua Inventada", cityId: "bh", lat: -19.9400, lng: -43.9345) == "savassi")
        // Sem nome e a ~3 km: outros.
        #expect(assigner.areaId(name: nil, cityId: "bh", lat: -19.9000, lng: -43.9900) == nil)
        // Sem coordenada e sem nome: outros.
        #expect(assigner.areaId(name: nil, cityId: "bh", lat: 0, lng: 0) == nil)
    }

    @Test func centroideNaoCruzaCidades() {
        let assigner = AreaAssigner(areas: AreaCatalog.jp)
        // Perto de Gion (Quioto), mas o lugar é de Tóquio: não vira bairro de Quioto.
        #expect(assigner.areaId(name: nil, cityId: "tokyo1", lat: 35.0037, lng: 135.7756) == nil)
    }

    // MARK: Índice

    private func place(_ id: String, area: String?, kind: MustColor?, open: Bool = false, order: Int = 0,
                       cityId: String = "bh", lat: Double = 0, lng: Double = 0, verified: Bool = false) -> AreaPlace {
        AreaPlace(id: id, name: id, areaName: area, cityId: cityId, lat: lat, lng: lng, kind: kind, isDone: false,
                  verified: verified, order: order, hasReservation: false)
    }

    @Test func contagemDominanteEAbertosPorBairro() {
        let places = [
            place("a1", area: "Savassi", kind: .eat, order: 1),
            place("a2", area: "Savassi", kind: .eat, order: 2),
            place("a3", area: "Savassi", kind: .drink, order: 3),
            place("l1", area: "Lourdes", kind: .art, order: 4),
            place("o1", area: nil, kind: .eat, order: 5),
        ]
        let index = AreaIndex.build(areas: AreaCatalog.bh, places: places, openIds: ["a1", "a3"])
        let savassi = try? #require(index.entry("savassi"))
        #expect(savassi?.count == 3)
        #expect(savassi?.openCount == 2)
        #expect(savassi?.dominant == .eat)
        #expect(index.entry("lourdes")?.openCount == 0)
        #expect(index.outros == ["o1"])
        #expect(index.areaId(forPlace: "l1") == "lourdes")
    }

    @Test func hojePraOndeEscolheOsTresComMaisAbertos() {
        var places: [AreaPlace] = []
        // Lourdes: 3 abertos. Funcionários e Savassi: 2 abertos cada (empate: mais musts, depois nome). Centro: 1.
        for i in 0..<3 { places.append(place("lo\(i)", area: "Lourdes", kind: .eat, open: true, order: i)) }
        for i in 0..<2 { places.append(place("fu\(i)", area: "Funcionários", kind: .drink, open: true, order: 10 + i)) }
        for i in 0..<2 { places.append(place("sa\(i)", area: "Savassi", kind: .eat, open: true, order: 20 + i)) }
        places.append(place("ce0", area: "Centro", kind: .shop, open: true, order: 30))
        let index = AreaIndex.build(areas: AreaCatalog.bh, places: places, openIds: Set(places.map(\.id)))
        #expect(index.openNow(limit: 3).map(\.id) == ["lourdes", "funcionarios", "savassi"])
    }

    @Test func amanhaPelosMaisMusts() {
        let places = (0..<4).map { place("s\($0)", area: "Savassi", kind: .eat, order: $0) }
            + (0..<2).map { place("c\($0)", area: "Centro", kind: .eat, order: 10 + $0) }
        let index = AreaIndex.build(areas: AreaCatalog.bh, places: places, openIds: [])
        #expect(index.mostMusts(limit: 2).map(\.id) == ["savassi", "centro"])
        #expect(index.openNow(limit: 3).isEmpty)
    }

    @Test func bairroDoDiaEOQueTemMaisParadas() {
        let places = [
            place("x", area: "Savassi", kind: .eat, order: 1),
            place("y", area: "Lourdes", kind: .eat, order: 2),
        ]
        let index = AreaIndex.build(areas: AreaCatalog.bh, places: places, openIds: [])
        #expect(AreaIndex.dayArea(stopPlaceIds: ["y", "x", "x"], index: index) == "savassi")
        // Empate: o que aparece primeiro no roteiro.
        #expect(AreaIndex.dayArea(stopPlaceIds: ["y", "x"], index: index) == "lourdes")
        // Sem bairro nenhum: nil.
        #expect(AreaIndex.dayArea(stopPlaceIds: ["zzz"], index: index) == nil)
        #expect(AreaIndex.dayNeighbors(stopPlaceIds: ["x", "y", "x"], main: "savassi", index: index).map(\.id) == ["lourdes"])
    }

    // MARK: Início (com o board do seed de BH)

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: .bh, bundle: Bundle(for: Token.self))
        return c
    }

    /// Sábado 31 out 2026, 14:20 em BH: o dia tem Café com Letras (Savassi), Glouton (Lourdes) e Albanos (Savassi).
    @Test func diaAceitoTiraBairroParadaAtualELinhaDoDia() throws {
        let c = try container()
        let ctx = c.mainContext
        let region = Region.bh
        let date = BoardDates(timeZone: region.timeZone).day(from: "2026-10-31")!
        let now = BoardDates.parseDateTime("2026-10-31T14:20:00-03:00")!
        let day = PlannedDay(date: date, budget: 200, accepted: true)
        ctx.insert(day)
        let places = try ctx.fetch(FetchDescriptor<Place>())
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stops = [
            Stop(place: byId["p08"], at: BoardDates.parseDateTime("2026-10-31T14:00:00-03:00")!, order: 0),
            Stop(place: byId["p29"], at: BoardDates.parseDateTime("2026-10-31T15:00:00-03:00")!, order: 1),
            Stop(place: byId["p34"], at: BoardDates.parseDateTime("2026-10-31T16:00:00-03:00")!, order: 2),
        ]
        stops.forEach { $0.day = day; ctx.insert($0) }
        let refs = places.map(HomeState.areaPlace)
        let index = AreaIndex.build(areas: AreaCatalog.bh, places: refs, openIds: [])
        let home = HomeState.homeDay(day, index: index, placesById: byId, now: now, region: region, location: nil, tempText: "27°")

        #expect(home.areaId == "savassi")
        #expect(home.title == "Savassi")
        #expect(home.seal == "SAV")
        #expect(home.stops.count == 3)
        #expect(home.current?.placeId == "p08")
        #expect(home.current?.isCurrent == true)
        #expect(home.subtitle.hasSuffix("27°"))
        #expect(home.currentDetail?.contains("às ") == true)
    }

    @Test func dataDoCardEmPortugues() {
        let now = BoardDates.parseDateTime("2026-10-31T09:30:00-03:00")!
        #expect(HomeState.dateLine(now, region: .bh) == "Sáb · 31 out")
    }

    @Test func cidadeDaViagemMostraODiaDaEstadia() throws {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: .jp, bundle: Bundle(for: Token.self))
        let trip = c.mainContext.tripInfo()
        let now = BoardDates.parseDateTime("2026-11-15T18:42:00+09:00")!
        #expect(HomeState.cityLine(now, region: .jp, trip: trip) == "Tóquio · dia 3/5")
    }
}
