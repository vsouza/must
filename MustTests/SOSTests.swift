import CoreLocation
import Foundation
import Testing
@testable import Must

/// SOS (prompt 25 · C): os dados do usuário ficam só no aparelho (fora do backup, fora do App Group), o "onde estou"
/// usa o último endereço conhecido sem rede e só pede de novo quando a pessoa andou, e a Quick Action chega à tela.
@MainActor
struct SOSTests {
    private func tempStore() -> SOSStore {
        SOSStore(directory: URL.temporaryDirectory.appending(path: "sos-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func perfilSoNoAparelhoForaDoBackup() throws {
        let store = tempStore()
        #expect(store.profile() == SOSProfile())
        var p = SOSProfile()
        p.insurer = "Assist Card"
        p.policy = "AC-123"
        p.phone24h = "+55 11 3003-0000"
        p.bloodType = "O+"
        try store.save(p)
        #expect(store.profile() == p)
        #expect(SOSStore.isExcludedFromBackup(store.profileFile))
        #expect(SOSStore.isExcludedFromBackup(store.directory))
    }

    @Test func pastaPadraoEApplicationSupportNuncaOAppGroup() {
        let dir = SOSStore().directory
        #expect(dir.path(percentEncoded: false).contains("Application Support"))
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Region.appGroup) {
            #expect(!dir.path().hasPrefix(group.path()))
        }
        #expect(!dir.path().contains("Mobile Documents")) // iCloud Drive
    }

    @Test func perfilNaoVaiProWidgetNemProDefaults() throws {
        let store = tempStore()
        var p = SOSProfile()
        p.insurer = "Seguradora-Secreta-\(UUID().uuidString)"
        try store.save(p)
        let shared = MustShared.defaults?.dictionaryRepresentation().values.map { "\($0)" }.joined() ?? ""
        #expect(!shared.contains(p.insurer))
        let std = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }.joined()
        #expect(!std.contains(p.insurer))
    }

    @Test func ultimoEnderecoPorPais() throws {
        let store = tempStore()
        let a = LastAddress(local: "東京都新宿区歌舞伎町1-3-9", latin: "Kabukichō 1-3-9, Shinjuku", lat: 35.6938, lng: 139.7034,
                            at: Date(timeIntervalSince1970: 1_800_000_000), country: "JP")
        try store.save(a)
        #expect(store.lastAddress(country: "JP") == a)
        #expect(store.lastAddress(country: "IT") == nil) // endereço do Japão não aparece no SOS da Itália
    }

    @Test func soPedeDeNovoQuandoAndouOuFicouVelho() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let last = LastAddress(local: "x", latin: "x", lat: 35.6938, lng: 139.7034, at: now, country: "JP")
        let here = CLLocation(latitude: 35.6938, longitude: 139.7034)
        #expect(!WhereAmI.needsRefresh(last, location: here, now: now.addingTimeInterval(60)))
        #expect(WhereAmI.needsRefresh(last, location: CLLocation(latitude: 35.6960, longitude: 139.7034), now: now)) // ~245 m
        #expect(WhereAmI.needsRefresh(last, location: here, now: now.addingTimeInterval(11 * 60)))
        #expect(WhereAmI.needsRefresh(nil, location: here, now: now))
    }

    @Test func semRedeMostraOUltimoConhecidoOuACoordenada() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let last = LastAddress(local: "東京都新宿区歌舞伎町1-3-9", latin: "Kabukichō 1-3-9, Shinjuku", lat: 35.6938, lng: 139.7034,
                               at: now, country: "JP")
        let far = CLLocation(latitude: 35.70, longitude: 139.71)
        let shown = WhereAmI.display(last, location: far, now: now)
        #expect(shown?.main == "東京都新宿区歌舞伎町1-3-9")
        #expect(shown?.sub == "Kabukichō 1-3-9, Shinjuku")
        #expect(shown?.isStale == true)
        let coord = WhereAmI.display(nil, location: CLLocation(latitude: -19.93851, longitude: -43.93432), now: now)
        #expect(coord?.main == "-19.93851, -43.93432")
        #expect(WhereAmI.display(nil, location: nil, now: now) == nil)
    }

    @Test func enderecoJaponesDoMaiorProMenor() {
        let parts = AddressParts(name: "歌舞伎町1丁目3-9", thoroughfare: "歌舞伎町1丁目", subThoroughfare: "3-9",
                                 subLocality: "歌舞伎町", locality: "新宿区", administrativeArea: "東京都")
        #expect(WhereAmI.line(parts, japaneseOrder: true) == "東京都新宿区歌舞伎町1丁目3-9")
        let br = AddressParts(name: "Praça da Liberdade", thoroughfare: "Praça da Liberdade", subThoroughfare: "450",
                              subLocality: "Funcionários", locality: "Belo Horizonte", administrativeArea: "MG")
        #expect(WhereAmI.line(br, japaneseOrder: false) == "Praça da Liberdade, 450 · Funcionários · Belo Horizonte")
    }

    @Test func geocoderEmJaponesEDepoisEmLatino() async {
        struct Fake: AddressGeocoding {
            func parts(at location: CLLocation, locale: Locale) async throws -> AddressParts? {
                locale.identifier.hasPrefix("ja")
                    ? AddressParts(thoroughfare: "歌舞伎町1丁目", subThoroughfare: "3-9", locality: "新宿区", administrativeArea: "東京都")
                    : AddressParts(thoroughfare: "1-chōme Kabukichō", subThoroughfare: "3-9", subLocality: nil, locality: "Shinjuku")
            }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let got = await WhereAmI.lookup(CLLocation(latitude: 35.69, longitude: 139.70), region: .jp, geocoder: Fake(), now: now)
        #expect(got?.local == "東京都新宿区歌舞伎町1丁目3-9")
        #expect(got?.latin == "1-chōme Kabukichō, 3-9 · Shinjuku")
        #expect(got?.country == "JP")
        #expect(got?.at == now)
    }

    @Test func quickActionChegaMesmoAntesDaRaiz() {
        let actions = QuickActions()
        var got: [String] = []
        actions.receive(QuickActions.sosType) // app abriu pelo atalho: a raiz ainda não montou
        actions.handler = { got.append($0) }
        #expect(got == [QuickActions.sosType])
        actions.receive(QuickActions.sosType)
        #expect(got.count == 2)
    }

    @Test func linkDoSOSEmpilhaNaAbaHoje() {
        let router = AppRouter()
        router.sheet = .assistant
        router.handle(url: NextStopAttributes.sosURL, region: .bh)
        #expect(router.sheet == nil)
        #expect(router.tab == .hoje)
        #expect(router.paths[.hoje] == [.sos])
        #expect(router.hidesNavBar)
    }

    @Test func liveActivitySoMostraSOSANoite() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func state(_ h: Int) -> NextStopAttributes.ContentState {
            NextStopAttributes.ContentState(number: 1, name: "x", at: cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: h))!,
                                            detail: "", done: 0, total: 1)
        }
        #expect(state(21).isNight(calendar: cal))
        #expect(state(2).isNight(calendar: cal))
        #expect(!state(15).isNight(calendar: cal))
    }
}
