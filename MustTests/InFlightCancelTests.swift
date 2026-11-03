import Foundation
import Testing
@testable import Must

/// Rodada 21 · A.5: o dedupe de GET em voo cancela a requisição quando o último interessado sai.
struct InFlightCancelTests {
    /// Marca o que o trabalho compartilhado fez (começou, foi cancelado).
    actor Probe {
        private(set) var started = false
        private(set) var cancelled = false
        func markStarted() { started = true }
        func markCancelled() { cancelled = true }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 where await !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func cancelaARequisicaoQuandoTodosSaem() async throws {
        let inFlight = InFlight()
        let probe = Probe()
        let waiter = Task {
            try await inFlight.value(for: "k") {
                await probe.markStarted()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    await probe.markCancelled()
                    throw error
                }
                return Data([1])
            }
        }
        try await waitUntil { await probe.started }
        waiter.cancel()
        _ = await waiter.result
        try await waitUntil { await probe.cancelled }
        #expect(await probe.cancelled)
        #expect(await inFlight.count == 0)
    }

    @Test func quemFicaRecebeOResultadoQuandoOutroSai() async throws {
        let inFlight = InFlight()
        let probe = Probe()
        let work: @Sendable () async throws -> Data = {
            await probe.markStarted()
            try await Task.sleep(for: .milliseconds(400))
            return Data([7])
        }
        let first = Task { try await inFlight.value(for: "k", work) }
        try await waitUntil { await probe.started }
        let second = Task { try await inFlight.value(for: "k", work) }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        _ = await first.result
        #expect(try await second.value == Data([7]))
        #expect(await probe.cancelled == false)
        #expect(await inFlight.count == 0)
    }
}
