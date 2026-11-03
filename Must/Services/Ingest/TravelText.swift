import Foundation

/// Dia sugerido no texto colado ("Dia 2 — Asakusa e Ueno"), com os lugares na ordem do texto (prompt 18 · E.21).
struct TravelDay: Equatable, Sendable {
    /// Número do "Dia N": vira a data do dia criado (dia 1 = início da viagem).
    var number: Int?
    var title: String
    /// Bairro ou tema ("Asakusa e Ueno").
    var area: String?
    /// Nomes dos lugares do dia, na ordem do texto.
    var items: [String]
}

/// Dica do texto e pra onde ela vai (prompt 18 · E.22): nota de um lugar, Carteira ou nota do dia.
struct TravelTip: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case place(String)
        case wallet
        case general
    }

    var text: String
    var target: Target
}

/// Resultado do pipeline de texto colado, antes de conferir no Places (prompt 18 · E.21).
struct TravelTextDraft: Equatable, Sendable {
    var days: [TravelDay] = []
    var places: [ExtractedPlace] = []
    var tips: [TravelTip] = []
    var links: [URL] = []
    /// Por onde passou ("no aparelho", "palavras-chave"). Mostrado no cabeçalho.
    var via = ""

    /// Junta blocos (de ~3.000 caracteres): dias em sequência, lugares sem repetir o nome, dicas sem repetir o texto.
    static func merge(_ parts: [TravelTextDraft]) -> TravelTextDraft {
        var out = TravelTextDraft()
        var vias: [String] = []
        for part in parts {
            let offset = out.days.count
            out.days += part.days
            for var place in part.places {
                place.dayIndex = place.dayIndex.map { $0 + offset }
                let key = PlaceMatcher.normalize(place.name)
                if let i = out.places.firstIndex(where: { PlaceMatcher.normalize($0.name) == key }) {
                    out.places[i].mentions += place.mentions
                    out.places[i].category = out.places[i].category ?? place.category
                    out.places[i].sub = out.places[i].sub ?? place.sub
                    out.places[i].area = out.places[i].area ?? place.area
                    out.places[i].nameLocal = out.places[i].nameLocal ?? place.nameLocal
                    out.places[i].dayIndex = out.places[i].dayIndex ?? place.dayIndex
                } else {
                    out.places.append(place)
                }
            }
            for tip in part.tips where !out.tips.contains(where: { $0.text == tip.text }) {
                out.tips.append(tip)
            }
            for link in part.links where !out.links.contains(link) {
                out.links.append(link)
            }
            if !part.via.isEmpty, !vias.contains(part.via) { vias.append(part.via) }
        }
        out.via = vias.joined(separator: " + ")
        return out
    }
}

/// Texto colado → dias, lugares, links e dicas, sem modelo: regex de listas, títulos e frases (prompt 18 · E.21).
/// É o fallback sem Foundation Models (simulador, aparelho sem Apple Intelligence) e a base de teste.
/// Nunca inventa lugar: só sai nome que aparece no texto, e o Places confere depois.
enum TravelTextParser {
    /// Bairros de Tóquio e de BH: aparecem como área, nunca como lugar.
    static let builtinAreas = [
        "Shibuya", "Shinjuku", "Harajuku", "Omotesando", "Asakusa", "Ueno", "Ginza", "Akihabara", "Ikebukuro",
        "Shimokitazawa", "Nakameguro", "Daikanyama", "Roppongi", "Tsukiji", "Kichijoji", "Yanaka", "Kagurazaka",
        "Ebisu", "Odaiba", "Nakano", "Koenji", "Shimbashi", "Ryogoku", "Gion", "Higashiyama", "Arashiyama",
        "Fushimi", "Kyoto", "Nara", "Osaka", "Savassi", "Lourdes", "Funcionários", "Santa Tereza", "Pampulha",
        "Sion", "Centro",
    ]

    /// Texto que pode ser mostrado e analisado: sem marcação de Markdown, sem espaços nas bordas.
    static func displayText(_ raw: String) -> String {
        raw.replacing("**", with: "")
            .replacing("__", with: "")
            .replacing("`", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                while l.hasPrefix("#") { l.removeFirst() }
                return l.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }

    /// Links (http/https e domínio colado sem esquema), com o intervalo no texto de exibição.
    static func linkRanges(in text: String) -> [(url: URL, range: Range<String.Index>)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var out: [(URL, Range<String.Index>)] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https",
                  let range = Range(match.range, in: text), !out.contains(where: { $0.0 == url }) else { continue }
            out.append((url, range))
        }
        return out
    }

    static func links(in text: String) -> [URL] {
        linkRanges(in: text).map(\.url)
    }

    static func parse(_ raw: String, knownAreas: [String] = []) -> TravelTextDraft {
        let display = displayText(raw)
        let body = display.replacing(/(?:https?:\/\/|www\.)\S+/, with: " ").replacing(/\b[\w-]+\.(?:com|jp|br|io|app|co|net|org)\S*/, with: " ")
        var acc = Accumulator(areas: knownAreas + builtinAreas)
        for paragraph in body.split(whereSeparator: \.isNewline) {
            let line = paragraph.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let header = dayHeader(line) {
                acc.startDay(header)
                continue
            }
            let bullet = bulletBody(line)
            acc.startParagraph(bullet: bullet != nil)
            for sentence in (bullet ?? line).split(whereSeparator: { ".!?".contains($0) }) {
                acc.sentence(String(sentence))
            }
        }
        var draft = TravelTextDraft(days: acc.days, places: acc.places, tips: acc.tips, links: links(in: display))
        for i in draft.days.indices {
            draft.days[i].items = acc.places.filter { $0.dayIndex == i }.map(\.name)
        }
        draft.via = "palavras-chave"
        return draft
    }

    // MARK: Linhas

    static func dayHeader(_ line: String) -> TravelDay? {
        guard line.count <= 80, let m = line.firstMatch(of: /(?i)^(?:dia|day)\s*(\d{1,2})\b[\s:.\-—–]*(.*)$/) else { return nil }
        let rest = String(m.2).trimmingCharacters(in: CharacterSet(charactersIn: " :.-—–*"))
        return TravelDay(number: Int(m.1), title: rest.isEmpty ? "Dia \(m.1)" : "Dia \(m.1) — \(rest)",
                         area: rest.isEmpty ? nil : rest, items: [])
    }

    static func bulletBody(_ line: String) -> String? {
        guard let m = line.firstMatch(of: /^(?:[-•*▪●]|\d{1,2}[.)])\s+(.*)$/) else { return nil }
        return String(m.1)
    }

    /// Pedaço de frase entre vírgulas, dashes e parênteses. `paren` = estava entre parênteses.
    struct Clause {
        var text: String
        var paren: Bool
        var range: Range<String.Index>
    }

    static func clauses(of sentence: String) -> [Clause] {
        var out: [Clause] = []
        var start = sentence.startIndex
        var paren = false
        func push(_ end: String.Index) {
            let range = start..<end
            let text = sentence[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append(Clause(text: text, paren: paren, range: range)) }
        }
        var i = sentence.startIndex
        while i < sentence.endIndex {
            let ch = sentence[i]
            if ch == "(" || ch == ")" {
                push(i)
                paren = ch == "("
                start = sentence.index(after: i)
            } else if ",;—–:".contains(ch) {
                push(i)
                start = sentence.index(after: i)
            }
            i = sentence.index(after: i)
        }
        push(sentence.endIndex)
        return out
    }

    struct Candidate {
        var name: String
        var range: Range<String.Index>
    }

    /// Nomes em potencial numa frase: "no Senso-ji", "Asakusa Imahan", "Tokyo National Museum" e o começo de um item de lista.
    static func candidates(in sentence: String, leading: Bool) -> [Candidate] {
        var raw: [(Substring, Range<String.Index>)] = []
        if leading, let m = sentence.firstMatch(of: /^\s*(\p{Lu}[\p{L}'’&\-]*(?:\s+(?:\p{Lu}[\p{L}'’&\-]*|de|do|da|of|the|&))*)/) {
            raw.append((m.1, m.1.startIndex..<m.1.endIndex))
        }
        for m in sentence.matches(of: /(?:^|\s)(?:no|na|em|at|in|do|da)\s+(\p{Lu}[\p{L}'’&\-]*(?:\s+(?:\p{Lu}[\p{L}'’&\-]*|of|the|de|do|da|&))*)/) {
            raw.append((m.1, m.1.startIndex..<m.1.endIndex))
        }
        for m in sentence.matches(of: /\p{Lu}[\p{L}'’&\-]*(?:\s+(?:\p{Lu}[\p{L}'’&\-]*|of|the|de|do|da|&))+/) {
            raw.append((m.output, m.range))
        }
        // Um nome dentro de outro (a mesma frase achada de dois jeitos): fica o mais longo.
        let sorted = raw.sorted { (a, b) -> Bool in
            if a.1.lowerBound != b.1.lowerBound { return a.1.lowerBound < b.1.lowerBound }
            return a.1.upperBound > b.1.upperBound
        }
        var kept: [(Substring, Range<String.Index>)] = []
        for item in sorted {
            let inside = kept.contains { other in
                other.1.lowerBound <= item.1.lowerBound && item.1.upperBound <= other.1.upperBound
            }
            if !inside { kept.append(item) }
        }
        return kept.compactMap { sub, range in
            guard let name = trimRun(String(sub)) else { return nil }
            return Candidate(name: name, range: range)
        }
    }

    private static let leadStopwords: Set<String> = [
        "dia", "day", "para", "comece", "compre", "depois", "antes", "chegue", "reserve", "claro", "aqui", "fontes",
        "link", "um", "uma", "o", "a", "as", "os", "à", "ao", "na", "no", "em", "se", "mas", "também", "então",
    ]
    private static let trailConnectors: Set<String> = ["de", "do", "da", "no", "na", "of", "the", "&", "e", "em", "com"]

    /// Tira palavra de começo de frase ("Para", "Compre") e conector solto no fim. Nil se não sobra nome.
    static func trimRun(_ raw: String) -> String? {
        var words = raw.split(separator: " ").map(String.init)
        while let first = words.first, leadStopwords.contains(foldedText(first)) { words.removeFirst() }
        while let last = words.last, trailConnectors.contains(foldedText(last)) { words.removeLast() }
        let name = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?'\"“”’"))
        return name.isEmpty ? nil : name
    }

    static func foldedText(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Área citada no texto (palavra inteira, não parte de outra palavra: "Sion" não casa com "decision").
    static func area(in text: String, areas: [String]) -> String? {
        let words = foldedText(text).split { !$0.isLetter }.map(String.init)
        for area in areas.sorted(by: { $0.count > $1.count }) {
            let aw = foldedText(area).split { !$0.isLetter }.map(String.init)
            guard !aw.isEmpty, words.count >= aw.count else { continue }
            for i in 0...(words.count - aw.count) where Array(words[i..<(i + aw.count)]) == aw {
                return area
            }
        }
        return nil
    }

    static func acceptable(_ name: String, areas: [String]) -> Bool {
        guard PlaceExtractor.isPlausible(name), name.first?.isNumber != true else { return false }
        let f = foldedText(name)
        if f.contains("http") || f.contains("www.") { return false }
        return !areas.contains { foldedText($0) == f }
    }

    /// Frase que é dica: começa com verbo de instrução ("Compre", "Reserve") ou cita ingresso, passe, antecedência…
    static func isTipClause(_ text: String) -> Bool {
        let f = foldedText(text)
        let first = f.split { !$0.isLetter }.first.map(String.init) ?? ""
        if imperatives.contains(first) { return true }
        return tipCues.contains { f.contains($0) }
    }

    private static let imperatives: Set<String> = [
        "compre", "compra", "comprar", "reserve", "reserva", "reservar", "chegue", "chegar", "evite", "leve", "baixe",
        "abra", "peca", "confirme", "tente", "aproveite", "prefira", "saia", "use", "faca", "procure", "garanta",
        "separe", "dica", "atencao", "cuidado", "vale",
    ]
    private static let tipCues = ["antecedencia", "ticket", "passe", "esim", "seguro", "vale a pena", "evite", "dica:"]

    /// Parêntese com hora ou dia ("antes das 8h fica vazio", "fecha seg") é dica do lugar; "(tsukemen de peixe)" não.
    static func hasTimeCue(_ text: String) -> Bool {
        let f = foldedText(text)
        if f.range(of: #"\d{1,2}\s?h\b|\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return true }
        return ["antes", "depois", "cedo", "tarde", "fecha", "abre", "vazio", "domingo", "segunda", "feriado"]
            .contains { f.range(of: $0) != nil }
    }
}

extension TravelTip {
    /// Dica que fala de ingresso, passe, cartão, eSIM ou seguro: vai pra Carteira.
    static func isWalletText(_ text: String) -> Bool {
        let f = TravelTextParser.foldedText(text)
        return ["ticket", "passe", "pass ", "esim", "seguro", "passaporte", "suica", "icoca", "pasmo", "visit japan", " qr", "cartao", " jr "]
            .contains { f.contains($0) }
    }

    /// Tipo de item da Carteira pra esta dica (passe e ticket viram passe de trem).
    var walletKind: WalletKind {
        let f = TravelTextParser.foldedText(text)
        if f.contains("esim") { return .esim }
        if f.contains("seguro") { return .insurance }
        if f.contains("passaporte") { return .passport }
        if f.contains("visit japan") || f.contains(" qr") { return .entryQR }
        if f.contains("jr ") || f.contains("jr pass") || f.contains("ticket") || f.contains("passe") || f.contains("pass ") { return .railPass }
        if f.contains("suica") || f.contains("icoca") || f.contains("pasmo") { return .transitCard }
        if f.contains("cartao") { return .creditCard }
        return .other
    }

    /// Nome do item da Carteira: "Tokyo Subway Ticket 72h" (sem o "de" e o verbo), ou o começo da dica.
    var walletName: String {
        if let m = text.firstMatch(of: /((?:\p{Lu}[\p{L}\-]*\s+){0,3}(?:Ticket|Pass|Passe|eSIM|JR Pass|Suica|ICOCA|Pasmo|Seguro)(?:\s+(?:de\s+)?\d+\s?h)?)/) {
            let name = String(m.1).replacing(" de ", with: " ")
            return name.trimmingCharacters(in: .whitespaces)
        }
        return String(text.prefix(60))
    }
}

/// Estado do parser entre as linhas: dia atual, último lugar (pra dica), lugares e dicas.
private struct Accumulator {
    let areas: [String]
    var days: [TravelDay] = []
    var places: [ExtractedPlace] = []
    var tips: [TravelTip] = []
    var current: Int?
    var lastPlace: String?
    /// Próxima frase é o começo de um item de lista ("- Meiji Jingu: …"): o nome inicial conta.
    var leadingNext = false

    init(areas: [String]) {
        self.areas = areas
    }

    mutating func startDay(_ header: TravelDay) {
        days.append(header)
        current = days.count - 1
        lastPlace = nil
    }

    mutating func startParagraph(bullet: Bool) {
        lastPlace = nil
        leadingNext = bullet
    }

    mutating func sentence(_ text: String) {
        let raw = TravelTextParser.candidates(in: text, leading: leadingNext)
        leadingNext = false
        let cands = raw.filter { TravelTextParser.acceptable($0.name, areas: areas) }
        var prevTip = false
        for clause in TravelTextParser.clauses(of: text) {
            if clause.paren {
                if TravelTextParser.hasTimeCue(clause.text) { addTip(clause.text, target: lastPlace.map { .place($0) } ?? .general) }
                prevTip = false
                continue
            }
            if TravelTextParser.isTipClause(clause.text) {
                addTip(clause.text, target: target(for: clause.text))
                prevTip = true
                continue
            }
            let inside = cands.filter { clause.range.contains($0.range.lowerBound) }
            if inside.isEmpty, prevTip, let last = tips.indices.last {
                // Continuação da dica ("..., porque ele cobre metrô"): entra na mesma dica.
                tips[last].text += ", " + clause.text
                continue
            }
            for cand in inside {
                let context = segment(of: cand, in: text, among: raw)
                addPlace(cand.name, context: context)
                lastPlace = cand.name
            }
            prevTip = false
        }
    }

    /// Trecho da frase que é do lugar: do fim do nome anterior até o começo do próximo.
    private func segment(of cand: TravelTextParser.Candidate, in text: String, among all: [TravelTextParser.Candidate]) -> String {
        let before = all.filter { $0.range.upperBound <= cand.range.lowerBound }.map(\.range.upperBound).max() ?? text.startIndex
        let after = all.filter { $0.range.lowerBound >= cand.range.upperBound }.map(\.range.lowerBound).min() ?? text.endIndex
        return String(text[before..<after])
    }

    private func target(for text: String) -> TravelTip.Target {
        if TravelTip.isWalletText(text) { return .wallet }
        if let lastPlace { return .place(lastPlace) }
        return .general
    }

    private mutating func addTip(_ text: String, target: TravelTip.Target) {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?"))
        guard !clean.isEmpty, !tips.contains(where: { $0.text == clean }) else { return }
        tips.append(TravelTip(text: clean, target: target))
    }

    private mutating func addPlace(_ name: String, context: String) {
        let key = PlaceMatcher.normalize(name)
        if let i = places.firstIndex(where: { PlaceMatcher.normalize($0.name) == key }) {
            places[i].mentions += 1
            return
        }
        let dayArea = current.flatMap { days[$0].area }
        let area = TravelTextParser.area(in: context, areas: areas) ?? dayArea.flatMap { TravelTextParser.area(in: $0, areas: areas) }
        places.append(ExtractedPlace(name: name, nameLocal: nil, area: area,
                                     category: TravelCategory.color(name: name, context: context),
                                     sub: PlaceExtractor.sub(in: name) ?? PlaceExtractor.sub(in: context),
                                     hint: current == nil ? "citado no texto" : "no texto colado", dayIndex: current))
    }
}

/// Categoria pela palavra do próprio nome e do trecho da frase (prompt 18 · E.21; o `primaryType` do Places manda depois).
enum TravelCategory {
    static func color(name: String, context: String) -> MustColor? {
        let n = TravelTextParser.foldedText(name)
        if ["museu", "museum", "galeria", "gallery", "exposi"].contains(where: { n.contains($0) }) { return .art }
        if n.hasSuffix("-ji") || ["jingu", "jinja", "templo", "temple", "shrine", "santuario"].contains(where: { n.contains($0) }) {
            return .temple
        }
        if let color = PlaceExtractor.category(in: name) { return color }
        if let color = PlaceExtractor.category(in: context) { return color }
        let c = TravelTextParser.foldedText(context)
        if ["sukiyaki", "yakiniku", "shabu", "gyoza", "tempura", "unagi", "kaiseki", "yakitori", "ramen"].contains(where: { c.contains($0) }) {
            return .eat
        }
        return nil
    }
}
