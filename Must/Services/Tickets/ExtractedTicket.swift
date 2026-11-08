import Foundation

/// Tipo do ingresso (prompt 15 · A). Experiência e evento viram lugar com sessão; voo vai pra Voos (fatia 6);
/// trem e QR de entrada (Visit Japan Web) vão pra Carteira (fatia 5).
enum TicketKind: String, Codable, Sendable, CaseIterable {
    case experience, event, flight, rail, entry, other

    var label: String {
        switch self {
        case .experience: "experiência"
        case .event: "evento"
        case .flight: "voo"
        case .rail: "trem"
        case .entry: "entrada"
        case .other: "outro"
        }
    }
}

/// Um campo lido: valor, confiança (0–1) e de onde veio ("pelo QR", "lido do texto", "do passe", "no aparelho", "à mão").
struct Extracted<Value: Equatable & Sendable>: Equatable, Sendable {
    var value: Value
    var confidence: Double
    var origin: String

    /// Abaixo de 0,8 a tela pede conferência (âmbar); acima, verde.
    var needsReview: Bool { confidence < ExtractedTicket.reviewBelow }
}

/// Uma perna de voo (conexões são várias pernas do mesmo PNR).
struct FlightLeg: Equatable, Sendable {
    var number: String
    var from: String
    var to: String
    var departs: Date?
}

/// O que sai da leitura: campos opcionais com confiança. Nada aqui é salvo sem a tela de conferência.
struct ExtractedTicket: Equatable, Sendable {
    static let reviewBelow = 0.8

    var kind: TicketKind = .other
    var title: Extracted<String>?
    var supplier: Extracted<String>?
    var at: Extracted<Date>?
    var people: Extracted<Int>?
    var price: Extracted<Double>?
    var currency: Extracted<String>?
    var confirmation: Extracted<String>?
    var qrPayload: Extracted<String>?
    var meetingPoint: Extracted<String>?
    var cancelUntil: Extracted<Date>?
    /// Local (museu, teatro, restaurante, estação): o endereço ou nome do lugar, quando não é ponto de encontro.
    var venue: Extracted<String>?
    /// Assento, fila, carro ou poltrona, como está no ingresso ("Carro 7 · 12A").
    var seat: Extracted<String>?
    /// Portão, plataforma, entrada ou porta.
    var gate: Extracted<String>?
    /// Nome do titular/passageiro.
    var holder: Extracted<String>?
    var legs: [FlightLeg] = []
}

/// Regras determinísticas (prompt 15 · A): QR e passe primeiro, depois regex. O modelo entra depois (`TicketModelExtractor`)
/// e só completa o que aqui ficou vazio ou abaixo de 0,8.
enum TicketExtractor {
    static func extract(_ reading: TicketReading, region: Region) -> ExtractedTicket {
        var out = ExtractedTicket()
        let text = reading.text
        let fromPass = reading.pass != nil

        // QR / código de barras (pelo QR ou do passe): o código do fornecedor quase sempre é o próprio QR.
        if let code = reading.codes.first(where: { !$0.isEmpty }) {
            out.qrPayload = Extracted(value: code, confidence: 0.98, origin: fromPass ? "do passe" : "pelo QR")
        }

        // Confirmação: QR com cara de código > código rotulado ("Código de reserva: XKQ7MP") > "BR-7K2M-9931" solto.
        if let code = reading.codes.first(where: TicketText.looksLikeCode) {
            out.confirmation = Extracted(value: code, confidence: 0.95, origin: fromPass ? "do passe" : "pelo QR")
        } else if let labelled = labelledCode(in: text) {
            out.confirmation = Extracted(value: labelled, confidence: 0.9, origin: "lido do texto")
        } else if let loose = TicketText.first(#"\b([A-Z]{2,3}-[A-Z0-9]{4}-[A-Z0-9]{4})\b"#, in: text)?[1] {
            out.confirmation = Extracted(value: loose, confidence: 0.85, origin: "lido do texto")
        }

        // Fornecedor: passe > palavra conhecida no texto.
        if let org = reading.pass?.organization {
            out.supplier = Extracted(value: org, confidence: 0.9, origin: "do passe")
        } else if let name = supplier(in: text) {
            out.supplier = Extracted(value: name, confidence: 0.95, origin: "lido do texto")
        }

        // Pernas de voo (PNR com duas ou mais linhas "LA 8084 · … · GRU → DOH").
        out.legs = flightLegs(in: text, region: region)

        // Data e hora: o passe manda; senão a primeira data que não seja de cancelamento.
        if let date = reading.pass?.relevantDate {
            out.at = Extracted(value: date, confidence: 0.9, origin: "do passe")
        } else if let found = TicketDates.first(in: mainText(text), region: region) {
            out.at = Extracted(value: found.date, confidence: found.hasTime ? 0.9 : 0.6, origin: "lido do texto")
        } else if let leg = out.legs.first?.departs {
            out.at = Extracted(value: leg, confidence: 0.85, origin: "lido do texto")
        }

        // Título: passe > "Experiência: …" > primeira linha com cara de título.
        if let description = reading.pass?.description {
            out.title = Extracted(value: description, confidence: 0.9, origin: "do passe")
        } else if let labelled = labelledTitle(in: text) {
            out.title = Extracted(value: labelled, confidence: 0.85, origin: "lido do texto")
        } else if let line = titleLine(in: text) {
            out.title = Extracted(value: line, confidence: 0.55, origin: "lido do texto")
        }

        // Pessoas.
        if let found = people(in: text) {
            out.people = Extracted(value: found.value, confidence: found.confidence, origin: "lido do texto")
        }

        // Preço e moeda.
        if let amount = TicketMoney.first(in: text) {
            out.price = Extracted(value: amount.value, confidence: amount.labelled ? 0.85 : 0.6, origin: "lido do texto")
            if let code = amount.currency {
                out.currency = Extracted(value: code, confidence: 0.9, origin: "lido do texto")
            }
        }
        if out.currency == nil, out.price != nil {
            out.currency = Extracted(value: region.currency, confidence: 0.5, origin: "moeda da região")
        }

        // Ponto de encontro: passe (locations) > rótulo "Meeting point:" / "Ponto de encontro:".
        if let location = reading.pass?.locationTexts.first {
            out.meetingPoint = Extracted(value: location, confidence: 0.9, origin: "do passe")
        } else if let meeting = meetingPoint(in: text) {
            out.meetingPoint = Extracted(value: meeting, confidence: 0.8, origin: "lido do texto")
        }

        // Cancelamento grátis até (data, ou "24h antes" sobre a data do ingresso).
        if let cancel = cancelUntil(in: text, region: region, start: out.at?.value) {
            out.cancelUntil = cancel
        }

        out.kind = kind(text: text, supplier: out.supplier?.value, legs: out.legs, codes: reading.codes)
        if out.kind == .entry {
            out.title = Extracted(value: entryName(text: text), confidence: 0.9, origin: "lido do texto")
        }
        return out
    }

    // MARK: Campos

    /// Código depois de um rótulo ("Código de reserva: XKQ7MP", "Reference BR-7K2M-9931"). Maiúsculas e dígitos, sem palavra comum.
    static func labelledCode(in text: String) -> String? {
        let label = #"(?i:código de reserva|codigo de reserva|reservation code|booking reference|booking code|confirmation code|código de confirmação|codigo de confirmacao|confirmation number|número da reserva|numero da reserva|localizador|pnr|reference|referência|referencia|confirmação|confirmacao|confirmation)"#
        for m in TicketText.matches(label + #"\s*(?:number|#|nº|n°)?\s*[:#.]?\s*([A-Za-z0-9][A-Za-z0-9-]{3,23})"#, in: text) {
            let candidate = m.groups[1]
            if candidate.uppercased() == candidate, TicketText.looksLikeCode(candidate) { return candidate }
        }
        return nil
    }

    static func supplier(in text: String) -> String? {
        let known: [(String, String)] = [
            ("Viator", "Viator"), ("GetYourGuide", "GetYourGuide"), ("Klook", "Klook"), ("Airbnb", "Airbnb"),
            ("LATAM", "LATAM"), ("Sympla", "Sympla"), ("Peatix", "Peatix"), ("e-plus", "e-plus"), ("Ingresse", "Ingresse"),
        ]
        for (word, name) in known where TicketText.first(#"(?i)\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#, in: text) != nil {
            return name
        }
        return nil
    }

    static func flightLegs(in text: String, region: Region) -> [FlightLeg] {
        var legs: [FlightLeg] = []
        for line in TicketText.lines(text) {
            let routes = TicketText.matches(#"\(([A-Z]{3})\)"#, in: line)
            guard let flight = TicketText.first(#"\b([A-Z]{2})\s?(\d{3,4})\b"#, in: line), routes.count >= 2 else { continue }
            let departs = TicketDates.first(in: line, region: region)?.date
            legs.append(FlightLeg(number: "\(flight[1]) \(flight[2])", from: routes[0].groups[1], to: routes[1].groups[1], departs: departs))
        }
        return legs
    }

    static func labelledTitle(in text: String) -> String? {
        let label = #"(?i)(?:experi[eê]ncia|experience|atividade|activity|tour|produto|product|evento|event|ingresso|ticket|aula|class|show)\s*:\s*([^\n]{4,120})"#
        guard let value = TicketText.first(label, in: text)?[1].trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Primeira linha com cara de título: 3 a 14 palavras, sem número e sem palavra de cabeçalho/rótulo.
    static func titleLine(in text: String) -> String? {
        let noise = #"(?i)confirm|reserv|booking|reference|refer[eê]ncia|passag|passenger|travel|meeting|encontro|cancel|pessoas|total|pago|price|pre[çc]o|e-?mail|www\.|http|código|codigo|localizador|pnr|checkin|check-in|seat|assento|terminal|gate"#
        for line in TicketText.lines(text) {
            let words = line.split(separator: " ")
            guard (3...14).contains(words.count), line.count <= 120, line.rangeOfCharacter(from: .decimalDigits) == nil,
                  !line.contains(":"), !line.contains("·"), TicketText.matches(noise, in: line).isEmpty else { continue }
            return line
        }
        return nil
    }

    /// (valor, confiança): "2 travelers", "Pessoas: 2" · "2 pessoas".
    static func people(in text: String) -> (confidence: Double, value: Int)? {
        if let hit = TicketText.first(#"(?i)\b(\d{1,2})\s+(?:travel(?:l)?ers|passengers|adults?|people|guests|pessoas|passageiros|adultos|viajantes|participantes)\b"#, in: text),
           let n = Int(hit[1]), (1...50).contains(n) {
            return (0.85, n)
        }
        if let hit = TicketText.first(#"(?i)(?:pessoas|passageiros|travel(?:l)?ers|participantes|quantidade|guests)\s*:?\s*(\d{1,2})\b"#, in: text),
           let n = Int(hit[1]), (1...50).contains(n) {
            return (0.8, n)
        }
        return nil
    }

    static func meetingPoint(in text: String) -> String? {
        let label = #"(?i)(?:meeting point|meeting place|ponto de encontro|local de encontro|encontro|集合場所)\s*:?\s*([^\n]{3,120})"#
        guard let value = TicketText.first(label, in: text)?[1].trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func cancelUntil(in text: String, region: Region, start: Date?) -> Extracted<Date>? {
        let label = #"(?i)(?:cancelamento gr[aá]tis at[eé]|cancelamento gratuito at[eé]|gr[aá]tis at[eé]|free cancellation (?:until|up to)|cancel(?:lation)? (?:for free )?until)"#
        for line in TicketText.lines(text) where TicketText.matches(label, in: line).isEmpty == false {
            if let found = TicketDates.first(in: line, region: region) {
                return Extracted(value: found.date, confidence: 0.75, origin: "lido do texto")
            }
            if let hours = TicketText.first(#"(?i)(\d{1,3})\s*(?:h|horas?|hours?)\s*(?:antes|before)"#, in: line),
               let n = Int(hours[1]), let start {
                return Extracted(value: start.addingTimeInterval(-Double(n) * 3600), confidence: 0.7, origin: "lido do texto")
            }
        }
        return nil
    }

    /// Tipo pela leitura: pernas de voo mandam; depois trem; depois experiência (fornecedor ou palavras) ou evento.
    static func kind(text: String, supplier: String?, legs: [FlightLeg], codes: [String] = []) -> TicketKind {
        if !legs.isEmpty { return .flight }
        if isEntryQR(text: text, codes: codes) { return .entry }
        if TicketText.matches(#"(?i)\b(shinkansen|nozomi|hikari|japan rail|jr pass|suica|trem|train|rail ?pass)\b"#, in: text).isEmpty == false {
            return .rail
        }
        let experienceSuppliers = ["Viator", "GetYourGuide", "Klook", "Airbnb"]
        if let supplier, experienceSuppliers.contains(supplier) { return .experience }
        if TicketText.matches(#"(?i)\b(tour|aula|class|workshop|experience|experiência|oficina|tasting|degusta[çc][aã]o|atelier|cooking)\b"#, in: text).isEmpty == false {
            return .experience
        }
        if TicketText.matches(#"(?i)\b(show|concert|concerto|exposi[çc][aã]o|exhibition|museum|museu|jogo|match|festival|galeria|gallery)\b"#, in: text).isEmpty == false
            || supplier == "Sympla" || supplier == "Peatix" || supplier == "Ingresse" || supplier == "e-plus" {
            return .event
        }
        return .other
    }

    /// QR de entrada no Japão (Visit Japan Web): o texto ou o QR apontam pro site/app do governo.
    static func isEntryQR(text: String, codes: [String]) -> Bool {
        let pattern = #"(?i)visit\s?japan|digital\.go\.jp|\bvjw\b"#
        if !TicketText.matches(pattern, in: text).isEmpty { return true }
        return codes.contains { !TicketText.matches(pattern, in: $0).isEmpty }
    }

    /// "Visit Japan Web · imigração" / "· alfândega": o texto diz qual dos dois QRs é. Sem pista (ou com as duas), só o nome.
    static func entryName(text: String) -> String {
        let immigration = !TicketText.matches(#"(?i)imigra[çc][aã]o|immigration"#, in: text).isEmpty
        let customs = !TicketText.matches(#"(?i)alf[aâ]nde(ga)?|customs"#, in: text).isEmpty
        switch (immigration, customs) {
        case (true, false): return "Visit Japan Web · imigração"
        case (false, true): return "Visit Japan Web · alfândega"
        default: return "Visit Japan Web"
        }
    }

    // MARK: Auxiliares

    /// O texto sem as linhas de cancelamento (a data do ingresso não pode ser a data limite).
    static func mainText(_ text: String) -> String {
        TicketText.lines(text).filter { line in
            TicketText.matches(#"(?i)cancel|gr[aá]tis at[eé]|gratuito at[eé]|free cancellation"#, in: line).isEmpty
        }.joined(separator: "\n")
    }
}
