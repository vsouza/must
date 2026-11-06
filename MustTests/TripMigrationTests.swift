import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 28 §3.1: migração de dados = nenhuma. Um aparelho com `must-jp.store` de antes do registro (sem
/// `trips.json`) abre o mesmo container, com o que o usuário mudou, e ganha o registro semeado.
@MainActor
struct TripMigrationTests {
    private final class Token {}

    @Test func containerAntigoAbreIgual() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-migr-\(UUID().uuidString)")
        let suite = "must-migr-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }
        // "Antes do update": abre o Japão, marca um lugar como feito, e o trips.json não existe.
        do {
            let old = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
            old.switchTo(.jp)
            let context = old.container.mainContext
            let place = try #require(try context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.id)])).first)
            place.done = DoneMark(at: Date(timeIntervalSince1970: 1_700_000_000), spent: nil)
            try context.save()
        }
        try FileManager.default.removeItem(at: dir.appending(path: TripRegistry.fileName))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0.hasSuffix(".store") }.sorted()
        #expect(before == ["must-bh.store", "must-jp.store"])

        // "Depois do update".
        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        #expect(store.region == .jp)
        #expect(store.current.id == "jp")
        #expect(store.trips.map(\.id) == ["bh", "jp", "it"])
        let context = store.container.mainContext
        let places = try context.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.id)]))
        #expect(!places.isEmpty)
        #expect(places.first?.isDone == true)
        let after = try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0.hasSuffix(".store") }.sorted()
        #expect(after == before)
    }
}
