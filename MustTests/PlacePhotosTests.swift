import Foundation
import Testing
import UIKit
@testable import Must

/// Prompt 19: fotos do Google (refs no Place, disco com teto, resolvedor, lote e medição de dados). Sem rede.

/// Registra o que o provedor de mentira recebeu, na ordem.
actor PhotoCallLog {
    private var events: [String] = []
    func log(_ event: String) { events.append(event) }
    func all() -> [String] { events }
    func count(prefix: String) -> Int { events.filter { $0.hasPrefix(prefix) }.count }
}

/// Provedor de mentira: refs iniciais, refs novas depois do Details de refresh, nomes expirados e cota recusada.
struct StubPhotos: PlacePhotosProviding {
    let log: PhotoCallLog
    /// Respostas do Details de fotos, uma por chamada (a última repete).
    var answers: [[PlacePhotoRef]]
    var expired: Set<String> = []
    var budgetBlocked = false

    var isConfigured: Bool { true }

    func photoRefs(placeId: String) async throws -> [PlacePhotoRef] {
        await log.log("refs:\(placeId)")
        let call = await log.count(prefix: "refs:") - 1
        return answers[min(call, answers.count - 1)]
    }

    func photo(_ ref: PlacePhotoRef, placeId: String, hero: Bool, prefetch: Bool) async throws -> URL {
        // Igual ao real: o que já está no disco não gasta chamada.
        if let existing = PlacePhotoStore.existing(ref) { return existing }
        await log.log("media:\(ref.name)")
        if budgetBlocked { throw ServiceError.budget("teto diário") }
        if expired.contains(ref.name) { throw ServiceError.http(404, "{}") }
        return try PlacePhotoStore.save(await MainActor.run { PhotoFixtures.jpeg() }, for: ref)
    }
}

enum PhotoFixtures {
    static func jpeg(_ width: CGFloat = 800, _ height: CGFloat = 1067) -> Data {
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.7) ?? Data()
    }

    /// Nome único por teste (o disco é compartilhado com o app de teste).
    static func ref(_ tag: String, author: String? = "Ana Souza") -> PlacePhotoRef {
        PlacePhotoRef(name: "places/T\(UUID().uuidString)/photos/\(tag)", author: author, authorURI: "https://maps.google.com/a")
    }
}

// MARK: - Resolvedor

@MainActor
@Suite struct PlacePhotoResolverTests {
    @Test func photoOnDiskIsServedWithoutAnyCall() async throws {
        let log = PhotoCallLog()
        let r = PhotoFixtures.ref("disco")
        _ = try PlacePhotoStore.save(PhotoFixtures.jpeg(), for: r)
        let resolver = PlacePhotoResolver(provider: StubPhotos(log: log, answers: [[r]]), commons: FakePhotoService())
        let photo = try await resolver.photo(placeId: "P1", refs: [r], index: 0, purpose: .hero, persist: nil)
        #expect(photo?.credit == "foto · Google · @Ana Souza")
        #expect(photo?.source == "Google")
        #expect(await log.all().isEmpty)
    }

    @Test func expiredRefRefreshesDetailsOnceAndRetries() async throws {
        let log = PhotoCallLog()
        let old = PhotoFixtures.ref("velha")
        let new = PhotoFixtures.ref("nova")
        let resolver = PlacePhotoResolver(provider: StubPhotos(log: log, answers: [[new]], expired: [old.name]),
                                          commons: FakePhotoService())
        var saved: [PlacePhotoRef] = []
        let photo = try await resolver.photo(placeId: "P2", refs: [old], index: 0, purpose: .hero, persist: { saved = $0 })
        #expect(photo?.id == new.name)
        #expect(saved == [new])
        // Uma ref morta, um Details de fotos, uma `/media` nova.
        #expect(await log.all() == ["media:\(old.name)", "refs:P2", "media:\(new.name)"])
    }

    @Test func secondExpiryInTheSameSessionDoesNotRefreshAgain() async throws {
        let log = PhotoCallLog()
        let old = PhotoFixtures.ref("morta")
        let new = PhotoFixtures.ref("tambem-morta")
        let resolver = PlacePhotoResolver(provider: StubPhotos(log: log, answers: [[new]], expired: [old.name, new.name]),
                                          commons: FakePhotoService())
        var threw = false
        do { _ = try await resolver.photo(placeId: "P3", refs: [old], index: 0, purpose: .hero, persist: nil) } catch { threw = true }
        #expect(threw)
        #expect(await log.count(prefix: "refs:") == 1)
        // Na mesma sessão, o lugar não refaz o Details de novo.
        threw = false
        do { _ = try await resolver.photo(placeId: "P3", refs: [old], index: 0, purpose: .hero, persist: nil) } catch { threw = true }
        #expect(threw)
        #expect(await log.count(prefix: "refs:") == 1)
    }

    @Test func placeWithoutGooglePhotosAsksOnceAndStaysEmpty() async throws {
        let log = PhotoCallLog()
        let resolver = PlacePhotoResolver(provider: StubPhotos(log: log, answers: [[]]), commons: FakePhotoService())
        let first = try await resolver.photo(placeId: "P4", refs: [], index: 0, purpose: .hero, persist: nil)
        let second = try await resolver.photo(placeId: "P4", refs: [], index: 0, purpose: .hero, persist: nil)
        #expect(first == nil)
        #expect(second == nil)
        #expect(await log.count(prefix: "refs:") == 1)
    }

    @Test func thumbNeverFetchesDetailsOrGallery() async throws {
        let log = PhotoCallLog()
        let resolver = PlacePhotoResolver(provider: StubPhotos(log: log, answers: [[PhotoFixtures.ref("x")]]), commons: FakePhotoService())
        #expect(await resolver.thumb(placeId: "P5", refs: []) == nil)
        let gallery = try await resolver.photo(placeId: "P5", refs: [], index: 2, purpose: .gallery, persist: nil)
        #expect(gallery == nil)
        #expect(await log.all().isEmpty)
    }

    @Test func heroFallsBackToCommonsWhenGoogleIsOutOfBudget() async throws {
        let log = PhotoCallLog()
        let r = PhotoFixtures.ref("cota")
        let provider = StubPhotos(log: log, answers: [[r]], budgetBlocked: true)
        let commons = FakePhotoService(photos: [CCPhoto(id: "c1", url: "https://upload.example.org/c1.jpg", largeURL: nil,
                                                       owner: "Carla", licenseName: "CC BY 2.0", page: "https://commons.example.org/c1")])
        let resolver = PlacePhotoResolver(provider: provider, commons: commons)
        let place = Place(id: "lugar-cota", name: "Lugar", cityId: "bh")
        place.placeId = "P6"
        place.photoRefs = [r]
        let hero = try await resolver.hero(for: place, cityName: "Belo Horizonte", commonsAllowed: true)
        #expect(hero?.source == nil)
        #expect(hero?.credit == "foto · Wikimedia CC BY 2.0 · @Carla")
    }

    @Test func heroWithoutAnyPhotoIsNilNotAnError() async throws {
        let log = PhotoCallLog()
        let resolver = PlacePhotoResolver(provider: StubPhotos(log: log, answers: [[]]), commons: FakePhotoService())
        let place = Place(id: "lugar-sem-foto", name: "Lugar", cityId: "bh")
        place.placeId = "P7"
        let hero = try await resolver.hero(for: place, cityName: "BH", commonsAllowed: false)
        #expect(hero == nil)
        #expect(place.photoRefs.isEmpty)
    }

    @Test func placeRefsKeepFiveAndRoundTrip() {
        let place = Place(id: "lugar-refs", name: "Lugar", cityId: "bh")
        place.photoRefs = (0..<7).map { PhotoFixtures.ref("\($0)") }
        #expect(place.photoRefs.count == 5)
        #expect(place.photoRefsData != nil)
        place.photoRefs = []
        #expect(place.photoRefsData == nil)
    }
}

// MARK: - Disco

@MainActor
@Suite struct PlacePhotoStoreTests {
    static func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-photo-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ dir: URL, _ name: String, size: Int, used: Date) throws {
        let url = dir.appending(path: name)
        try Data(count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: used], ofItemAtPath: url.path())
    }

    @Test func trimDropsStaleGoogleFilesAndTheOldestOverTheCap() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = try Self.scratch()
        let commons = try Self.scratch()
        try Self.file(dir, "muito-velha.jpg", size: 500, used: now.addingTimeInterval(-40 * 86_400))
        try Self.file(dir, "antiga.jpg", size: 1000, used: now.addingTimeInterval(-3 * 86_400))
        try Self.file(dir, "media.jpg", size: 1000, used: now.addingTimeInterval(-2 * 86_400))
        try Self.file(dir, "nova.jpg", size: 1000, used: now.addingTimeInterval(-1 * 86_400))
        let removed = PlacePhotoStore.trim(now: now, cap: 2_500, in: dir, commons: commons)
        #expect(removed == 2)
        let left = Set((try FileManager.default.contentsOfDirectory(atPath: dir.path())))
        #expect(left == ["media.jpg", "nova.jpg"])
    }

    @Test func trimCountsCommonsPhotosInTheSameCap() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = try Self.scratch()
        let commons = try Self.scratch()
        try Self.file(commons, "photo_https___commons.json", size: 1000, used: now.addingTimeInterval(-5 * 86_400))
        try Self.file(commons, "gplaces_outra.json", size: 1000, used: now.addingTimeInterval(-5 * 86_400))
        try Self.file(dir, "google.jpg", size: 1000, used: now.addingTimeInterval(-1 * 86_400))
        PlacePhotoStore.trim(now: now, cap: 1_500, in: dir, commons: commons)
        // A foto do Commons (prefixo `photo`) é a mais antiga: sai primeiro; o JSON de outra coisa não entra no teto.
        #expect(!FileManager.default.fileExists(atPath: commons.appending(path: "photo_https___commons.json").path()))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "google.jpg").path()))
        #expect(FileManager.default.fileExists(atPath: commons.appending(path: "gplaces_outra.json").path()))
    }

    @Test func thumbnailIsTwoHundredAndFortyOnTheLongSide() throws {
        let data = PhotoFixtures.jpeg(800, 1067)
        let thumb = try #require(PlacePhotoStore.makeThumbnail(data, maxPixel: 240))
        let size = try #require(PlacePhotoStore.thumbnailSize(thumb))
        #expect(max(size.width, size.height) == 240)
        #expect(size.width < size.height)
        #expect(thumb.count < data.count)
    }
}

// MARK: - Orçamento

struct PlacePhotoBudgetTests {
    /// Um dia de novembro de 2026 no meio do mês (o mês da cota é o do relógio).
    static let midMonth: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 15; c.hour = 12
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 1_794_000_000)
    }()

    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "must-photo-budget-\(UUID().uuidString)")!
    }

    @Test func placePhotosHasDailyCapOfSixty() {
        let d = Self.defaults()
        ApiBudget.record(.placePhotos, units: 60, now: Self.midMonth, defaults: d)
        #expect(ApiBudget.check(.placePhotos, now: Self.midMonth, defaults: d) == .dailySKUCap(sku: .placePhotos, cap: 60))
        // Amanhã o teto zera.
        let tomorrow = Self.midMonth.addingTimeInterval(86_400)
        #expect(ApiBudget.check(.placePhotos, now: tomorrow, defaults: d) == nil)
    }

    @Test func aboveEightyPercentOnlyTheOpenPlaceHeroGoes() {
        let d = Self.defaults()
        // 850 fotos no mês (acima de 80% de 1.000), gastas em outro dia.
        ApiBudget.record(.placePhotos, units: 850, now: Self.midMonth.addingTimeInterval(-3 * 86_400), defaults: d)
        #expect(ApiBudget.check(.placePhotos, hero: false, now: Self.midMonth, defaults: d) == .monthlyCut(sku: .placePhotos, used: 850))
        #expect(ApiBudget.check(.placePhotos, hero: true, now: Self.midMonth, defaults: d) == nil)
    }

    @Test func heroStopsAtTheFreeQuota() {
        let d = Self.defaults()
        ApiBudget.record(.placePhotos, units: 1_000, now: Self.midMonth.addingTimeInterval(-3 * 86_400), defaults: d)
        #expect(ApiBudget.check(.placePhotos, hero: true, now: Self.midMonth, defaults: d) == .monthlyCut(sku: .placePhotos, used: 1_000))
    }
}

// MARK: - Lote e medição

@MainActor
@Suite struct PhotoBatchTests {
    @Test func batchRunsOnlyWhereTheNetworkAllows() {
        let wifi = PrefetchPolicy.Network(status: .online, wifi: true, expensive: false)
        let cellular = PrefetchPolicy.Network(status: .online, wifi: false, expensive: true)
        let constrained = PrefetchPolicy.Network(status: .constrained, wifi: true, expensive: false)
        let offline = PrefetchPolicy.Network(status: .offline, wifi: false, expensive: false)
        #expect(PhotoBatch.allows(wifi, wifiOnly: true))
        #expect(!PhotoBatch.allows(cellular, wifiOnly: true))
        #expect(PhotoBatch.allows(cellular, wifiOnly: false))
        // Modo de Pouco Dados e offline nunca, mesmo com "só Wi-Fi" desligado.
        #expect(!PhotoBatch.allows(constrained, wifiOnly: false))
        #expect(!PhotoBatch.allows(offline, wifiOnly: false))
    }

    @Test func batchFetchesRefsThenOnePhotoPerPlace() async {
        let log = PhotoCallLog()
        let r = PhotoFixtures.ref("lote")
        let provider = StubPhotos(log: log, answers: [[r]])
        let outcome = await PhotoBatch.fetch(PhotoBatch.Item(id: "p1", placeId: "P8", refs: []), provider: provider)
        #expect(outcome.result == .saved)
        #expect(outcome.refs == [r])
        #expect(await log.all() == ["refs:P8", "media:\(r.name)"])
    }

    @Test func batchStopsOnBudgetAndKeepsTheRefs() async {
        let log = PhotoCallLog()
        let r = PhotoFixtures.ref("teto")
        let provider = StubPhotos(log: log, answers: [[r]], budgetBlocked: true)
        let outcome = await PhotoBatch.fetch(PhotoBatch.Item(id: "p2", placeId: "P9", refs: [r]), provider: provider)
        #expect(outcome.result == .stop("teto diário"))
        #expect(outcome.refs == [r])
    }

    @Test func batchRefreshesExpiredRefsOnce() async {
        let log = PhotoCallLog()
        let old = PhotoFixtures.ref("velha-lote")
        let new = PhotoFixtures.ref("nova-lote")
        let provider = StubPhotos(log: log, answers: [[new]], expired: [old.name])
        let outcome = await PhotoBatch.fetch(PhotoBatch.Item(id: "p3", placeId: "P10", refs: [old]), provider: provider)
        #expect(outcome.result == .saved)
        #expect(outcome.refs == [new])
    }
}

@MainActor
@Suite struct PhotoDataUsageTests {
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "must-data-usage-\(UUID().uuidString)")!
    }

    @Test func bytesAreSplitByNetworkAndMonth() {
        let d = Self.defaults()
        let now = PhotoBudgetTestsClock.midMonth
        DataUsage.add(100, network: .wifi, now: now, defaults: d)
        DataUsage.add(50, network: .cellular, now: now, defaults: d)
        DataUsage.add(25, network: .wifi, now: now, defaults: d)
        #expect(DataUsage.used(.wifi, now: now, defaults: d) == 125)
        #expect(DataUsage.used(.cellular, now: now, defaults: d) == 50)
        // Outro mês começa do zero.
        #expect(DataUsage.used(.wifi, now: now.addingTimeInterval(40 * 86_400), defaults: d) == 0)
    }

    @Test func detailsCarryPhotoRefsAndTheirAuthor() throws {
        let json = """
        {"id": "ChIJ-y", "photos": [
          {"name": "places/ChIJ-y/photos/A", "authorAttributions": [{"displayName": "Lia", "uri": "https://maps.google.com/lia"}]}
        ]}
        """
        let details = try PlacesService.parseDetails(Data(json.utf8))
        #expect(details.photos == [PlacePhotoRef(name: "places/ChIJ-y/photos/A", author: "Lia", authorURI: "https://maps.google.com/lia")])
    }
}

/// Relógio de teste (o mesmo meio de novembro de 2026 das outras suítes de orçamento).
enum PhotoBudgetTestsClock {
    static var midMonth: Date { PlacePhotoBudgetTests.midMonth }
}
