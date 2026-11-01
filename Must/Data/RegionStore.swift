import Foundation
import Observation
import OSLog
import SwiftData

/// Região atual + o `ModelContainer` dela. Trocar região = trocar container (não apaga nada).
/// O root injeta `.modelContainer(store.container)` e usa `.id(store.region)` pra recriar a árvore.
@MainActor
@Observable
final class RegionStore {
    static let regionKey = "region"

    private(set) var region: Region
    private(set) var container: ModelContainer
    /// Último erro ao abrir/semear o container (mostrado no menu escondido).
    private(set) var lastError: String?
    /// Muda a cada container novo (troca de região ou zerar) — o root usa na `.id`.
    private(set) var generation = 0

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let seedBundle: Bundle

    /// - Parameters:
    ///   - directory: onde ficam os `.store` (padrão: App Group). Testes passam uma pasta temporária.
    init(directory: URL? = nil, defaults: UserDefaults = .standard, seedBundle: Bundle = .main) {
        self.directory = directory ?? Region.storeDirectory
        self.defaults = defaults
        self.seedBundle = seedBundle
        let region = Region(rawValue: defaults.string(forKey: Self.regionKey) ?? "") ?? .bh
        self.region = region
        let (container, error) = Self.openContainer(for: region, in: self.directory, seedBundle: seedBundle)
        self.container = container
        self.lastError = error
    }

    func switchTo(_ newRegion: Region) {
        guard newRegion != region else { return }
        Log.data.info("trocando região \(self.region.rawValue, privacy: .public) → \(newRegion.rawValue, privacy: .public)")
        defaults.set(newRegion.rawValue, forKey: Self.regionKey)
        let (container, error) = Self.openContainer(for: newRegion, in: directory, seedBundle: seedBundle)
        self.container = container
        self.lastError = error
        self.region = newRegion
        generation += 1
    }

    /// Apaga o `.store` desta região e reimporta o seed. As outras regiões ficam intactas.
    func resetBoard() {
        Log.data.notice("zerando board \(self.region.rawValue, privacy: .public)")
        // Solta o container atual antes de apagar os arquivos.
        container = Self.inMemoryContainer()
        let base = directory.appending(path: region.storeFileName)
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: base.path() + suffix))
        }
        defaults.removeObject(forKey: Self.onboardedKey(region))
        let (container, error) = Self.openContainer(for: region, in: directory, seedBundle: seedBundle)
        self.container = container
        self.lastError = error
        generation += 1
    }

    // MARK: Onboarding

    static func onboardedKey(_ region: Region) -> String { "onboarded.\(region.rawValue)" }

    var isOnboarded: Bool { defaults.bool(forKey: Self.onboardedKey(region)) }

    func markOnboarded() { defaults.set(true, forKey: Self.onboardedKey(region)) }

    // MARK: Container

    private static func openContainer(for region: Region, in directory: URL, seedBundle: Bundle) -> (ModelContainer, String?) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let config = ModelConfiguration(region.rawValue, schema: MustSchema.schema,
                                            url: directory.appending(path: region.storeFileName))
            let container = try ModelContainer(for: MustSchema.schema, configurations: config)
            try seedIfEmpty(container.mainContext, region: region, bundle: seedBundle)
            return (container, nil)
        } catch {
            Log.data.error("falha abrindo \(region.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            let fallback = inMemoryContainer()
            try? seedIfEmpty(fallback.mainContext, region: region, bundle: seedBundle)
            return (fallback, error.localizedDescription)
        }
    }

    static func inMemoryContainer() -> ModelContainer {
        // swiftlint:disable:next force_try
        try! ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Container vazio → importa `seed-<região>.json` do bundle.
    static func seedIfEmpty(_ context: ModelContext, region: Region, bundle: Bundle) throws {
        let count = try context.fetchCount(FetchDescriptor<MustList>())
        _ = context.settings(for: region)
        guard count == 0 else {
            try addNewKinds(context, region: region, bundle: bundle)
            try context.save()
            return
        }
        guard let url = region.seedURL(in: bundle) else {
            Log.data.error("seed-\(region.rawValue, privacy: .public).json não está no bundle")
            try context.save()
            return
        }
        let board = try BoardCodec.decode(Data(contentsOf: url))
        let summary = try BoardCodec(context: context, region: region).import(board: board)
        Log.data.info("seed \(region.rawValue, privacy: .public): \(summary.description, privacy: .public)")
    }

    /// Board de antes do prompt 13: acrescenta as listas photo/art/sport do seed e os lugares delas
    /// (só o que não existe — nada do usuário é sobrescrito). Roda uma vez por região.
    static func addNewKinds(_ context: ModelContext, region: Region, bundle: Bundle) throws {
        let lists = try context.fetch(FetchDescriptor<MustList>())
        guard !lists.contains(where: { $0.kind != .place }), let url = region.seedURL(in: bundle) else { return }
        let seed = try BoardCodec.decode(Data(contentsOf: url))
        let kinds = seed.lists.filter { ($0.kind ?? .place) != .place }
        let ids = Set(kinds.map(\.id))
        // Uma lista do usuário com o mesmo id ganha o tipo; nenhuma lista nova se ela já existir.
        for list in lists where ids.contains(list.id) { list.kind = kinds.first { $0.id == list.id }?.kind ?? .place }
        let existing = Set(lists.map(\.id))
        let knownPlaces = Set(try context.fetch(FetchDescriptor<Place>()).map(\.id))
        let board = Board(version: seed.version, region: seed.region, trip: nil, budget: nil,
                          lists: kinds.filter { !existing.contains($0.id) },
                          places: seed.places.filter { ids.contains($0.listId) && !knownPlaces.contains($0.id) },
                          expenses: nil, days: nil, events: nil)
        guard !board.lists.isEmpty || !board.places.isEmpty else { return }
        let summary = try BoardCodec(context: context, region: region).import(board: board)
        Log.data.info("tipos novos \(region.rawValue, privacy: .public): \(summary.description, privacy: .public)")
    }
}
