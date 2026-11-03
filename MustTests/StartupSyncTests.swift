import Foundation
import Testing
@testable import Must

/// Arranque (prompt 18 · A.6): a primeira sincronização espera o atraso; pedidos seguidos viram um.
@MainActor
struct StartupSyncTests {
    private actor Calls {
        private(set) var sleeps: [Duration] = []
        private(set) var runs = 0
        func slept(_ d: Duration) { sleeps.append(d) }
        func ran() { runs += 1 }
    }

    /// Espera até a condição valer, cedendo o main actor pras tasks rodarem (sem tempo de relógio).
    private func settle(_ condition: () async -> Bool) async {
        for _ in 0..<500 where !(await condition()) { await Task.yield() }
    }

    @Test func primeiraSincronizacaoEsperaOArranque() async {
        let calls = Calls()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let sync = StartupSync(sleep: { d in
            await calls.slept(d)
            for await _ in gate { break } // o "relógio" só termina quando o teste solta
        })

        #expect(sync.request { await calls.ran() })
        await settle { await calls.sleeps.count == 1 }
        #expect(await calls.sleeps == [StartupSync.launchDelay])
        #expect(await calls.runs == 0, "nada de sincronizar antes do atraso de arranque")

        release.yield(())
        await settle { await calls.runs == 1 }
        #expect(await calls.runs == 1)
        await settle { !sync.isBusy }
        #expect(!sync.isBusy)
    }

    @Test func pedidosSeguidosViramUm() async {
        let calls = Calls()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let sync = StartupSync(sleep: { _ in for await _ in gate { break } })

        #expect(sync.request { await calls.ran() })
        // Abertura, `.active` e "voltou a rede" chegam juntos: só o primeiro entra.
        #expect(!sync.request { await calls.ran() })
        #expect(!sync.request { await calls.ran() })

        release.yield(())
        await settle { await calls.runs == 1 }
        await settle { !sync.isBusy }
        #expect(await calls.runs == 1)
    }

    @Test func depoisDoArranqueOPedidoVaiNaHora() async {
        let calls = Calls()
        let sync = StartupSync(sleep: { d in await calls.slept(d) })

        #expect(sync.request { await calls.ran() })
        await settle { await calls.runs == 1 }
        await settle { !sync.isBusy }

        // Voltou pro app (ou a rede): sem atraso de novo; o limite de 6 h fica no SyncCoordinator.
        #expect(sync.request { await calls.ran() })
        await settle { await calls.runs == 2 }
        #expect(await calls.runs == 2)
        #expect(await calls.sleeps.count == 1, "só a primeira abertura dorme")
    }

    @Test func atrasoDeArranqueSaiDoPrompt() {
        #expect(StartupSync.launchDelay == .seconds(2))
    }
}
