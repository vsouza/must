import CoreLocation
import Foundation
import Testing
@testable import Must

/// Bairro pelo GPS (prompt 21 · fatia 2): grade de 300 m, nome do geocoder → bairro, cache por célula e a
/// capa de bairro só no Wi-Fi. Sem rede de verdade: o geocoder e as fotos são falsos.
@MainActor
struct CurrentAreaTests {
    // MARK: Grade

    @Test func celulaTemCercaDe300Metros() {
        let metersPerCell = AreaGrid.step * 111_000
        #expect(metersPerCell > 280 && metersPerCell < 320)
    }

    @Test func pontosNoMeioDaMesmaCelulaCaemJuntos() {
        let c = AreaGrid.cell(lat: 35.6909, lng: 139.7003)
        let lat0 = Double(c.row) * AreaGrid.step
        let lng0 = Double(c.column) * AreaGrid.step
        // Dois pontos dentro da célula, longe das bordas: mesma chave.
        let a = AreaGrid.key(lat: lat0 + AreaGrid.step * 0.3, lng: lng0 + AreaGrid.step * 0.3, region: .jp)
        let b = AreaGrid.key(lat: lat0 + AreaGrid.step * 0.7, lng: lng0 + AreaGrid.step * 0.6, region: .jp)
        #expect(a == b)
    }

    @Test func celulaVizinhaTemOutraChave() {
        let c = AreaGrid.cell(lat: 35.6909, lng: 139.7003)
        let lat0 = Double(c.row) * AreaGrid.step
        let lng0 = Double(c.column) * AreaGrid.step
        let here = AreaGrid.key(lat: lat0 + AreaGrid.step / 2, lng: lng0 + AreaGrid.step / 2, region: .jp)
        let north = AreaGrid.key(lat: lat0 + AreaGrid.step * 1.5, lng: lng0 + AreaGrid.step / 2, region: .jp)
        let sameCellOtherRegion = AreaGrid.key(lat: lat0 + AreaGrid.step / 2, lng: lng0 + AreaGrid.step / 2, region: .bh)
        #expect(here != north)
        #expect(here != sameCellOtherRegion)
    }

    // MARK: Nome → bairro

    @Test func shinjukuKuViraShinjuku() {
        let area = AreaNameMatch.area(named: ["Shinjuku-ku"], in: AreaCatalog.jp)
        #expect(area?.id == "shinjuku")
    }

    @Test func acentoECaixaNaoAtrapalham() {
        let area = AreaNameMatch.area(named: ["SAVASSI"], in: AreaCatalog.bh)
        #expect(area?.id == "savassi")
        let folded = AreaNameMatch.area(named: ["Nakameguro"], in: AreaCatalog.jp)
        #expect(folded?.name == "Naka-Meguro")
    }

    @Test func nomeDesconhecidoNaoAchaBairro() {
        #expect(AreaNameMatch.area(named: ["Belo Horizonte", "Yoyogi"], in: AreaCatalog.jp) == nil)
        #expect(AreaNameMatch.area(named: [], in: AreaCatalog.bh) == nil)
    }

    @Test func primeiroNomeQueBateGanha() {
        // Do mais local pro mais amplo: o bairro vem antes da cidade.
        let area = AreaNameMatch.area(named: ["Yoyogi", "Shibuya"], in: AreaCatalog.jp)
        #expect(area?.id == "shibuya")
    }

    // MARK: Cache por célula

    @Test func tabelaCuradaNaoPedeGeocoder() async {
        let geocoder = FakeAreaGeocoder(names: ["Nada"])
        let service = CurrentAreaService(geocoder: geocoder, store: MemoryAreaCellStore(), isOnline: { true })
        // Centroide de Savassi (BH): a tabela resolve sem rede.
        let area = await service.area(at: CLLocation(latitude: -19.9385, longitude: -43.9343), region: .bh)
        #expect(area?.id == "savassi")
        #expect(await geocoder.calls == 0)
    }

    @Test func mesmaCelulaNaoGeocodificaDeNovo() async {
        let geocoder = FakeAreaGeocoder(names: ["Yoyogi", "Shibuya"])
        let store = MemoryAreaCellStore()
        let service = CurrentAreaService(geocoder: geocoder, store: store, isOnline: { true })
        // Longe da tabela (Yoyogi não está): cai no geocoder.
        let here = CLLocation(latitude: 35.50, longitude: 139.50)
        let first = await service.area(at: here, region: .jp)
        #expect(first?.id == "shibuya")
        #expect(await geocoder.calls == 1)

        // Mesma célula, outro ponto: nada de rede.
        let nearby = CLLocation(latitude: 35.50005, longitude: 139.50005)
        #expect(await service.area(at: nearby, region: .jp)?.id == "shibuya")
        #expect(await geocoder.calls == 1)

        // Outro serviço (outra abertura do app) com o mesmo disco: também não geocodifica.
        let reopened = CurrentAreaService(geocoder: geocoder, store: store, isOnline: { true })
        #expect(await reopened.area(at: nearby, region: .jp)?.id == "shibuya")
        #expect(await geocoder.calls == 1)
    }

    @Test func offlineUsaOUltimoValorSemGeocoder() async {
        let geocoder = FakeAreaGeocoder(names: ["Yoyogi", "Shibuya"])
        let service = CurrentAreaService(geocoder: geocoder, store: MemoryAreaCellStore(), isOnline: { false })
        let here = CLLocation(latitude: 35.50, longitude: 139.50)
        #expect(await service.area(at: here, region: .jp) == nil)
        #expect(await geocoder.calls == 0)
    }

    // MARK: Capa de bairro (Wi-Fi)

    @Test func capaDeBairroNaoSaiNaRedeForaDoWiFi() async {
        let places = [AreaPlace(id: "p1", name: "Savassi Bar", areaName: "Savassi", cityId: "bh", lat: -19.9385, lng: -43.9343,
                                kind: .eat, isDone: false, verified: false, order: 0, hasReservation: false)]
        let photos = FakePhotoProvider()
        let celular = PrefetchPolicy.Network(status: .online, wifi: false, expensive: true)
        let pouco = PrefetchPolicy.Network(status: .constrained, wifi: true, expensive: false)
        let offline = PrefetchPolicy.Network(status: .offline, wifi: false, expensive: false)
        #expect(await AreaCoverPrefetch.run(region: .bh, places: places, network: celular, photos: photos, cityName: "BH") == 0)
        #expect(await AreaCoverPrefetch.run(region: .bh, places: places, network: pouco, photos: photos, cityName: "BH") == 0)
        #expect(await AreaCoverPrefetch.run(region: .bh, places: places, network: offline, photos: photos, cityName: "BH") == 0)
        #expect(await photos.calls == 0)
    }

    @Test func soWiFiLiberaACapa() {
        #expect(PrefetchPolicy.allows(.init(status: .online, wifi: true, expensive: false)))
        #expect(!PrefetchPolicy.allows(.init(status: .online, wifi: true, expensive: true)))
        #expect(!PrefetchPolicy.allows(.init(status: .constrained, wifi: true, expensive: false)))
        #expect(!PrefetchPolicy.allows(.init(status: .online, wifi: false, expensive: false)))
    }
}

// MARK: Falsos

/// Geocoder que conta as chamadas e devolve sempre os mesmos nomes.
private actor FakeAreaGeocoder: AreaNameGeocoding {
    private(set) var calls = 0
    private let names: [String]

    init(names: [String]) { self.names = names }

    func names(at location: CLLocation) async throws -> [String] {
        calls += 1
        return names
    }
}

private actor MemoryAreaCellStore: AreaCellStore {
    private var values: [String: String] = [:]

    func value(for key: String) async -> String? { values[key] }
    func save(_ value: String, for key: String) async { values[key] = value }
}

/// Fotos de mentira: conta as buscas (nenhuma foto sai da máquina).
private actor FakePhotoProvider: PhotoProviding {
    private(set) var calls = 0
    nonisolated var isConfigured: Bool { true }

    func search(text: String) async throws -> [CCPhoto] {
        calls += 1
        return []
    }

    func search(near: CLLocationCoordinate2D, radiusKm: Double) async throws -> [CCPhoto] {
        calls += 1
        return []
    }
}
