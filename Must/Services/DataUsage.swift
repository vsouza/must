import Foundation
import Synchronization

/// Dados que o app baixou no mês, por tipo de rede (premissa de dados: Ajustes › Dados mostra "celular × Wi-Fi").
/// Conta o corpo das respostas do `HTTP` (o cabeçalho não entra). Resposta vinda do URLCache não passa pela rede, então não conta.
/// Guardado em UserDefaults por mês (`data.AAAA-MM.wifi` / `.cellular`), como o contador do `ApiBudget`.
enum DataUsage {
    enum Network: String, CaseIterable, Sendable {
        case wifi, cellular
    }

    /// `HTTP` soma de qualquer fila: a soma passa por um cofre.
    private static let lock = Mutex<Void>(())

    static func key(_ network: Network, now: Date) -> String {
        "data.\(ApiBudget.monthKey(now)).\(network.rawValue)"
    }

    static func add(_ bytes: Int, network: Network, now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        guard bytes > 0 else { return }
        lock.withLock { _ in
            defaults.set(defaults.integer(forKey: key(network, now: now)) + bytes, forKey: key(network, now: now))
        }
    }

    static func used(_ network: Network, now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Int64 {
        Int64(defaults.integer(forKey: key(network, now: now)))
    }

    /// Rede atual: Wi-Fi ou o resto (celular, hotspot). Lido de qualquer thread.
    static var currentNetwork: Network { Connectivity.currentIsWiFi ? .wifi : .cellular }
}
