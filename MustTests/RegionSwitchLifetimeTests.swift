import Foundation
import SwiftData
import Testing
@testable import Must

/// Trocar de região não solta o container antigo: a árvore que sai ainda lê o `context` dele por um instante
/// (`didSave` do board novo, animação da troca). Antes, `context.container` de um container solto parava o app
/// no SwiftData (EXC_BREAKPOINT em `AppRoot.refreshOutsideSoon`, iPhone, 05/11).
@MainActor
struct RegionSwitchLifetimeTests {
    private final class Token {}

    @Test func oldContextStaysUsableAfterSwitchingRegion() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-tests-\(UUID().uuidString)")
        let suite = "must-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        // O que o `@Environment(\.modelContext)` da árvore velha guarda: só o contexto, não o container.
        weak var oldContainer = store.container
        let oldContext = store.container.mainContext

        store.switchTo(.jp)
        #expect(store.region == .jp)
        #expect(store.retiredCount == 1)
        #expect(oldContainer != nil)
        // Ler o board velho depois da troca não derruba.
        _ = oldContext.container
        #expect(try oldContext.fetchCount(FetchDescriptor<Place>()) == 50)

        store.switchTo(.bh)
        #expect(store.retiredCount == 2)
    }
}
