import Foundation
import SwiftData
import Testing
@testable import Must

/// Capa da lista: à mão › foto do Google já no disco › Commons da sincronização (05/11).
@MainActor
struct ListCoverTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "must-cover-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// O container fica guardado no teste: solto, o SwiftData destrói os modelos.
    private let container = RegionStore.inMemoryContainer()

    private func board(seedLists: [String]) -> (ModelContext, MustList, MustList) {
        let context = container.mainContext
        let settings = context.settings(for: .jp)
        settings.seedListOrder = seedLists
        let commons = ListPhoto(flickrId: "1", url: "https://upload.wikimedia.org/x.jpg", credit: "foto · Wikimedia", license: "CC BY", page: nil)
        let seed = MustList(id: "eat", name: "eat", icon: .cafe, color: .eat, photo: commons)
        let mine = MustList(id: "kissaten", name: "kissaten", icon: .cafe, color: .coffee, photo: commons)
        context.insert(seed)
        context.insert(mine)
        return (context, seed, mine)
    }

    @Test func seedListPhotoIsAutomaticAndOwnListPhotoIsManual() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        let (_, seed, mine) = board(seedLists: ["eat"])
        #expect(!ListCover.isManual(seed, defaults: d))
        #expect(ListCover.isManual(mine, defaults: d))
    }

    @Test func choosingAPhotoByHandMakesItManualAndRemovingItGoesBackToAuto() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        let (context, seed, _) = board(seedLists: ["eat"])
        ListCover.mark(seed, chosen: true, context: context, defaults: d)
        #expect(ListCover.isManual(seed, defaults: d))
        ListCover.mark(seed, chosen: false, context: context, defaults: d)
        #expect(!ListCover.isManual(seed, defaults: d))
    }

    @Test func googlePhotoOnDiskWinsInBoardOrderAndNothingOnDiskIsNil() throws {
        let (context, seed, _) = board(seedLists: ["eat"])
        let first = Place(id: "a", name: "A", cityId: "tokyo1")
        let second = Place(id: "b", name: "B", cityId: "tokyo1")
        first.order = 0
        second.order = 1
        second.placeId = "P-b"
        let missing = PlacePhotoRef(name: "places/a/photos/\(UUID().uuidString)")
        let onDisk = PlacePhotoRef(name: "places/b/photos/\(UUID().uuidString)")
        first.photoRefs = [missing]
        second.photoRefs = [onDisk]
        for p in [first, second] { context.insert(p); p.list = seed }
        #expect(ListCover.google(for: seed) == nil)

        let file = try PlacePhotoStore.save(Data([0xFF, 0xD8, 0xFF]), for: onDisk)
        defer { try? FileManager.default.removeItem(at: file) }
        let cover = ListCover.google(for: seed)
        #expect(cover?.source == "Google")
        #expect(cover?.url == file.absoluteString)
    }
}
