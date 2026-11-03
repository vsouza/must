import Foundation
import Observation
import SwiftData

/// Ajustes › Dados › "Baixar fotos dos lugares" (prompt 19 · item 5): a foto principal de cada lugar com `placeId`,
/// 4 por vez, em Task de baixa prioridade, pausável e só no Wi-Fi por padrão. Cada lugar: refs (Details só com
/// `photos`, se faltam) e uma `/media`. Vale o teto diário (60 de fotos) e o corte de 80% do mês do `ApiBudget`:
/// quando o teto segura, o lote para e continua no dia seguinte (ou no próximo "Baixar").
@MainActor
@Observable
final class PhotoBatch {
    enum State: Equatable {
        case idle
        case running
        case paused
        /// Sem Wi-Fi (com "só Wi-Fi" ligado) ou em Modo de Pouco Dados: espera a rede boa.
        case waitingNetwork
        /// Parou por cota (teto diário ou corte de 80%): o motivo vai pra tela.
        case stopped(String)
        case done
    }

    /// Lugar do lote, só valores (Sendable): o `Place` fica no main.
    struct Item: Sendable, Equatable {
        var id: String
        var placeId: String
        var refs: [PlacePhotoRef]
    }

    /// Resultado de um lugar, voltando pro main pra gravar as refs.
    struct Outcome: Sendable, Equatable {
        enum Result: Sendable, Equatable {
            case saved, noPhoto, failed, stop(String)
        }
        var id: String
        var refs: [PlacePhotoRef]
        var result: Result
    }

    static let concurrency = 4
    static let wifiOnlyKey = "photos.batchWiFiOnly"

    private(set) var state: State = .idle
    private(set) var done = 0
    private(set) var total = 0

    @ObservationIgnored private let provider: any PlacePhotosProviding
    @ObservationIgnored private var task: Task<Void, Never>?

    init(provider: any PlacePhotosProviding) {
        self.provider = provider
    }

    /// "Só no Wi-Fi" (padrão: ligado). Desligado, o lote também usa o celular (nunca no Modo de Pouco Dados).
    static var wifiOnly: Bool {
        get { UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: wifiOnlyKey) }
    }

    /// Pode rodar agora? Offline e Modo de Pouco Dados (`constrained`) nunca; sem "só Wi-Fi", qualquer rede boa.
    static func allows(_ network: PrefetchPolicy.Network, wifiOnly: Bool) -> Bool {
        guard network.status == .online else { return false }
        return !wifiOnly || network.wifi
    }

    /// Fila do lote: os lugares com `placeId` (o resto não tem foto do Google; a Commons não entra no lote).
    static func queue(_ places: [Place]) -> [Item] {
        places.compactMap { place in
            guard let placeId = place.placeId else { return nil }
            return Item(id: place.id, placeId: placeId, refs: place.photoRefs)
        }
    }

    var isRunning: Bool { task != nil }

    /// Começa (ou retoma) o lote. `network` diz a rede agora (o `Connectivity` do main).
    func start(places: [Place], context: ModelContext, network: @escaping @MainActor () -> PrefetchPolicy.Network) {
        guard task == nil else {
            if state == .paused { state = .running }
            return
        }
        let items = Self.queue(places)
        let owners = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        total = items.count
        done = 0
        state = .running
        let provider = provider
        task = Task(priority: .utility) { [weak self] in
            await self?.run(items, owners: owners, context: context, network: network, provider: provider)
            self?.task = nil
        }
    }

    func pause() {
        guard task != nil, state == .running || state == .waitingNetwork else { return }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    // MARK: Laço

    private func run(_ items: [Item], owners: [String: Place], context: ModelContext,
                     network: @escaping @MainActor () -> PrefetchPolicy.Network, provider: any PlacePhotosProviding) async {
        var index = 0
        while index < items.count {
            guard !Task.isCancelled else { return }
            // Pausado: espera (sem gastar nada).
            while state == .paused, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
            }
            // Rede que não deixa (sem Wi-Fi, ou Modo de Pouco Dados): espera a boa, sem sair do lote.
            guard PhotoBatch.allows(network(), wifiOnly: Self.wifiOnly) else {
                state = .waitingNetwork
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            if state == .waitingNetwork { state = .running }

            let chunk = Array(items[index..<min(index + Self.concurrency, items.count)])
            index += chunk.count
            let outcomes = await withTaskGroup(of: Outcome.self) { group -> [Outcome] in
                for item in chunk {
                    group.addTask { await Self.fetch(item, provider: provider) }
                }
                var all: [Outcome] = []
                for await outcome in group { all.append(outcome) }
                return all
            }
            var stopReason: String?
            for outcome in outcomes {
                if let place = owners[outcome.id], outcome.refs != place.photoRefs, !outcome.refs.isEmpty {
                    place.photoRefs = outcome.refs
                }
                switch outcome.result {
                case .saved, .noPhoto: done += 1
                case .failed: break
                case .stop(let why): stopReason = stopReason ?? why
                }
            }
            try? context.save()
            if let stopReason {
                state = .stopped(stopReason)
                task = nil
                return
            }
        }
        if !Task.isCancelled { state = .done }
    }

    /// Um lugar: refs (se faltam), uma `/media` (disco primeiro). Ref expirada → refaz as refs uma vez.
    /// Sem `@MainActor`: roda fora do main (o `provider` é um struct Sendable).
    nonisolated static func fetch(_ item: Item, provider: any PlacePhotosProviding) async -> Outcome {
        var refs = item.refs
        do {
            if refs.isEmpty {
                refs = try await provider.photoRefs(placeId: item.placeId)
                guard let first = refs.first else { return Outcome(id: item.id, refs: [], result: .noPhoto) }
                _ = try await provider.photo(first, placeId: item.placeId, hero: false, prefetch: true)
                return Outcome(id: item.id, refs: refs, result: .saved)
            }
            do {
                _ = try await provider.photo(refs[0], placeId: item.placeId, hero: false, prefetch: true)
            } catch ServiceError.http(let code, _) where code == 400 || code == 404 {
                refs = try await provider.photoRefs(placeId: item.placeId)
                guard let first = refs.first else { return Outcome(id: item.id, refs: [], result: .noPhoto) }
                _ = try await provider.photo(first, placeId: item.placeId, hero: false, prefetch: true)
            }
            return Outcome(id: item.id, refs: refs, result: .saved)
        } catch ServiceError.budget(let why) {
            return Outcome(id: item.id, refs: refs, result: .stop(why))
        } catch {
            return Outcome(id: item.id, refs: refs, result: .failed)
        }
    }
}
