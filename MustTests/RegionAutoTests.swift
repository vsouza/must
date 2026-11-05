import Foundation
import Testing
@testable import Must

/// `region.auto`: o Bool de Ajustes e o "NO"/"YES" do argumento de lançamento (`-region.auto NO`, que chega como String).
struct RegionAutoTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) throws {
        let suite = "must-auto-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func missingValueIsAutomatic() throws {
        try withDefaults { #expect(RegionStore.readAuto($0)) }
    }

    @Test func savedBoolIsRespected() throws {
        try withDefaults { d in
            d.set(false, forKey: RegionStore.autoKey)
            #expect(!RegionStore.readAuto(d))
            d.set(true, forKey: RegionStore.autoKey)
            #expect(RegionStore.readAuto(d))
        }
    }

    @Test func launchArgumentStringNOTurnsAutomaticOff() throws {
        try withDefaults { d in
            d.set("NO", forKey: RegionStore.autoKey)
            #expect(!RegionStore.readAuto(d))
            d.set("YES", forKey: RegionStore.autoKey)
            #expect(RegionStore.readAuto(d))
        }
    }
}
