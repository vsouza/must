import Foundation

/// Campos de ingresso que a regex antiga não lia (prompt 31 · 6): hora rotulada, local, assento, portão, titular, voo.
/// Tudo puro: texto entra, valor sai. Português, inglês, italiano e um pouco de japonês.
enum TicketFields {
    // MARK: Hora

    /// Hora de um "Início do show: 21:00", escolhida pelo rótulo (a abertura dos portões e o embarque perdem pro início/partida).
    /// Sem rótulo, a primeira hora do texto. nil se não há hora nenhuma.
    static func time(in text: String) -> (hour: Int, minute: Int, labelled: Bool)? {
        var best: (rank: Int, location: Int, hour: Int, minute: Int, labelled: Bool)?
        let ns = text as NSString
        let patterns = [#"(?<![\d:.])([01]?\d|2[0-3])[:h]([0-5]\d)(?!\d)\s*([AaPp][Mm])?"#,
                        #"(?<![\d:.])([01]?\d|2[0-3])\s?h(?![\p{L}\d])()()"#,
                        #"(?i)\bore\s+([01]?\d|2[0-3])\.([0-5]\d)\b()"#]
        for m in patterns.flatMap({ TicketText.matches($0, in: text) }) {
            var hour = Int(m.groups[1]) ?? 0
            let minute = Int(m.groups[2]) ?? 0
            switch m.groups[3].lowercased() {
            case "pm": if hour < 12 { hour += 12 }
            case "am": if hour == 12 { hour = 0 }
            default: break
            }
            // Rótulo: o trecho da mesma linha entre o último separador (· | quebra) e a hora.
            let before = ns.substring(to: m.location)
            let tail = before.components(separatedBy: CharacterSet(charactersIn: "\n·|•")).last ?? ""
            let rank = rankOfLabel(tail)
            if best == nil || (rank, m.location) < (best!.rank, best!.location) {
                best = (rank, m.location, hour, minute, rank < 3)
            }
        }
        return best.map { ($0.hour, $0.minute, $0.labelled) }
    }

    /// 0 = início/partida/horário do evento · 1 = entrada/turno/hora · 3 = sem rótulo · 5 = abertura, embarque, chegada.
    private static func rankOfLabel(_ label: String) -> Int {
        let lowered = TicketText.folded(label)
        let low = #"abertura|portoes|portões|開場|doors|embarque|boarding|imbarco|arrives|arrival|chegada|arrivo|check-?in|apertura|cancel|\bate\b|until|fecha|closing"#
        if TicketText.first(low, in: lowered) != nil, TicketText.first(#"inicio|start|show|partida|depart|saida|inizio|開演"#, in: lowered) == nil {
            return 5
        }
        if TicketText.first(#"inicio|início|start|show|partida|depart|saida|saída|inizio|begin|kick|開演|開始"#, in: lowered) != nil { return 0 }
        if TicketText.first(#"entry|entrada|turno|ingresso|ore\b|hora|horario|horário|time|admission|slot|入場|開演|時間"#, in: lowered) != nil { return 1 }
        return 3
    }

    // MARK: Local, assento, portão, titular

    /// "Local: Teatro Bom Retiro — Av. …", "Venue: …", "Luogo: …". O resto da linha depois do rótulo com dois-pontos.
    static func venue(in text: String) -> Extracted<String>? {
        let label = #"(?im)(?:^[^\S\n]*|[·|]\s*)(?:local|venue|luogo|location|endere[cç]o|address|indirizzo|onde|where|会場|場所)\s*[:：]\s*([^\n]{3,140})"#
        if let value = TicketText.first(label, in: text)?[1].trimmingCharacters(in: .whitespaces), !value.isEmpty {
            return Extracted(value: value, confidence: 0.85, origin: "lido do texto")
        }
        if let address = address(in: text) {
            return Extracted(value: address, confidence: 0.6, origin: "endereço no texto")
        }
        return nil
    }

    /// Endereço pelo `NSDataDetector` (a Apple reconhece os formatos de vários países, no aparelho).
    static func address(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else { return nil }
        let ns = text as NSString
        guard let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range).replacingOccurrences(of: "\n", with: ", ")
    }

    /// Carro, fila, setor, poltrona: pedaços na ordem em que aparecem ("Carro 7 · Seat 12A").
    static func seat(in text: String) -> Extracted<String>? {
        let patterns = [
            #"(?i)\b(?:setor|sector|section|settore|bloco|block)\s*[:#]?\s*([^\n·|]{1,24})"#,
            #"(?i)\b(?:car|carro|coach|carrozza|vag[aã]o)\s*[:#]?\s*((?-i:\d{1,2}))\b"#,
            #"(?i)\b(?:fila|row|file)\s*[:#]?\s*((?-i:[A-Z0-9]{1,3}))\b"#,
            #"(?i)\b(?:seat|assento|poltrona|posto|sedile|cadeira|lugar|asiento)\s*[:#]?\s*((?-i:\d{1,3}[A-Z]?|[A-Z]\d{1,3}))\b"#,
            #"(\d{1,2})号車"#, #"(\d{1,2}[A-Z])\s*席"#,
        ]
        var parts: [(location: Int, text: String)] = []
        for pattern in patterns {
            for m in TicketText.matches(pattern, in: text) {
                parts.append((m.location, m.groups[0].trimmingCharacters(in: .whitespaces)))
            }
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.sorted { $0.location < $1.location }.map(\.text).joined(separator: " · ")
        return Extracted(value: joined, confidence: 0.85, origin: "lido do texto")
    }

    /// Portão, plataforma, entrada: o código ou número depois do rótulo.
    static func gate(in text: String) -> Extracted<String>? {
        let label = #"(?i)\b(?:port[aã]o|gate|platform|plataforma|binario|binário|cancello|entrance|entrada|door|porta|ingresso|番線|ゲート)\s*[:#]?\s*((?-i:[A-Z]{1,2}\d{0,2}|\d{1,2}[A-Z]?))\b"#
        guard let value = TicketText.first(label, in: text)?[1], !value.isEmpty else { return nil }
        return Extracted(value: value, confidence: 0.85, origin: "lido do texto")
    }

    /// Nome do titular/passageiro, sem tratamento ("MR", "MS") e sem número.
    static func holder(in text: String) -> Extracted<String>? {
        let label = #"(?i)\b(?:under the name|reserva em nome de|em nome de|reservation name|passageiro|passenger|titular|intestatario|intestatário|visitatore|visitor|guest|h[oó]spede|nome|name|氏名|お名前)\s*[:：]?\s*([^\n·|\d]{3,50})"#
        for m in TicketText.matches(label, in: text) {
            var value = m.groups[1].trimmingCharacters(in: .whitespaces)
            value = value.replacingOccurrences(of: #"\s+(MR|MRS|MS|MISS|SR|SRA)\b\.?$"#, with: "", options: .regularExpression)
            let letters = value.filter(\.isLetter).count
            if letters >= 4, value.contains(where: \.isUppercase) {
                return Extracted(value: value, confidence: 0.85, origin: "lido do texto")
            }
        }
        return nil
    }

    // MARK: Voo e trem

    /// Voo sem "(GRU)" na mesma linha: "Voo LA 8084" e os aeroportos em qualquer lugar ("São Paulo (GRU) → Doha (DOH)", "GRU → DOH").
    static func flightLeg(in text: String) -> FlightLeg? {
        guard let flight = TicketText.first(#"(?i:voo|flight|vol|vuelo|volo)\s*[:#]?\s*((?-i:[A-Z][A-Z0-9]|[A-Z0-9][A-Z]))\s?(\d{3,4})\b"#, in: text) else { return nil }
        var airports = TicketText.matches(#"\(([A-Z]{3})\)"#, in: text).map { $0.groups[1] }
        if airports.count < 2, let route = TicketText.first(#"\b([A-Z]{3})\s*(?:→|->|—|-|to|para)\s*([A-Z]{3})\b"#, in: text) {
            airports = [route[1], route[2]]
        }
        guard airports.count >= 2 else { return nil }
        return FlightLeg(number: "\(flight[1]) \(flight[2])", from: airports[0], to: airports[1], departs: nil)
    }

    /// Nome do trem: "Shinkansen Nozomi 225", "Frecciarossa 9611".
    static func trainTitle(in text: String) -> String? {
        for line in TicketText.lines(text) where line.count <= 80 {
            if TicketText.first(#"(?i)\b(shinkansen|nozomi|hikari|kodama|mizuho|sakura|frecciarossa|frecciargento|italo|intercity|limited express|thello)\b"#, in: line) != nil,
               TicketText.first(#"(?i)(departs|arrives|fare|ticket no|seat|car \d)"#, in: line) == nil {
                return line
            }
        }
        return nil
    }
}
