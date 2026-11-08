import Foundation
@testable import Must

/// Acerto por campo no corpus de ingressos (prompt 31 · 6). Um campo "não se aplica" quando o gabarito é nil/vazio.
enum TicketField2: String, CaseIterable, Sendable {
    case titulo, data, hora, local, assento, portao, codigo, qr, nome
}

struct TicketScore: Sendable {
    var caseID: String
    var kindLabel: String
    var form: TicketForm
    /// true = acertou, false = errou, ausente = não se aplica.
    var hits: [TicketField2: Bool]
    var seconds: Double
}

enum TicketScoring {
    /// O que o extrator devolveu, em texto simples (um lugar só pra trocar quando o extrator ganhar campos).
    struct Observed: Sendable {
        var title: String?
        var at: Date?
        var venue: String?
        var seat: String?
        var gate: String?
        var codes: [String] = []
        var qr: String?
        var name: String?
    }

    static func observed(_ e: ExtractedTicket) -> Observed {
        Observed(title: e.title?.value, at: e.at?.value, venue: e.venue?.value ?? e.meetingPoint?.value, seat: e.seat?.value, gate: e.gate?.value,
                 codes: [e.confirmation?.value, e.qrPayload?.value].compactMap { $0 }, qr: e.qrPayload?.value, name: e.holder?.value)
    }

    @MainActor
    static func score(_ ticket: TicketCase, form: TicketForm, extracted: ExtractedTicket, seconds: Double) -> TicketScore {
        let o = observed(extracted)
        let t = ticket.truth
        var hits: [TicketField2: Bool] = [:]
        hits[.titulo] = o.title.map { TicketText.appears(t.title, in: $0) } ?? false
        let calendar = ticket.region.calendar
        let parts = o.at.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        hits[.data] = parts.map { [$0.year, $0.month, $0.day] == Array(t.at[0...2]) } ?? false
        hits[.hora] = parts.map { [$0.hour, $0.minute] == Array(t.at[3...4]) } ?? false
        if let venue = t.venue { hits[.local] = o.venue.map { TicketText.appears(venue, in: $0) } ?? false }
        if let seat = t.seat { hits[.assento] = o.seat.map { value in seat.allSatisfy { TicketText.appears($0, in: value) } } ?? false }
        if let gate = t.gate { hits[.portao] = o.gate.map { TicketText.appears(gate, in: $0) } ?? false }
        hits[.codigo] = o.codes.contains(t.code)
        hits[.qr] = o.qr == ticket.qr
        if !t.name.isEmpty { hits[.nome] = o.name.map { TicketText.appears(t.name, in: $0) } ?? false }
        return TicketScore(caseID: ticket.id, kindLabel: ticket.label, form: form, hits: hits, seconds: seconds)
    }

    /// Tabela em Markdown: campo × forma, e campo × tipo.
    static func markdown(_ scores: [TicketScore], title: String) -> String {
        func rate(_ subset: [TicketScore], _ field: TicketField2) -> String {
            let values = subset.compactMap { $0.hits[field] }
            guard !values.isEmpty else { return "n/a" }
            return "\(Int((Double(values.filter { $0 }.count) / Double(values.count) * 100).rounded()))%"
        }
        func total(_ subset: [TicketScore]) -> String {
            let all = subset.flatMap { Array($0.hits.values) }
            guard !all.isEmpty else { return "n/a" }
            return "\(Int((Double(all.filter { $0 }.count) / Double(all.count) * 100).rounded()))%"
        }
        var out = "### \(title)\n\n"
        let fields = TicketField2.allCases
        out += "Por forma do arquivo\n\n| forma | " + fields.map(\.rawValue).joined(separator: " | ") + " | total |\n|---|" + String(repeating: "---|", count: fields.count + 1) + "\n"
        for form in TicketForm.allCases {
            let subset = scores.filter { $0.form == form }
            out += "| \(form.rawValue) | " + fields.map { rate(subset, $0) }.joined(separator: " | ") + " | \(total(subset)) |\n"
        }
        out += "| **tudo** | " + fields.map { rate(scores, $0) }.joined(separator: " | ") + " | \(total(scores)) |\n\n"
        out += "Por tipo\n\n| tipo | " + fields.map(\.rawValue).joined(separator: " | ") + " | total |\n|---|" + String(repeating: "---|", count: fields.count + 1) + "\n"
        for ticket in TicketCorpus.all {
            let subset = scores.filter { $0.caseID == ticket.id }
            out += "| \(ticket.label) | " + fields.map { rate(subset, $0) }.joined(separator: " | ") + " | \(total(subset)) |\n"
        }
        let avg = scores.map(\.seconds).reduce(0, +) / Double(max(scores.count, 1))
        out += "\nTempo médio de leitura: \(String(format: "%.2f", avg)) s por arquivo.\n"
        return out
    }
}
