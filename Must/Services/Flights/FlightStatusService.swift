import Foundation
import OSLog
import SwiftData

// Status de voo (prompt 15 · C). Só AeroDataBox (RapidAPI, plano grátis): 400 unidades/mês, 2 por consulta.
// Regras (CLAUDE.md "Status de voo"): consulta só de 24 h antes da partida até o pouso, no máximo a cada 30 min por
// trecho (cache no próprio trecho), nunca em background ou loop; só quando Voos ou Hoje é aberto ou o usuário puxa a tela.
// Sem chave ou sem cota, o trecho mostra o horário programado, sem erro.

/// O que a API disse sobre um trecho. Campo que não veio fica nil.
struct FlightStatusReport: Equatable, Sendable {
    var status: FlightStatus?
    /// Partida revista (só quando a companhia mudou o horário).
    var departs: Date?
    var arrives: Date?
    var terminal: String?
    var gate: String?
}

/// Quem entrega o status de um trecho. O real é `AeroDataBoxService`; a fake vem só no build de debug (prints).
protocol FlightStatusProviding: Sendable {
    func report(number: String, departureIATA: String, day: String) async throws -> FlightStatusReport?
}

/// Resposta de `GET /flights/number/{number}/{date}` (AeroDataBox). Tolerante: campo ausente vira nil, não erro.
enum AeroDataBoxParser {
    /// Escolhe o voo que sai do aeroporto pedido (a API devolve uma lista, às vezes com voos de outros trechos).
    static func parse(_ data: Data, departureIATA: String) throws -> FlightStatusReport? {
        let json = try JSONSerialization.jsonObject(with: data)
        let items: [[String: Any]]
        if let array = json as? [[String: Any]] {
            items = array
        } else if let one = json as? [String: Any] {
            items = [one]
        } else {
            throw ServiceError.decoding("status de voo")
        }
        let wanted = departureIATA.uppercased()
        let item = items.first { iata(in: $0["departure"]) == wanted } ?? items.first
        guard let item else { return nil }

        let departure = item["departure"] as? [String: Any] ?? [:]
        let arrival = item["arrival"] as? [String: Any] ?? [:]
        let scheduled = localTime(departure["scheduledTime"])
        let revised = localTime(departure["revisedTime"])
        return FlightStatusReport(
            status: status(item["status"] as? String, scheduled: scheduled, revised: revised),
            departs: revised,
            arrives: localTime(arrival["revisedTime"]) ?? localTime(arrival["scheduledTime"]),
            terminal: text(departure["terminal"]),
            gate: text(departure["gate"])
        )
    }

    /// "Expected" · "Departed" · "Arrived" · "Canceled" · "Delayed" … → status do app.
    static func status(_ raw: String?, scheduled: Date?, revised: Date?) -> FlightStatus? {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return nil }
        if raw.hasPrefix("cancel") { return .cancelled }
        switch raw {
        case "arrived": return .landed
        case "departed", "enroute", "en route": return .departed
        case "boarding", "gateclosed", "gate closed": return .boarding
        case "delayed": return .delayed
        case "expected":
            if let revised, let scheduled, revised.timeIntervalSince(scheduled) >= 300 { return .delayed }
            return .onTime
        default: return .scheduled
        }
    }

    private static func iata(in value: Any?) -> String? {
        ((value as? [String: Any])?["airport"] as? [String: Any])?["iata"] as? String
    }

    private static func text(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `{"local": "2026-11-02 23:40-03:00", "utc": "2026-11-03 02:40Z"}` → Date. Tenta o local, depois o UTC.
    static func localTime(_ value: Any?) -> Date? {
        guard let object = value as? [String: Any] else { return nil }
        if let local = object["local"] as? String, let date = date(local) { return date }
        if let utc = object["utc"] as? String, let date = date(utc) { return date }
        return nil
    }

    private static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for format in ["yyyy-MM-dd HH:mmxxx", "yyyy-MM-dd HH:mmxx", "yyyy-MM-dd HH:mm'Z'", "yyyy-MM-dd HH:mm"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = format.hasSuffix("'Z'") || format == "yyyy-MM-dd HH:mm" ? TimeZone(identifier: "UTC") : nil
            f.dateFormat = format
            if let date = f.date(from: trimmed) { return date }
        }
        return nil
    }
}

/// Cota mensal da AeroDataBox (contador em UserDefaults, como o `PlacesUsage`). Vira mês a mês.
enum FlightQuota {
    /// Plano grátis.
    static let planLimit = 400
    /// Para em 380 (margem pra não estourar por uma consulta a mais).
    static let monthlyCap = 380
    /// Cada consulta por número de voo custa 2 unidades.
    static let unitsPerCall = 2

    private static func month(_ now: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func usedKey(_ now: Date) -> String { "aerodatabox.units.\(month(now))" }
    static func blockedKey(_ now: Date) -> String { "aerodatabox.blocked.\(month(now))" }

    static func used(now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: usedKey(now))
    }

    /// 429 ou 403 da API (cota esgotada ou chave recusada): para até o mês seguinte.
    static func isBlocked(now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: blockedKey(now))
    }

    static func record(units: Int = unitsPerCall, now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(used(now: now, defaults: defaults) + units, forKey: usedKey(now))
    }

    static func block(now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: blockedKey(now))
    }
}

/// Política de consulta (pura, testável). Não chama nada: diz se este trecho pode gastar uma consulta agora.
enum FlightPolicy {
    /// Só a partir de 24 h antes da partida.
    static let window: TimeInterval = 24 * 3600
    /// No máximo uma consulta a cada 30 min por trecho.
    static let minInterval: TimeInterval = 30 * 60

    static func shouldQuery(_ leg: FlightSegment, now: Date, hasSource: Bool, usedThisMonth: Int, blocked: Bool) -> Bool {
        guard hasSource, !blocked, usedThisMonth < FlightQuota.monthlyCap else { return false }
        guard leg.status != .landed, leg.status != .cancelled else { return false }
        // Antes da janela: o horário programado basta.
        guard now >= leg.departs.addingTimeInterval(-window) else { return false }
        // Depois do pouso: nada mais muda.
        guard now <= leg.landsEstimate.addingTimeInterval(3600) else { return false }
        // Cache: a última consulta vale por 30 min.
        if let fetched = leg.statusFetchedAt, now.timeIntervalSince(fetched) < minInterval { return false }
        return true
    }
}

/// Consulta real: AeroDataBox pela RapidAPI. Conta a cota e bloqueia no 429/403.
struct AeroDataBoxService: FlightStatusProviding {
    static let host = "aerodatabox.p.rapidapi.com"
    /// Cobra por chamada: nada de repetir (retries 0) e sem disjuntor (a cota e o 429/403 já são o freio).
    var http = HTTP(retries: 0, breaker: nil)

    func report(number: String, departureIATA: String, day: String) async throws -> FlightStatusReport? {
        guard let key = Secrets.aerodataboxKey else { throw ServiceError.missingKey(Secrets.Key.aerodatabox.rawValue) }
        let compact = FlightRules.compactNumber(number)
        guard let url = URL(string: "https://\(Self.host)/flights/number/\(compact)/\(day)") else { return nil }
        do {
            let data = try await http.get(url, headers: ["X-RapidAPI-Key": key, "X-RapidAPI-Host": Self.host], service: "AeroDataBox")
            FlightQuota.record()
            return try AeroDataBoxParser.parse(data, departureIATA: departureIATA)
        } catch ServiceError.http(let code, let body) {
            // A chamada foi cobrada (ou recusada): conta, e no 429/403 para até o mês seguinte.
            FlightQuota.record()
            if code == 429 || code == 403 { FlightQuota.block() }
            throw ServiceError.http(code, body)
        }
    }
}

#if DEBUG
/// `-debugFlight fake` (prints do simulador): status de mentira, sem gastar cota.
struct FakeFlightStatusService: FlightStatusProviding {
    func report(number: String, departureIATA: String, day: String) async throws -> FlightStatusReport? {
        FlightStatusReport(status: .onTime, departs: nil, arrives: nil, terminal: "3", gate: "B12")
    }
}
#endif

/// Orquestra a atualização de um voo: escolhe os trechos que a política manda consultar e grava o cache no trecho.
@MainActor
enum FlightStatusUpdater {
    /// Fonte ativa: a fake no `-debugFlight fake`; a real com chave; nil sem chave (só o programado).
    static func activeSource() -> (any FlightStatusProviding)? {
        #if DEBUG
        if DebugFlags.string("debugFlight") == "fake" { return FakeFlightStatusService() }
        #endif
        return Secrets.aerodataboxKey == nil ? nil : AeroDataBoxService()
    }

    /// Consulta os trechos devidos (no máximo um por trecho). Devolve quantas consultas foram feitas.
    /// Sem rede, o voo entra na fila de saída (`Outbox`) e a consulta não é marcada: a próxima tentativa sai quando a rede voltar.
    @discardableResult
    static func refresh(_ flight: Flight, context: ModelContext, now: Date = AppClock.now, region: Region,
                        source: (any FlightStatusProviding)? = activeSource()) async -> Int {
        let outcome = await run(flight, context: context, now: now, region: region, source: source)
        if outcome.offline { Outbox.enqueue(.flightStatus, ref: flight.id, context: context, now: now) }
        return outcome.calls
    }

    struct Outcome: Equatable {
        var calls = 0
        /// Alguma consulta devida não saiu por falta de rede.
        var offline = false
    }

    /// O mesmo que `refresh`, sem mexer na fila. Usado pela fila de saída (que também respeita `FlightPolicy`).
    static func run(_ flight: Flight, context: ModelContext, now: Date = AppClock.now, region: Region,
                    source: (any FlightStatusProviding)?) async -> Outcome {
        var legs = flight.legs
        var outcome = Outcome()
        var changed = false
        for index in legs.indices {
            let leg = legs[index]
            let due = FlightPolicy.shouldQuery(leg, now: now, hasSource: source != nil,
                                               usedThisMonth: FlightQuota.used(now: now), blocked: FlightQuota.isBlocked(now: now))
            guard due, let source else { continue }
            let day = FlightRules.localDayString(leg.departsNow, iata: leg.from, fallback: region.timeZone)
            do {
                let report = try await source.report(number: leg.number, departureIATA: leg.from, day: day)
                outcome.calls += 1
                changed = true
                if let report {
                    legs[index].status = report.status ?? legs[index].status
                    legs[index].revisedDeparts = report.departs
                    legs[index].revisedArrives = report.arrives
                    legs[index].terminal = report.terminal ?? legs[index].terminal
                    legs[index].gate = report.gate ?? legs[index].gate
                }
                legs[index].statusFetchedAt = now
            } catch ServiceError.offline {
                // Nada saiu nem foi cobrado: não marca o trecho (ele continua devido) e para por aqui.
                outcome.offline = true
                break
            } catch {
                // Cota ou chave recusada: o horário programado continua valendo. Não vira erro na tela.
                outcome.calls += 1
                changed = true
                Log.network.info("status de voo indisponível: \(String(describing: error), privacy: .private)")
                legs[index].statusFetchedAt = now
            }
            if FlightQuota.isBlocked(now: now) { break }
        }
        guard changed else { return outcome }
        flight.legs = legs
        try? context.save()
        return outcome
    }
}
