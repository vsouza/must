import Foundation
import Testing
@testable import Must

struct SecretsTests {
    @Test func missingPlistReturnsEmpty() {
        // Bundle de testes não tem Secrets.plist: deve devolver vazio sem crashar.
        let values = Secrets.load(from: Bundle(for: BundleToken.self))
        #expect(values.isEmpty)
    }
}

private final class BundleToken {}
