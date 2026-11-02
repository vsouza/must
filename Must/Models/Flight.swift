import Foundation
import SwiftData

// Voos da viagem (prompt 15 · C). Um `Flight` é uma reserva (PNR) com as pernas (conexões), a franquia e o checklist.
// Pernas e checklist ficam como JSON (como `Ticket` no `Place`); o board exporta em `flights`. Nada disso vai pro Wallet.

/// Situação de um trecho. "Programado" é o padrão; o resto vem do AeroDataBox quando há chave e cota.
enum FlightStatus: String, Codable, CaseIterable, Sendable {
    case scheduled, onTime, delayed, boarding, departed, landed, cancelled

    var label: String {
        switch self {
        case .scheduled: "programado"
        case .onTime: "no horário"
        case .delayed: "atrasado"
        case .boarding: "embarcando"
        case .departed: "decolou"
        case .landed: "pousou"
        case .cancelled: "cancelado"
        }
    }

    /// Verde quando está tudo certo, âmbar quando muda o que você tem que fazer.
    var isAlert: Bool { self == .delayed || self == .cancelled }
}

/// Fases do checklist, na ordem da tela.
enum ChecklistPhase: String, Codable, CaseIterable, Sendable, Identifiable {
    case h72, bags, airport, arrival

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h72: "72 h antes"
        case .bags: "malas · na véspera"
        case .airport: "aeroporto"
        case .arrival: "ao pousar"
        }
    }
}

/// Um item do checklist de um voo. `auto` = marca sozinho quando a Carteira tem o documento (`autoRule`).
struct ChecklistItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var phase: ChecklistPhase
    var title: String
    var note: String?
    var done: Bool
    /// Lembrete local nesse instante (só o que tem `dueAt` vira notificação).
    var dueAt: Date?
    var auto: Bool
    /// "entryQR" (Visit Japan Web) · "esim". Nil se o item é só manual.
    var autoRule: String?

    init(id: String, phase: ChecklistPhase, title: String, note: String? = nil, done: Bool = false,
         dueAt: Date? = nil, auto: Bool = false, autoRule: String? = nil) {
        self.id = id
        self.phase = phase
        self.title = title
        self.note = note
        self.done = done
        self.dueAt = dueAt
        self.auto = auto
        self.autoRule = autoRule
    }
}

/// Um trecho de voo (uma perna). Conexões são várias pernas do mesmo `Flight`.
struct FlightSegment: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// "LA 8084".
    var number: String
    /// Códigos IATA ("GRU", "HND"). Vazio quando o trecho veio sem rota reconhecível.
    var from: String
    var to: String
    /// Partida programada, no fuso do aeroporto de origem.
    var departs: Date
    /// Chegada programada, no fuso do destino. Nil quando o e-mail não traz.
    var arrives: Date?
    var seat: String?
    var terminal: String?
    var gate: String?
    var status: FlightStatus
    /// Horário revisto pela companhia (AeroDataBox), se houver.
    var revisedDeparts: Date?
    var revisedArrives: Date?
    /// Cache: quando o status foi consultado pela última vez (intervalo mínimo de 30 min).
    var statusFetchedAt: Date?
    /// Observação do board antigo (ex.: "chega no dia seguinte").
    var note: String?

    init(id: String = UUID().uuidString, number: String, from: String, to: String, departs: Date, arrives: Date? = nil,
         seat: String? = nil, terminal: String? = nil, gate: String? = nil, status: FlightStatus = .scheduled,
         revisedDeparts: Date? = nil, revisedArrives: Date? = nil, statusFetchedAt: Date? = nil, note: String? = nil) {
        self.id = id
        self.number = number
        self.from = from
        self.to = to
        self.departs = departs
        self.arrives = arrives
        self.seat = seat
        self.terminal = terminal
        self.gate = gate
        self.status = status
        self.revisedDeparts = revisedDeparts
        self.revisedArrives = revisedArrives
        self.statusFetchedAt = statusFetchedAt
        self.note = note
    }

    /// Tolerante a campos ausentes (JSON antigo ou exportado por outra versão).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        departs = try c.decode(Date.self, forKey: .departs)
        arrives = try c.decodeIfPresent(Date.self, forKey: .arrives)
        seat = try c.decodeIfPresent(String.self, forKey: .seat)
        terminal = try c.decodeIfPresent(String.self, forKey: .terminal)
        gate = try c.decodeIfPresent(String.self, forKey: .gate)
        status = try c.decodeIfPresent(FlightStatus.self, forKey: .status) ?? .scheduled
        revisedDeparts = try c.decodeIfPresent(Date.self, forKey: .revisedDeparts)
        revisedArrives = try c.decodeIfPresent(Date.self, forKey: .revisedArrives)
        statusFetchedAt = try c.decodeIfPresent(Date.self, forKey: .statusFetchedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Partida que vale: a revista pela companhia, se houver.
    var departsNow: Date { revisedDeparts ?? departs }

    /// Chegada que vale (ou a estimativa de 16 h quando o e-mail não trouxe a hora).
    var landsEstimate: Date { (revisedArrives ?? arrives) ?? departs.addingTimeInterval(16 * 3600) }

    var carrierCode: String { FlightRules.carrierCode(of: number) }

    /// "GRU → HND".
    var routeLabel: String { "\(from.isEmpty ? "?" : from) → \(to.isEmpty ? "?" : to)" }
}

/// Reserva de voo (PNR): pernas, franquia e checklist. Uma por PNR (ou por trecho solto do board antigo).
@Model
final class Flight {
    @Attribute(.unique) var id: String = UUID().uuidString
    /// Localizador da reserva ("QX7R2A"). Vazio = não lido.
    var pnr: String = ""
    /// Nome da companhia ("LATAM"), a partir do número do primeiro trecho.
    var carrier: String = ""
    /// Modelo do checklist: "intl-japan" ou "domestic-br" (`FlightRules.templateKey`).
    var template: String = ""
    /// Franquia de malas despachadas (kg) e de bagagem de mão (kg). Nil = não informado.
    var checkedKg: Int?
    var cabinKg: Int?
    var legsData: Data = Data("[]".utf8)
    var checklistData: Data = Data("[]".utf8)
    /// PDF da reserva em `TicketFiles` (proteção completa). Nil se não há arquivo.
    var attachmentName: String?
    var order: Int = 0
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, pnr: String = "", carrier: String = "", template: String = "",
         checkedKg: Int? = nil, cabinKg: Int? = nil, legs: [FlightSegment] = [], checklist: [ChecklistItem] = [],
         attachmentName: String? = nil, order: Int = 0, createdAt: Date = AppClock.now) {
        self.attachmentName = attachmentName
        self.id = id
        self.pnr = pnr
        self.carrier = carrier
        self.template = template
        self.checkedKg = checkedKg
        self.cabinKg = cabinKg
        self.legsData = (try? JSONEncoder.board(timeZone: .gmt).encode(legs)) ?? Data("[]".utf8)
        self.checklistData = (try? JSONEncoder.board(timeZone: .gmt).encode(checklist)) ?? Data("[]".utf8)
        self.order = order
        self.createdAt = createdAt
    }

    var legs: [FlightSegment] {
        get { (try? JSONDecoder.board.decode([FlightSegment].self, from: legsData)) ?? [] }
        set { legsData = (try? JSONEncoder.board(timeZone: .gmt).encode(newValue)) ?? Data("[]".utf8) }
    }

    var checklist: [ChecklistItem] {
        get { (try? JSONDecoder.board.decode([ChecklistItem].self, from: checklistData)) ?? [] }
        set { checklistData = (try? JSONEncoder.board(timeZone: .gmt).encode(newValue)) ?? Data("[]".utf8) }
    }

    var firstLeg: FlightSegment? { legs.first }
    var lastLeg: FlightSegment? { legs.last }

    /// Partida do primeiro trecho.
    var departs: Date? { legs.first?.departsNow }

    /// Terminou: pousou (ou passou a estimativa de chegada do último trecho).
    func isOver(now: Date) -> Bool {
        guard let last = legs.last else { return true }
        return last.status == .landed || now > last.landsEstimate.addingTimeInterval(3600)
    }

    var checklistDone: Int { checklist.filter(\.done).count }

    /// "GRU → DOH → HND" (as pernas em ordem).
    var routeLabel: String {
        guard let first = legs.first else { return "" }
        return ([first.from] + legs.map(\.to)).joined(separator: " → ")
    }
}

extension ModelContext {
    /// Reservas de voo da região, na ordem da viagem (primeiro trecho).
    func flights() -> [Flight] {
        let all = (try? fetch(FetchDescriptor<Flight>())) ?? []
        return all.sorted { ($0.departs ?? .distantFuture, $0.order) < ($1.departs ?? .distantFuture, $1.order) }
    }
}

/// Regras de voo (puras, testáveis): modelo do checklist, carrier, chegada ao aeroporto, legado do board.
enum FlightRules {
    static let carriers: [String: String] = [
        "LA": "LATAM", "G3": "Gol", "AD": "Azul", "JJ": "TAM", "AV": "Avianca", "AA": "American", "UA": "United",
        "DL": "Delta", "AF": "Air France", "KL": "KLM", "TP": "TAP", "BA": "British Airways", "LH": "Lufthansa",
        "QR": "Qatar Airways", "EK": "Emirates", "TK": "Turkish", "KE": "Korean Air", "CX": "Cathay Pacific",
        "JL": "JAL", "NH": "ANA",
    ]

    /// "LA 8084" → "LA"; "LA8084" → "LA".
    static func carrierCode(of number: String) -> String {
        let trimmed = number.trimmingCharacters(in: .whitespaces).uppercased()
        return String(trimmed.prefix(while: { $0.isLetter || $0.isNumber }).prefix(2).filter(\.isLetter))
    }

    static func carrierName(_ code: String) -> String { carriers[code.uppercased()] ?? code }

    /// "LA 8084" → "LA8084" (a forma que a API pede).
    static func compactNumber(_ number: String) -> String {
        number.filter { !$0.isWhitespace }.uppercased()
    }

    /// Modelo do checklist: tudo no Brasil → doméstico; qualquer outro trecho → internacional (os itens do Japão só
    /// entram se algum trecho passa pelo Japão, ver `ChecklistTemplates`).
    static func templateKey(for legs: [FlightSegment]) -> String {
        let allBrazil = !legs.isEmpty && legs.allSatisfy { Airports.isBrazil($0.from) && Airports.isBrazil($0.to) }
        return allBrazil ? "domestic-br" : "intl-japan"
    }

    static func touchesJapan(_ legs: [FlightSegment]) -> Bool {
        legs.contains { Airports.isJapan($0.from) || Airports.isJapan($0.to) }
    }

    /// "internacional + Japão" · "internacional" · "doméstico" (o selo da tela).
    static func templateLabel(_ template: String, legs: [FlightSegment]) -> String {
        if template == "domestic-br" { return "doméstico" }
        return touchesJapan(legs) ? "internacional + Japão" : "internacional"
    }

    /// Chegada ao aeroporto: 3 h antes no internacional, 2 h no doméstico; o deslocamento vem de fora (estimativa 60 min sem rota).
    static func leaveForAirport(departs: Date, international: Bool, travelMinutes: Int = 60) -> Date {
        departs.addingTimeInterval(TimeInterval(-((international ? 180 : 120) + travelMinutes) * 60))
    }

    /// Hora de sair de casa pro voo (com o deslocamento até o aeroporto).
    static func isInternational(_ leg: FlightSegment) -> Bool {
        guard let a = Airports.airport(leg.from), let b = Airports.airport(leg.to) else { return true }
        return a.country != b.country || a.country != "BR"
    }

    /// O horário que veio do e-mail vale no fuso da região; isto põe os mesmos números no fuso do aeroporto de origem.
    static func inAirportZone(_ date: Date, region: Region, iata: String) -> Date {
        guard let zone = Airports.airport(iata)?.timeZone else { return date }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = region.timeZone
        let parts = source.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var target = Calendar(identifier: .gregorian)
        target.timeZone = zone
        return target.date(from: parts) ?? date
    }

    /// "2026-11-11" no fuso dado.
    static func dayKey(_ date: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Data local do aeroporto (a que a API de status pede). Sem aeroporto conhecido, usa o fuso dado.
    static func localDayString(_ date: Date, iata: String, fallback: TimeZone) -> String {
        dayKey(date, zone: Airports.airport(iata)?.timeZone ?? fallback)
    }

    /// Trechos que saem no dia da região (data local do aeroporto de origem), já com a hora de sair pro aeroporto.
    static func dayFlights(_ flights: [Flight], on day: Date, region: Region) -> [DayFlight] {
        let key = dayKey(day, zone: region.timeZone)
        return flights.flatMap { flight in
            flight.legs.filter { localDayString($0.departsNow, iata: $0.from, fallback: region.timeZone) == key }.map { leg in
                DayFlight(number: leg.number, departs: leg.departsNow,
                          leaveAt: leaveForAirport(departs: leg.departsNow, international: isInternational(leg)))
            }
        }.sorted { $0.departs < $1.departs }
    }

    /// Trechos do board antigo (`events` com `kind: flight`): "LA3553 · BH → São Paulo". Sem rota reconhecível, o título fica.
    static func legacyLeg(title: String, at: Date, note: String?) -> FlightSegment {
        let pattern = #"^\s*([A-Za-z0-9]{2})\s?(\d{1,4})\s*[·•\-–]\s*(.+?)\s*(?:→|->)\s*(.+?)\s*$"#
        guard let m = TicketText.first(pattern, in: title) else {
            return FlightSegment(number: title, from: "", to: "", departs: at, note: note)
        }
        let from = airportCode(m[3])
        let to = airportCode(m[4])
        return FlightSegment(number: "\(m[1].uppercased()) \(m[2])", from: from, to: to, departs: at, note: note)
    }

    /// "CNF", "bh", "São Paulo" → código IATA (ou "" se não reconhece).
    static func airportCode(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 3, trimmed.uppercased() == trimmed, Airports.airport(trimmed) != nil { return trimmed }
        return Airports.iata(forCity: trimmed) ?? ""
    }
}

/// Reservas a partir de trechos soltos (board antigo): um trecho continua o anterior quando sai de onde o outro chegou,
/// com menos de 2 dias de espera. O seed de Japão vira uma reserva só: CNF → GRU → JFK → HND.
enum FlightChains {
    static func bookings(from legs: [FlightSegment]) -> [[FlightSegment]] {
        var out: [[FlightSegment]] = []
        for leg in legs.sorted(by: { $0.departs < $1.departs }) {
            if let last = out.last?.last, !leg.from.isEmpty, leg.from == last.to,
               leg.departs.timeIntervalSince(last.departsNow) < 2 * 86_400 {
                out[out.count - 1].append(leg)
            } else {
                out.append([leg])
            }
        }
        return out
    }
}
