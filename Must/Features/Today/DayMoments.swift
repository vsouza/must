import Foundation

// Lógica pura das telas do dia v8 (prompt 23 §2: capa, Bom dia, Agora, Linha, Ir, Boa noite). Nada aqui lê
// SwiftData nem rede: as telas montam as entradas nos gatilhos (aparecer, minuto, salvar) e só desenham o resultado.

// MARK: - Textos

enum DayText {
    /// "Fuunji · tsukemen" → "Fuunji". O título curto de uma parada (card Agora, pílulas, "e … à noite").
    static func head(_ label: String) -> String {
        let first = label.components(separatedBy: " · ").first ?? label
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// "Sáb · 15 nov" (dia da semana com maiúscula, mês curto, no fuso da região).
    static func dayLine(_ date: Date, region: Region) -> String {
        "\(weekdayShort(date, region: region).capitalizedFirst) · \(region.shortDay(date))"
    }

    /// "sáb" (sem ponto).
    static func weekdayShort(_ date: Date, region: Region) -> String {
        var style = Date.FormatStyle(locale: region.locale, calendar: region.calendar).weekday(.abbreviated)
        style.timeZone = region.timeZone
        return date.formatted(style).replacingOccurrences(of: ".", with: "").lowercased()
    }

    /// Fim de semana (sáb/dom) no calendário da região.
    static func isWeekend(_ date: Date, region: Region) -> Bool {
        let weekday = region.calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Dia da viagem ("dia 3 de 14"): conta do início ao fim da viagem. `nil` fora dela ou sem datas (BH).
    static func tripDay(start: Date?, end: Date?, on date: Date, calendar: Calendar) -> (index: Int, total: Int)? {
        guard let start, let end else { return nil }
        let s = calendar.startOfDay(for: start), e = calendar.startOfDay(for: end), d = calendar.startOfDay(for: date)
        guard s <= d, d <= e else { return nil }
        let total = (calendar.dateComponents([.day], from: s, to: e).day ?? 0) + 1
        let index = (calendar.dateComponents([.day], from: s, to: d).day ?? 0) + 1
        return (index, total)
    }

    /// Céu numa palavra (código WMO do Open-Meteo): "sol", "nublado", "chuva"…
    static func sky(_ code: Int) -> String {
        switch code {
        case 0, 1: "sol"
        case 2: "sol e nuvens"
        case 3: "nublado"
        case 45, 48: "névoa"
        case 51...67, 80...82: "chuva"
        case 71...77, 85, 86: "neve"
        case 95...: "tempestade"
        default: "nublado"
        }
    }

    /// Chuva no código ou na probabilidade (≥ 50 %).
    static func isRainy(_ weather: DayWeather) -> Bool {
        (51...67).contains(weather.code) || (80...82).contains(weather.code) || weather.code >= 95 || weather.precipProb >= 50
    }

    /// Rótulo do tempo da Linha à esquerda do card: "agora", "âncora", "café", "micro", "drink"…
    static func caption(for stop: DayStop, isNow: Bool) -> String {
        if isNow { return "agora" }
        switch stop.kind {
        case .anchor: return "âncora"
        case .micro: return stop.tag?.lowercased() == "café" ? "café" : "micro"
        case .must:
            // "Must drink · vinho de taça" → "drink"
            let note = stop.note.lowercased()
            if note.hasPrefix("must "), let word = note.dropFirst(5).split(whereSeparator: { $0 == " " || $0 == "·" }).first {
                return String(word)
            }
            return "must"
        }
    }

    /// "¥ 11,3k" / "R$ 86" / "€ 64": o gasto grande da Boa noite sem estourar a coluna.
    static func compactMoney(_ value: Double, region: Region) -> (number: String, suffix: String) {
        let symbol = region.currencySymbol
        if value >= 10_000 {
            let k = (value / 1000).formatted(.number.locale(region.locale).precision(.fractionLength(1)))
            return ("\(symbol)\(k)", "k")
        }
        return ("\(symbol)\(region.money(value, symbol: false))", "")
    }
}

extension String {
    /// "sáb" → "Sáb".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Só cash

/// Lugar que só aceita dinheiro: lido do texto (nota da parada, notas do lugar). O board não tem um campo próprio.
enum CashOnly {
    static let markers = ["só cash", "so cash", "cash only", "only cash", "só dinheiro", "somente dinheiro",
                          "apenas dinheiro", "só aceita dinheiro", "solo contanti", "só em dinheiro"]

    static func detect(_ texts: String?...) -> Bool {
        texts.contains { text in
            guard let text = text?.lowercased(), !text.isEmpty else { return false }
            return markers.contains { text.contains($0) }
        }
    }
}

// MARK: - Feito (micro-paradas e paradas do dia)

/// Paradas marcadas como feitas nas telas v8 (Agora ✓, Ir › Cheguei), por dia. Micro-paradas não têm `Place` nem
/// `Stop` no SwiftData, então ficam aqui (UserDefaults, uma chave por dia); lugares do board também ganham 済.
struct DayDoneStore {
    var defaults: UserDefaults = .standard

    static func key(_ day: String) -> String { "v8.done.\(day)" }

    func ids(day: String) -> Set<String> {
        Set(defaults.stringArray(forKey: Self.key(day)) ?? [])
    }

    func mark(_ id: String, day: String, done: Bool = true) {
        var set = ids(day: day)
        if done { set.insert(id) } else { set.remove(id) }
        defaults.set(set.sorted(), forKey: Self.key(day))
    }

    /// Feita no plano (motor) ou marcada aqui.
    func isDone(_ stop: DayStop, day: String) -> Bool { stop.done || ids(day: day).contains(stop.id) }
}

// MARK: - Linha do dia

/// Estado de uma parada na Linha: feita (50 %), agora (laranja) ou ainda por vir.
enum LinhaStopState: Equatable {
    case done, now, upcoming

    static func of(_ stop: DayStop, nowId: String?, doneIds: Set<String>) -> LinhaStopState {
        if stop.done || doneIds.contains(stop.id) { return .done }
        if stop.id == nowId { return .now }
        return .upcoming
    }
}

extension DayPlan {
    /// Posição (de 1) da parada no dia.
    func position(of stop: DayStop) -> Int? { stops.firstIndex { $0.id == stop.id }.map { $0 + 1 } }

    var microCount: Int { stops.filter { $0.kind == .micro }.count }

    /// "9 paradas" / "3 âncoras · 4 micro".
    var countLine: String { stops.count == 1 ? "1 parada" : "\(stops.count) paradas" }
    var anchorLine: String {
        let a = anchors.count
        return (a == 1 ? "1 âncora" : "\(a) âncoras") + " · \(microCount) micro"
    }
}

// MARK: - Bom dia: "Antes de sair"

/// Um item do checklist da manhã (e chip da Boa noite pra amanhã).
struct MorningItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case passport, transitCard, cash, umbrella }
    var kind: Kind
    /// "Suica ¥ 1.240 · recarregar"
    var text: String
    /// Chip curto ("recarregar Suica").
    var short: String
    var id: String { kind.rawValue }
}

/// Checklist gerado do dia (prompt 23 §2 · 02): passaporte se há ingresso/tax-free (fora do Brasil), cartão de
/// transporte abaixo de ¥ 1.500 pelo saldo anotado na Carteira (Japão), dinheiro se há lugar só-cash, guarda-chuva se chuva.
enum MorningChecklist {
    /// Abaixo disso, a Suica pede recarga (uma passagem de metrô + um konbini).
    static let transitCardFloor: Double = 1_500

    struct TransitCard: Sendable { var name: String; var balance: Double }

    static func items(plan: DayPlan?, placeNotes: [String: String] = [:], transitCard: TransitCard?,
                      weather: DayWeather?, region: Region) -> [MorningItem] {
        var items: [MorningItem] = []
        let stops = plan?.stops ?? []

        if region != .bh {
            let ticket = stops.contains { $0.kind == .anchor && ($0.tag?.uppercased() == "QR" || $0.note.lowercased().contains("ingresso")) }
            let taxFree = stops.contains { ($0.label + " " + $0.note).lowercased().contains("tax-free") }
            var reasons: [String] = []
            if ticket { reasons.append("ingresso") }
            if taxFree { reasons.append("tax-free") }
            if !reasons.isEmpty {
                items.append(MorningItem(kind: .passport, text: "Passaporte (\(reasons.joined(separator: " + ")))", short: "passaporte"))
            }
        }

        if region == .jp, let card = transitCard, card.balance < transitCardFloor {
            items.append(MorningItem(kind: .transitCard, text: "\(card.name) \(region.money(card.balance)) · recarregar",
                                     short: "recarregar \(card.name)"))
        }

        if let cash = stops.first(where: { CashOnly.detect($0.label, $0.note, $0.placeId.flatMap { placeNotes[$0] }) }) {
            items.append(MorningItem(kind: .cash, text: "Dinheiro: \(DayText.head(cash.label)) é só cash", short: "levar dinheiro"))
        }

        if let weather, DayText.isRainy(weather) {
            items.append(MorningItem(kind: .umbrella, text: "Guarda-chuva · \(weather.precipProb)% de chuva", short: "guarda-chuva"))
        }
        return items
    }

    /// Chave do que já foi marcado no checklist de um dia (UserDefaults).
    static func checkedKey(_ day: String) -> String { "v8.morning.\(day)" }
}

// MARK: - Boa noite

/// O resumo do fim do dia (prompt 23 §2 · 14).
struct NightSummary: Equatable, Sendable {
    var done: Int
    var total: Int
    /// Estimativa: minutos das pernas a pé × 75 m + 400 m por perna de trem/metrô/ônibus (estação). O app não conta passos.
    var walkKm: Double
    var spent: Double
    var budget: Double
    var sentence: String

    /// % do orçamento gasto; `nil` sem orçamento.
    var percent: Int? { budget > 0 ? Int((spent / budget * 100).rounded()) : nil }

    static let metersPerWalkMinute: Double = 75
    static let metersPerStation: Double = 400

    static func build(plan: DayPlan, doneIds: Set<String>, spent: Double) -> NightSummary {
        let isDone: (DayStop) -> Bool = { $0.done || doneIds.contains($0.id) }
        let done = plan.stops.filter(isDone).count
        let total = plan.stops.count
        let walk = plan.legs.reduce(0.0) { sum, leg in
            switch leg.mode {
            case .walk: sum + Double(leg.minutes) * metersPerWalkMinute
            case .train, .metro, .bus: sum + metersPerStation
            case .taxi: sum
            }
        }
        let skipped = plan.stops.filter { !isDone($0) }
        var sentence = done == total ? "Todas as \(total) paradas." : "\(done) das \(total) paradas."
        if skipped.count == 1, let one = skipped.first {
            let name = one.kind == .micro ? DayText.head(one.label).split(separator: " ").first.map(String.init)?.lowercased() ?? "" : DayText.head(one.label)
            sentence += " Ficou de fora: \(name)."
        } else if skipped.count > 1, done > 0 {
            sentence += " \(skipped.count) ficaram pra outro dia."
        }
        return NightSummary(done: done, total: total, walkKm: walk / 1000, spent: spent, budget: plan.budget, sentence: sentence)
    }

    /// Chave da linha do diário de um dia (UserDefaults; o modelo SwiftData não muda nesta rodada).
    static func diaryKey(_ day: String) -> String { "v8.diary.\(day)" }
    /// Dia fechado ("Fechar o dia").
    static func closedKey(_ day: String) -> String { "v8.closed.\(day)" }
}
