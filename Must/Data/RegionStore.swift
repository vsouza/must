import CoreLocation
import Foundation
import Observation
import OSLog
import SwiftData
import SwiftUI

/// Região atual + o `ModelContainer` dela. Trocar região = trocar container (não apaga nada).
/// O root injeta `.modelContainer(store.container)` e usa `.id(store.region)` pra recriar a árvore.
@MainActor
@Observable
final class RegionStore {
    static let regionKey = "region"
    /// Região pelo GPS (padrão). Escolher BH, Japão ou Itália à mão desliga.
    nonisolated static let autoKey = "region.auto"

    private(set) var region: Region
    private(set) var container: ModelContainer
    /// Último erro ao abrir/semear o container (mostrado no menu escondido).
    private(set) var lastError: String?
    /// Muda a cada container novo (troca de região ou zerar) — o root usa na `.id`.
    private(set) var generation = 0
    /// Viagem recém-criada esperando a folha do fluxo Nova viagem fechar pra abrir (o passo 9 ainda mostra "Pronto").
    private(set) var pendingTrip: TripID?
    /// Container já aberto e preenchido de uma viagem nova (reaproveitado na troca; nunca dois no mesmo arquivo).
    @ObservationIgnored private var prepared: [TripID: ModelContainer] = [:]

    /// Containers que já saíram (troca de região, zerar). Ficam vivos até o app fechar: a árvore velha ainda roda
    /// por um instante (animação da troca, `didSave` do board novo, tarefas em voo) e ler `context.container` de um
    /// container solto derruba o app no SwiftData. Três regiões: no máximo uns poucos containers, pouca memória.
    @ObservationIgnored private var retired: [ModelContainer] = []
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let seedBundle: Bundle
    /// Registro das viagens (`trips.json`, prompt 28). Semeado com bh/jp/it na primeira abertura.
    @ObservationIgnored let registry: TripRegistry
    /// Viagens do registro que aparecem em Minhas viagens (sem as arquivadas).
    private(set) var trips: [Trip]

    /// - Parameters:
    ///   - directory: onde ficam os `.store` (padrão: App Group). Testes passam uma pasta temporária.
    init(directory: URL? = nil, defaults: UserDefaults = .standard, seedBundle: Bundle = .main) {
        let directory = directory ?? Self.debugFreshDirectory ?? Region.storeDirectory
        self.directory = directory
        self.defaults = defaults
        self.seedBundle = seedBundle
        let registry = TripRegistry(directory: directory)
        self.registry = registry
        self.trips = registry.visible
        Self.moveToBrazilOnce(defaults)
        // A viagem guardada; apagada ou arquivada, a de casa (ou a primeira do registro).
        let saved = defaults.string(forKey: Self.regionKey).flatMap(registry.trip).flatMap { $0.archived ? nil : $0 }
        let fallback = registry.visible.first { $0.kind == .home } ?? registry.visible.first
        let region = (saved ?? fallback).map(Region.init(trip:)) ?? .bh
        self.region = region
        let (container, error) = Self.openContainer(for: region, in: self.directory, seedBundle: seedBundle)
        self.container = container
        self.lastError = error
    }

    /// `-debugFreshStore YES` (UI tests, rodada 23 · G): cada abertura começa do seed numa pasta temporária, sem tocar
    /// no board do simulador. Só DEBUG e fora do host de testes.
    static var debugFreshDirectory: URL? {
        guard DebugFlags.bool("debugFreshStore") else { return nil }
        let dir = URL.temporaryDirectory.appending(path: "must-uitests-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Uma vez (05/11/2026, pedido do Vinicius: "vamos mudar o app pro brasil por hora, quero usar ele na rua"):
    /// volta pro BH no automático e desliga data/GPS simulados do menu escondido, pra o teste de rua usar hora e GPS
    /// reais. Depois disso, Ajustes › Região manda de novo. Nunca nos testes nem nos prints (`-debugScreen`).
    static let brazilOnceKey = "region.v8.brasilParaRua"

    static func moveToBrazilOnce(_ defaults: UserDefaults) {
        guard defaults === UserDefaults.standard, !DebugFlags.isTestHost, DebugFlags.string("debugScreen") == nil,
              !defaults.bool(forKey: brazilOnceKey) else { return }
        defaults.set(true, forKey: brazilOnceKey)
        defaults.set(Region.bh.rawValue, forKey: regionKey)
        defaults.set(true, forKey: autoKey)
        defaults.set(false, forKey: DevOverrides.Key.simDateOn)
        defaults.set(false, forKey: DevOverrides.Key.simGPSOn)
    }

    /// A viagem atual (registro).
    var current: Trip { registry.trip(region.rawValue) ?? region.trip }

    /// Tema da viagem da região (bandeira, lavado, selos). `MustApp` injeta no ambiente, fora da `.id`.
    var theme: TripTheme { TripTheme.forRegion(region) }

    /// Automático: abre na região onde o GPS está (BH no Brasil, Japão lá, Roma na Itália).
    var isAuto: Bool { Self.readAuto(defaults) }

    /// Sem valor = automático. `bool(forKey:)` entende o Bool gravado e o "NO"/"YES" do argumento de lançamento
    /// (`-region.auto NO` chega como String; `as? Bool` lia nil e o automático continuava ligado).
    nonisolated static func readAuto(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: autoKey) == nil ? true : defaults.bool(forKey: autoKey)
    }

    /// Ajustes › Região: `nil` = automático pelo GPS; uma região = fixa nela.
    func choose(_ newRegion: Region?, near coordinate: CLLocationCoordinate2D?) {
        defaults.set(newRegion == nil, forKey: Self.autoKey)
        if let newRegion {
            switchTo(newRegion)
        } else if let coordinate {
            followGPS(coordinate)
        }
    }

    /// No automático, abre a viagem da regra do prompt 28 §3.10: datas de hoje › país do GPS › casa.
    func followGPS(_ coordinate: CLLocationCoordinate2D, now: Date = AppClock.now) {
        guard isAuto, let picked = autoPick(near: coordinate, now: now), picked != region else { return }
        Log.data.info("automático: abrindo \(picked.rawValue, privacy: .public)")
        switchTo(picked)
    }

    /// A viagem que o automático abriria aqui e agora (Minhas viagens marca "GPS").
    func autoPick(near coordinate: CLLocationCoordinate2D?, now: Date = AppClock.now) -> Region? {
        let all = registry.trips
        let country = coordinate.flatMap { RegionAuto.country(at: $0, trips: all) }
        return RegionAuto.pick(trips: all, now: now, gpsCountry: country).flatMap(region(for:))
    }

    /// A viagem do registro como `Region` (o que a UI lê).
    func region(for id: TripID) -> Region? { registry.trip(id).map(Region.init(trip:)) }

    func switchTo(_ newRegion: Region) {
        guard newRegion != region else { return }
        // Sempre a versão do registro (datas e nome atualizados).
        let newRegion = region(for: newRegion.rawValue) ?? newRegion
        Log.data.info("trocando região \(self.region.rawValue, privacy: .public) → \(newRegion.rawValue, privacy: .public)")
        defaults.set(newRegion.rawValue, forKey: Self.regionKey)
        let (container, error) = prepared.removeValue(forKey: newRegion.rawValue).map { ($0, nil) }
            ?? Self.openContainer(for: newRegion, in: directory, seedBundle: seedBundle)
        retire(self.container)
        // 0,4 s: o tema (lavado, bandeira, selos) troca junto com a região (prompt 20).
        withAnimation(.easeInOut(duration: 0.4)) {
            self.container = container
            self.lastError = error
            self.region = newRegion
            generation += 1
        }
    }

    /// Apaga o `.store` desta região e reimporta o seed. As outras regiões ficam intactas.
    func resetBoard() {
        Log.data.notice("zerando board \(self.region.rawValue, privacy: .public)")
        // Tira o container atual de uso antes de apagar os arquivos (ele fica vivo em `retired`: a árvore que sai
        // ainda pode ler o contexto dele).
        retire(container)
        container = Self.inMemoryContainer()
        retire(container)
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

    private func retire(_ old: ModelContainer) {
        guard !retired.contains(where: { $0 === old }) else { return }
        retired.append(old)
    }

    /// Quantos containers estão guardados (teste).
    var retiredCount: Int { retired.count }

    // MARK: Viagens (prompt 28 · F2)

    /// Relê o registro (depois de criar, arquivar ou apagar).
    func reloadTrips() { trips = registry.visible }

    /// Arquivar: some de Minhas viagens, o `.store` fica. A de casa não arquiva; a aberta volta pra casa antes.
    func archive(_ id: TripID) {
        guard let trip = registry.trip(id), trip.kind != .home else { return }
        if region.rawValue == id { leaveToHome() }
        registry.setArchived(id, true)
        reloadTrips()
        Log.data.info("viagem arquivada \(id, privacy: .public)")
    }

    /// Apagar: tira do registro e apaga **só** o `.store` dela (e os bairros gerados). A de casa não apaga.
    func delete(_ id: TripID) {
        guard let trip = registry.trip(id), trip.kind != .home else { return }
        if region.rawValue == id { leaveToHome() }
        let base = directory.appending(path: trip.storeFileName)
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: base.path() + suffix))
        }
        registry.remove(id)
        KnownTrips.shared.forget(id)
        GeneratedAreaStore.shared.forget(id, directory: directory)
        defaults.removeObject(forKey: "onboarded.\(id)")
        reloadTrips()
        Log.data.notice("viagem apagada \(id, privacy: .public)")
    }

    private func leaveToHome() {
        let home = registry.visible.first { $0.kind == .home && $0.id != region.rawValue }
            ?? registry.visible.first { $0.id != region.rawValue }
        if let home { switchTo(Region(trip: home)) }
    }

    /// Pasta dos `.store` desta instância (testes: temporária).
    var storeDirectory: URL { directory }

    /// Nova viagem (prompt 28 §4): grava no registro, abre o container novo `must-<slug>-<4 letras>.store`, preenche
    /// com o rascunho e deixa pronta pra abrir. `openNow: false` (o fluxo) troca quando a folha fecha (`openPending`);
    /// o automático desliga pra o GPS não puxar de volta pra casa logo depois.
    @discardableResult
    func create(_ draft: NewTripDraft, openNow: Bool = false, now: Date = AppClock.now) throws -> Trip {
        let trip = try NewTripWriter.trip(from: draft, taken: Set(registry.trips.map(\.id)), now: now)
        let region = Region(trip: trip)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(trip.id, schema: MustSchema.schema, url: directory.appending(path: trip.storeFileName))
        let container = try ModelContainer(for: MustSchema.schema, configurations: config)
        try NewTripWriter.fill(container.mainContext, trip: trip, draft: draft, now: now)
        Self.applyRegionDefaults(container.mainContext.settings(for: region), region: region)
        try container.mainContext.save()
        registry.upsert(trip)
        reloadTrips()
        defaults.set(true, forKey: Self.onboardedKey(region))
        defaults.set(false, forKey: Self.autoKey)
        prepared[trip.id] = container
        Log.data.notice("viagem nova \(trip.id, privacy: .public): \(trip.cities.count) cidades, \(draft.places.count) lugares")
        if openNow { switchTo(region) } else { pendingTrip = trip.id }
        return trip
    }

    /// Abre a viagem criada pelo fluxo (chamado quando a folha Nova viagem fecha).
    func openPending() {
        guard let id = pendingTrip else { return }
        pendingTrip = nil
        if let region = region(for: id) { switchTo(region) }
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
        applyRegionDefaults(context.settings(for: region), region: region)
        guard count == 0 else {
            guard region.trip.isBuiltIn else {
                try context.save()
                return
            }
            try BoardCodec(context: context, region: region).migrateFlightEvents()
            try mergeSeed(context, region: region, bundle: bundle)
            WalletStarter.ensure(context, region: region)
            try context.save()
            return
        }
        guard let url = region.seedURL(in: bundle) else {
            // Viagem criada no app: nasce vazia (prompt 28 §3.8). De fábrica sem seed é erro de bundle.
            if region.trip.isBuiltIn { Log.data.error("seed-\(region.rawValue, privacy: .public).json não está no bundle") }
            try context.save()
            return
        }
        let board = try BoardCodec.decode(Data(contentsOf: url))
        let summary = try BoardCodec(context: context, region: region).import(board: board)
        let settings = context.settings(for: region)
        settings.seenSeedIds = board.places.map(\.id)
        settings.seedListOrder = board.lists.map(\.id)
        WalletStarter.ensure(context, region: region)
        try context.save()
        Log.data.info("seed \(region.rawValue, privacy: .public): \(summary.description, privacy: .public)")
    }

    /// `Settings(region:)` só conhece o câmbio do iene; a Itália começa com o câmbio de referência do euro.
    /// Só enquanto o usuário não salvou um câmbio dele (`fxDate == nil`) e o valor ainda é o 1 do construtor.
    // TODO(v8:E): `Settings.init` (Must/Models) poderia usar `region.defaultFXRate` direto; aí isto some.
    static func applyRegionDefaults(_ settings: Settings, region: Region) {
        if region.hasFX, settings.fxDate == nil, settings.fxRate == 1, region.defaultFXRate != 1 {
            settings.fxRate = region.defaultFXRate
        }
    }

    /// O que ainda está igual ao seed antigo acompanha o novo (prompt 13): "see" violeta com museus vira
    /// templos/mirantes em teal, os museus que continuam nele vão pra art, e as listas seguem a ordem do design.
    /// Só mexe no que bate exatamente com o padrão antigo; o que o usuário mudou fica. Roda sem custo se nada bate.
    static func realign(_ context: ModelContext, lists: [MustList], seed: Board) throws {
        var changed = false
        let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let see = byId["see"], see.colorRaw == MustColor.see.rawValue, see.iconRaw == MustIcon.museu.rawValue,
           let s = seed.lists.first(where: { $0.id == "see" }), s.color != .see,
           seed.places.allSatisfy({ $0.listId == "see" || byId[$0.listId] != nil }) {
            // Só quando as listas de destino (art…) já existem: recolore e move de uma vez.
            see.color = s.color
            if let icon = s.icon.flatMap(MustIcon.init(rawValue:)) { see.icon = icon }
            see.subs = s.sub ?? see.subs
            let seedPlaces = Dictionary(seed.places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for place in see.places {
                guard let sp = seedPlaces[place.id], sp.listId != "see", let target = byId[sp.listId] else { continue }
                place.list = target
                place.sub = sp.sub
            }
            changed = true
        }
        // Ordem do design pras listas do seed, uma vez só (depois a ordem é do usuário: editar lista › ordem).
        // As criadas pelo usuário vêm depois, na ordem em que estavam.
        let order = seed.lists.map(\.id)
        let settings = try context.fetch(FetchDescriptor<Settings>()).first
        if settings?.seedListOrder.isEmpty ?? true {
            let custom = lists.filter { !order.contains($0.id) }.sorted { $0.order < $1.order }
            for list in lists { if let i = order.firstIndex(of: list.id) { list.order = i } }
            for (i, list) in custom.enumerated() { list.order = order.count + i }
            // Só marca quando todas as listas do seed já existem: mergeSeed alinha antes e depois de importar as novas.
            if order.allSatisfy({ id in lists.contains { $0.id == id } }) { settings?.seedListOrder = order }
            changed = true
        }
        if changed {
            try context.save()
            Log.data.info("board alinhado com o seed novo")
        }
    }

    /// Board já existente: recebe o que o seed ganhou depois (listas, lugares, eventos), uma vez só.
    /// Nada do usuário é sobrescrito; lugar que ele apagou não volta (o id fica em `seenSeedIds`).
    static func mergeSeed(_ context: ModelContext, region: Region, bundle: Bundle) throws {
        guard let url = region.seedURL(in: bundle) else { return }
        let seed = try BoardCodec.decode(Data(contentsOf: url))
        let settings = context.settings(for: region)
        let seen = Set(settings.seenSeedIds)
        let seedIds = Set(seed.places.map(\.id))
        let lists = try context.fetch(FetchDescriptor<MustList>())
        try realign(context, lists: lists, seed: seed)
        guard !seedIds.isSubset(of: seen) else { return }

        for list in lists {
            guard let s = seed.lists.first(where: { $0.id == list.id }) else { continue }
            // Lista antiga com o mesmo id ganha o tipo (photo/art/sport) e as sub-listas novas.
            if list.kind == .place, let kind = s.kind, kind != .place { list.kind = kind }
            let extra = (s.sub ?? []).filter { !list.subs.contains($0) }
            if !extra.isEmpty { list.subs += extra }
        }
        let listIds = Set(lists.map(\.id))
        let known = Set(try context.fetch(FetchDescriptor<Place>()).map(\.id))
        let places = seed.places.filter { !seen.contains($0.id) && !known.contains($0.id) }
        let events = try context.fetch(FetchDescriptor<TripEvent>())
        let newEvents = (seed.events ?? []).filter { e in !events.contains { $0.title == e.title && abs($0.at.timeIntervalSince(e.at)) < 60 } }
        let board = Board(version: seed.version, region: seed.region, trip: nil, budget: nil,
                          lists: seed.lists.filter { !listIds.contains($0.id) },
                          places: places, expenses: nil, days: nil, events: newEvents)
        if !board.lists.isEmpty || !board.places.isEmpty || !newEvents.isEmpty {
            let summary = try BoardCodec(context: context, region: region).import(board: board)
            Log.data.info("seed novo \(region.rawValue, privacy: .public): \(summary.description, privacy: .public)")
        }
        settings.seenSeedIds = Array(seen.union(seedIds)).sorted()
        try context.save()
        // As listas novas (art…) já existem: agora dá pra mover os museus e ordenar.
        try realign(context, lists: try context.fetch(FetchDescriptor<MustList>()), seed: seed)
    }
}
