import CoreLocation
import Foundation

/// Capítulos do Guia do bairro (prompt 23 §2 · 06, `Guia.png`): os Musts do bairro por período do dia (Manhã, Tarde,
/// Noite). As paradas do dia entram com a hora; os outros Musts do bairro entram pela janela do lugar, sem hora.
/// Puro (sem SwiftData): a tela converte `DayStop`/`Place` nas entradas abaixo.
enum GuiaChapters {
    enum Period: String, CaseIterable, Sendable, Hashable {
        case manha, tarde, noite

        var title: String {
            switch self {
            case .manha: "Manhã"
            case .tarde: "Tarde"
            case .noite: "Noite"
            }
        }

        /// Faixa padrão quando o capítulo não tem hora ("12:00 → 18:00").
        var hours: (start: Int, end: Int) {
            switch self {
            case .manha: (7, 12)
            case .tarde: (12, 18)
            case .noite: (18, 24)
            }
        }

        static func of(hour: Int) -> Period {
            switch hour {
            case 5..<12: .manha
            case 12..<18: .tarde
            default: .noite
            }
        }

        static func of(windows: [DayWindow]) -> Period {
            if windows.contains(.lunch) || windows.contains(.afternoon) { return .tarde }
            if windows.contains(.dinner) || windows.contains(.night) { return .noite }
            if windows.contains(.morning) { return .manha }
            return .tarde
        }
    }

    struct Item: Identifiable, Hashable, Sendable {
        var id: String
        var placeId: String?
        var title: String
        var meta: String
        /// Hora da parada no dia; `nil` = Must do bairro fora do dia.
        var at: Date?
        var isNow: Bool
        var done: Bool
        var micro: Bool
    }

    struct Chapter: Identifiable, Hashable, Sendable {
        var period: Period
        var items: [Item]
        var start: Date?
        var end: Date?

        var id: String { period.rawValue }
    }

    /// Must do bairro fora do dia.
    struct Extra: Sendable {
        var placeId: String
        var title: String
        var meta: String
        var windows: [DayWindow]
        var done: Bool
    }

    /// `stops`: paradas do dia que caem no bairro (na ordem). `nowStopId`: a parada de agora. `extras`: os outros Musts
    /// (já sem os que estão no dia), até `perChapter` por capítulo. Feitos vão pro fim do capítulo.
    static func build(stops: [DayStop], nowStopId: String?, extras: [Extra], calendar: Calendar, now: Date,
                      perChapter: Int = 5) -> [Chapter] {
        var buckets: [Period: [Item]] = [:]
        var ranges: [Period: (Date, Date)] = [:]
        // A manhã que já passou não tem capítulo (o guia é pra daqui pra frente), salvo parada de agora.
        for stop in stops {
            let period = Period.of(hour: calendar.component(.hour, from: stop.start))
            buckets[period, default: []].append(Item(id: "stop-\(stop.id)", placeId: stop.placeId, title: stop.label, meta: stop.note,
                                                     at: stop.start, isNow: stop.id == nowStopId, done: stop.done,
                                                     micro: stop.kind == .micro))
            let r = ranges[period] ?? (stop.start, stop.end)
            ranges[period] = (min(r.0, stop.start), max(r.1, stop.end))
        }
        let used = Set(stops.compactMap(\.placeId))
        for extra in extras where !used.contains(extra.placeId) {
            let period = Period.of(windows: extra.windows)
            guard (buckets[period]?.count ?? 0) < perChapter + stops.count else { continue }
            buckets[period, default: []].append(Item(id: "place-\(extra.placeId)", placeId: extra.placeId, title: extra.title,
                                                     meta: extra.meta, at: nil, isNow: false, done: extra.done, micro: false))
        }
        let currentPeriod = Period.of(hour: calendar.component(.hour, from: now))
        return Period.allCases.compactMap { period in
            guard var items = buckets[period], !items.isEmpty else { return nil }
            // Períodos que já passaram somem quando tudo neles está feito.
            if period.order < currentPeriod.order, items.allSatisfy({ $0.done || $0.at == nil }), !items.contains(where: \.isNow) {
                return nil
            }
            items = items.enumerated().sorted { a, b in
                if a.element.done != b.element.done { return !a.element.done }
                switch (a.element.at, b.element.at) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.offset < b.offset
                }
            }.map(\.element)
            let timed = items.filter { $0.at != nil }.count
            items = Array(items.prefix(max(perChapter, timed)))
            let range = ranges[period]
            return Chapter(period: period, items: items, start: range?.0, end: range?.1)
        }
    }

    /// "Tarde 14:30 → 17:00": faixa das paradas ou a do período.
    static func rangeText(_ chapter: Chapter, time: (Date) -> String) -> String {
        if let start = chapter.start, let end = chapter.end { return "\(time(start)) → \(time(end))" }
        let h = chapter.period.hours
        return String(format: "%02d:00 → %02d:00", h.start, h.end % 24)
    }
}

extension GuiaChapters.Period {
    var order: Int { GuiaChapters.Period.allCases.firstIndex(of: self) ?? 0 }
}

/// Texto de duas linhas por bairro (curado, offline). Sem texto, o Guia monta uma linha com os números do bairro.
enum GuiaBlurbs {
    static let text: [String: String] = [
        // Tóquio
        "shinjuku": "Estação mais movimentada do mundo e, por isso, tudo perto: ramen de fila, o parque do golden e os bares de dez lugares. Comece a oeste, termine a leste.",
        "shibuya": "O cruzamento, as lojas de disco e os bares de vinil. De dia, Miyashita Park; de noite, Nonbei Yokocho.",
        "harajuku": "Takeshita pra ver, Omotesando pra comprar e o Meiji Jingu pra respirar. Cedo é melhor.",
        "asakusa": "A Tóquio antiga: Senso-ji, Nakamise e as oficinas de faca e de comida de plástico. Volte de noite, com o templo aceso.",
        "ueno": "Museus no parque, Ameyoko de comida de rua e o zoológico. Fecha cedo, comece de manhã.",
        "akihabara": "Eletrônicos, retrô games e maid cafés. Sábado e domingo a rua principal fecha pros carros à tarde.",
        "ginza": "Lojas de departamento, depachika e cafés antigos. Sábado e domingo a Chuo-dori vira rua de pedestre.",
        "nakameguro": "O rio com as cerejeiras, cafés de bairro e sushi de balcão. Bom de andar no fim da tarde.",
        "naka-meguro": "O rio com as cerejeiras, cafés de bairro e sushi de balcão. Bom de andar no fim da tarde.",
        "shimokitazawa": "Brechós, cafés e teatros pequenos. Tudo a pé, sem pressa, melhor de tarde.",
        "nakano": "Nakano Broadway pra colecionador e becos de izakaya atrás da estação.",
        "tsukiji": "O mercado externo de manhã cedo: tamagoyaki, ostra e faca. Quase tudo fecha às 14h.",
        "roppongi": "Mori Art Museum, a vista do Tokyo City View e a noite mais internacional da cidade.",
        "ebisu": "Cervejaria, yakitori e o Garden Place. Bom pra jantar tranquilo.",
        "kichijoji": "Inokashira Park, o Ghibli e as ruelas de Harmonica Yokocho.",
        // Kyoto
        "gion": "Machiya, chá e o caminho de Hanamikoji. Cedo pra foto, à noite pras lanternas.",
        "higashiyama": "Kiyomizu-dera e as ladeiras de Sannenzaka. Comece antes das 8h pra pegar vazio.",
        "arashiyama": "Bambuzal, o rio e o Tenryu-ji. Chegue às 7h ou espere multidão.",
        // BH
        "savassi": "A praça, os bares de calçada e as lojas de rua. Tudo a pé, melhor no fim da tarde.",
        "centro": "Mercado Central, o Edifício Niemeyer e a Praça Sete. De dia; de noite, de carro.",
        "funcionarios": "Cafés, restaurantes e a Praça da Liberdade com os museus do Circuito Cultural.",
        "lourdes": "Restaurantes de chef e bares escondidos. Reserva no fim de semana.",
        "santa-tereza": "O bairro boêmio: botecos antigos, samba e comida de vó.",
        "pampulha": "A lagoa, a igrejinha do Niemeyer e o Mineirão. Vá de carro e fique pro pôr do sol.",
        // Roma
        "centro-storico": "Pantheon, Navona e as ruelas entre os dois. Igrejas fecham das 12:30 às 15:30.",
        "trastevere": "Trattorias de família, roupa no varal e o Gianicolo no golden. Sem reserva, chegue cedo.",
        "monti": "Colosseo a cinco minutos, bares de vinho e lojas pequenas. O bairro mais vivo do centro.",
        "vaticano": "Museus e São Pedro: ombro e joelho cobertos, ingresso com hora marcada.",
        "testaccio": "O mercado, a pizza al taglio e o melhor quinto quarto de Roma.",
        "ghetto": "Carciofo alla giudia, o Pórtico de Otávia e a sinagoga. Fecha no sábado.",
    ]

    static func blurb(areaId: String, name: String, musts: Int, open: Int) -> String {
        if let text = text[areaId] { return text }
        if musts == 0 { return "Nenhum Must seu aqui ainda. Os vizinhos estão logo abaixo." }
        return "\(musts) \(musts == 1 ? "Must seu" : "Musts seus") em \(name)\(open > 0 ? ", \(open) \(open == 1 ? "aberto" : "abertos") agora" : ""). Comece pelo mais perto."
    }
}
