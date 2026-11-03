import Foundation
import SwiftData

/// Fila de saída (prompt 18 · A.4): o que depende de rede e foi pedido sem rede fica gravado e é reenviado
/// quando volta a internet (e na abertura). Todo envio passa pelos guardas dos serviços: `FlightPolicy`, cota e disjuntor.
@MainActor
enum Outbox {
    static let maxAttempts = 6

    /// Entre tentativas que falharam: 1, 2, 4… min, teto de 30 min.
    static func backoff(attempts: Int) -> TimeInterval {
        min(30 * 60, 60 * pow(2, Double(max(0, attempts - 1))))
    }

    static func undone(_ context: ModelContext) -> [OutboxItem] {
        let all = (try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { !$0.done }))) ?? []
        return all.sorted { $0.createdAt < $1.createdAt }
    }

    /// "N esperando internet" (Adicionar).
    static func waitingCount(_ context: ModelContext) -> Int { undone(context).count }

    /// Um item por (tipo, ref): pedir de novo não duplica.
    @discardableResult
    static func enqueue(_ kind: OutboxKind, ref: String, context: ModelContext, now: Date = AppClock.now) -> OutboxItem {
        if let existing = undone(context).first(where: { $0.kind == kind.rawValue && $0.ref == ref }) { return existing }
        let item = OutboxItem(kind: kind, ref: ref, now: now)
        context.insert(item)
        try? context.save()
        return item
    }

    /// Leitura de link já feita na fila (a legenda guardada), pra Adicionar não pedir a rede de novo.
    static func readyCaption(for url: String, context: ModelContext) -> (item: OutboxItem, caption: Caption)? {
        let done = (try? context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.done }))) ?? []
        for item in done where item.ref == url && item.outboxKind == .readLink {
            if let data = item.result, let caption = (try? JSONDecoder().decode(StoredCaption.self, from: data))?.caption {
                return (item, caption)
            }
        }
        return nil
    }

    /// Reenvia o que está na hora (`nextTry` vencido). Sem rede não faz nada. Devolve quantos terminaram.
    @discardableResult
    static func drain(context: ModelContext, region: Region, now: Date = AppClock.now,
                      isOnline: @Sendable () -> Bool = { Connectivity.current != .offline },
                      flightSource: (any FlightStatusProviding)? = FlightStatusUpdater.activeSource(),
                      fetchCaption: @Sendable (String) async throws -> Caption = readLinkCaption,
                      places: (any PlacesProviding)? = nil) async -> Int {
        guard isOnline() else { return 0 }
        var finished = 0
        for item in undone(context) where item.nextTry <= now {
            switch item.outboxKind {
            case .flightStatus:
                guard let flight = findFlight(item.ref, context: context) else {
                    item.done = true
                    item.lastError = "voo apagado"
                    finished += 1
                    continue
                }
                // A política de voo decide se gasta consulta agora (fora da janela, o item termina sem chamada).
                let outcome = await FlightStatusUpdater.run(flight, context: context, now: now, region: region, source: flightSource)
                if outcome.offline {
                    reschedule(item, now: now, error: "sem internet", countsAttempt: false)
                } else {
                    item.done = true
                    finished += 1
                }
            case .readLink:
                do {
                    let caption = try await fetchCaption(item.ref)
                    item.result = try? JSONEncoder().encode(StoredCaption(caption))
                    item.lastError = nil
                    item.done = true
                    finished += 1
                } catch {
                    if isOffline(error) {
                        reschedule(item, now: now, error: "sem internet", countsAttempt: false)
                    } else if HTTP.isTransient(error) || error is URLError {
                        reschedule(item, now: now, error: error.localizedDescription, countsAttempt: true)
                    } else {
                        // Página sem legenda, link recusado: não adianta tentar de novo.
                        item.done = true
                        item.lastError = error.localizedDescription
                        finished += 1
                    }
                }
            case .conferText:
                // Texto colado sem rede (prompt 18 · E.23): confere os lugares no Places quando a rede volta.
                guard let places, places.isConfigured, DevOverrides.liveData else { continue }
                let pending = (try? JSONDecoder().decode([ConferredPlace].self, from: item.result ?? Data())) ?? []
                let conferred = await TextConference.conference(pending, provider: places, near: region.defaultCenter)
                item.result = try? JSONEncoder().encode(conferred)
                item.lastError = nil
                item.done = true
                finished += 1
            case nil:
                item.done = true
                finished += 1
            }
        }
        try? context.save()
        return finished
    }

    /// Lê a legenda de um link colado (o mesmo caminho do Adicionar).
    nonisolated static func readLinkCaption(_ text: String) async throws -> Caption {
        try await CaptionFetcher().fetch(LinkResolver.resolve(text))
    }

    static func isOffline(_ error: Error) -> Bool {
        if (error as? ServiceError) == .offline || (error as? CaptionError) == .offline { return true }
        return (error as? URLError)?.code == .notConnectedToInternet
    }

    private static func reschedule(_ item: OutboxItem, now: Date, error: String, countsAttempt: Bool) {
        if countsAttempt { item.attempts += 1 }
        item.lastError = error
        if item.attempts >= maxAttempts {
            item.done = true
            return
        }
        // Sem rede não conta tentativa: a fila tenta de novo logo que a rede voltar.
        item.nextTry = now.addingTimeInterval(countsAttempt ? backoff(attempts: item.attempts) : 60)
    }

    private static func findFlight(_ id: String, context: ModelContext) -> Flight? {
        try? context.fetch(FetchDescriptor<Flight>(predicate: #Predicate { $0.id == id })).first
    }
}

/// Legenda guardada no `OutboxItem.result` (`Caption` não é Codable).
struct StoredCaption: Codable, Sendable {
    var source: String
    var title: String?
    var text: String
    var url: String?

    init(_ caption: Caption) {
        source = caption.source.rawValue
        title = caption.title
        text = caption.text
        url = caption.url?.absoluteString
    }

    var caption: Caption? {
        guard let source = LinkSource(rawValue: source) else { return nil }
        return Caption(source: source, title: title, text: text, url: url.flatMap(URL.init(string:)))
    }
}
