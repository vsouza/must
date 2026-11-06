import Foundation
import OSLog

/// Registro das viagens (prompt 28 §3.2): `trips.json` na mesma pasta dos `.store` (App Group). Não é SwiftData, então
/// não tem migração de schema. Na primeira abertura depois do update é semeado com as três de fábrica
/// (`BuiltInTrip`: `bh`, `jp`, `it`) e os `.store` delas continuam com o mesmo nome e conteúdo.
///
/// Arquivo pequeno: leitura e gravação síncronas, atômicas. Arquivo ilegível nunca é sobrescrito: o app segue com as
/// de fábrica em memória e loga.
final class TripRegistry: @unchecked Sendable {
    static let fileName = "trips.json"

    struct File: Codable, Sendable {
        var version: Int
        var trips: [Trip]
    }

    let url: URL
    private let lock = NSLock()
    private var all: [Trip]
    /// `false` quando o arquivo existe mas não deu pra ler (aí nada é gravado por cima).
    private let writable: Bool

    init(directory: URL) {
        url = directory.appending(path: Self.fileName)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path()) {
            do {
                let file = try Self.decoder.decode(File.self, from: Data(contentsOf: url))
                all = file.trips
                writable = true
            } catch {
                Log.data.error("trips.json ilegível: \(error.localizedDescription, privacy: .public); usando as de fábrica")
                all = BuiltInTrip.all
                writable = false
            }
        } else {
            all = BuiltInTrip.all
            writable = true
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            persist()
            Log.data.info("trips.json semeado com bh, jp, it")
        }
        KnownTrips.shared.publish(all)
    }

    // MARK: Leitura

    /// Todas, inclusive arquivadas, na ordem do registro.
    var trips: [Trip] { lock.withLock { all } }

    /// As que aparecem em Minhas viagens (sem as arquivadas).
    var visible: [Trip] { trips.filter { !$0.archived } }

    func trip(_ id: TripID) -> Trip? { lock.withLock { all.first { $0.id == id } } }

    // MARK: Escrita

    /// Insere ou troca pelo `id`.
    func upsert(_ trip: Trip) {
        lock.withLock {
            if let i = all.firstIndex(where: { $0.id == trip.id }) { all[i] = trip } else { all.append(trip) }
        }
        persist()
    }

    /// Arquivar: some da lista, o `.store` fica.
    func setArchived(_ id: TripID, _ archived: Bool) {
        guard var trip = trip(id) else { return }
        trip.archived = archived
        upsert(trip)
    }

    /// Tira do registro (quem apaga o `.store` é o `TripStore`).
    func remove(_ id: TripID) {
        lock.withLock { all.removeAll { $0.id == id } }
        persist()
    }

    private func persist() {
        let snapshot = lock.withLock { all }
        KnownTrips.shared.publish(snapshot)
        guard writable else { return }
        do {
            let data = try Self.encoder.encode(File(version: 1, trips: snapshot))
            try data.write(to: url, options: .atomic)
        } catch {
            Log.data.error("falha gravando trips.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Viagens conhecidas no processo (o último registro lido ou gravado). `Region(rawValue:)` e o decode de um id de
/// viagem criada no app acham a viagem por aqui sem abrir o arquivo de novo.
final class KnownTrips: @unchecked Sendable {
    static let shared = KnownTrips()

    private let lock = NSLock()
    private var byId: [TripID: Trip] = [:]

    func publish(_ trips: [Trip]) {
        lock.withLock { for trip in trips { byId[trip.id] = trip } }
    }

    func trip(_ id: TripID) -> Trip? { lock.withLock { byId[id] } }

    func forget(_ id: TripID) { _ = lock.withLock { byId.removeValue(forKey: id) } }
}
