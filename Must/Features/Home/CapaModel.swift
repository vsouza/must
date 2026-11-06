import CoreGraphics
import Foundation

// Capa do dia v8 (prompt 23 §2 · 01, `CapaJP/BR/IT.png`, `CapaFoto.png`). Tudo que a capa escreve sai daqui,
// calculado nos gatilhos (aparecer, minuto, salvar) — nunca no `body`.

/// O que a capa mostra.
struct CapaContent: Equatable, Sendable {
    /// Ficha técnica: canto de cima à esquerda ("Sáb · 15 nov" / "dia 3 de 14").
    var topLeft: [String]
    /// Canto de cima à direita ("Tóquio · 18° sol" / "pôr do sol 16:38").
    var topRight: [String]
    /// Meio à esquerda ("9 paradas" / "3 âncoras · 4 micro").
    var midLeft: [String]
    /// Meio à direita ("gasto ¥ 4.250" / "de ¥ 12.000").
    var midRight: [String]
    /// "Japão" / "Brasil" / "Itália".
    var country: String
    /// "Shinjuku".
    var area: String
    /// "e Golden Gai à noite" / "e Gianicolo no golden".
    var evening: String?
    /// Numeral do dia (dia da viagem; fora dela, o dia do mês).
    var numeral: String
    /// Card "Agora · 2 de 9" / "Fuunji · saia 14:35". `nil` sem dia montado.
    var agora: Agora?
    var hasPlan: Bool

    struct Agora: Equatable, Sendable {
        var title: String
        var line: String
        /// Dia acabou: o card leva pra Boa noite, não pro Agora.
        var dayOver: Bool
    }
}

extension CapaContent {
    /// Entradas já resolvidas (valores, nada de `@Model`).
    struct Inputs: Sendable {
        var region: Region
        var now: Date
        var plan: DayPlan?
        var dayNow: DayNow?
        /// Nome do bairro do dia (do `Area`), ou do bairro do GPS sem dia montado.
        var areaName: String?
        /// Cidade de hoje ("Tóquio"); sem viagem, o nome da região.
        var cityName: String
        var tripDay: (index: Int, total: Int)?
        var tempText: String?
        var sky: String?
        var sunset: Date?
        /// Gasto de hoje (Expense); `nil` usa o do plano.
        var spentToday: Double?
    }

    static func build(_ i: Inputs) -> CapaContent {
        let region = i.region
        let topLeft = [DayText.dayLine(i.now, region: region),
                       i.tripDay.map { "dia \(i.plan?.dayNumber ?? $0.index) de \($0.total)" }
                           ?? (DayText.isWeekend(i.now, region: region) ? "fim de semana" : "dia de semana")]
        let weather = [i.cityName, [i.tempText, i.sky].compactMap { $0 }.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        var topRight = [weather]
        if let sunset = i.sunset { topRight.append("pôr do sol \(region.timeString(sunset))") }

        let numeral = i.plan?.dayNumber.map(String.init) ?? i.tripDay.map { "\($0.index)" } ?? region.dayNumber(i.now)
        let country = Self.countryName(region)

        guard let plan = i.plan else {
            return CapaContent(topLeft: topLeft, topRight: topRight, midLeft: ["sem dia montado", "monte em 1 minuto"],
                               midRight: i.spentToday.map { ["gasto \(region.money($0))", "hoje"] } ?? [],
                               country: country, area: i.areaName ?? i.cityName, evening: nil, numeral: numeral,
                               agora: nil, hasPlan: false)
        }

        let spent = i.spentToday ?? plan.spent
        let midRight = ["gasto \(region.money(spent))", plan.budget > 0 ? "de \(region.money(plan.budget))" : "sem teto hoje"]
        let area = i.areaName ?? plan.title.components(separatedBy: " + ").first ?? plan.title

        var agora: Agora?
        if let now = i.dayNow, let k = plan.position(of: now.current) {
            let verb = now.arriveBy != nil ? "chegue" : "saia"
            let time = region.timeString(now.arriveBy ?? now.leaveAt)
            agora = Agora(title: "Agora · \(k) de \(plan.stops.count)", line: "\(DayText.head(now.current.label)) · \(verb) \(time)",
                          dayOver: false)
        } else if let first = plan.stops.first(where: { !$0.done }), i.now < first.start, let k = plan.position(of: first) {
            // Antes da primeira parada o motor não tem "agora" (`nil`), mas o dia não acabou: a primeira e a hora de sair.
            let leave = DayNowRules.leaveTime(to: first, in: plan)
            agora = Agora(title: "Primeira · \(k) de \(plan.stops.count)",
                          line: "\(DayText.head(first.label)) · saia \(region.timeString(leave))", dayOver: false)
        } else if !plan.stops.isEmpty {
            agora = Agora(title: "Dia feito · \(plan.stops.count) paradas", line: "Boa noite", dayOver: true)
        }

        return CapaContent(topLeft: topLeft, topRight: topRight, midLeft: [plan.countLine, plan.anchorLine], midRight: midRight,
                           country: country, area: area, evening: evening(plan, region: region), numeral: numeral,
                           agora: agora, hasPlan: true)
    }

    /// "e Golden Gai à noite" (última parada de verdade a partir das 18h) ou "e Gianicolo no golden" (âncora do sol).
    static func evening(_ plan: DayPlan, region: Region) -> String? {
        let cal = region.calendar
        let night = plan.stops.last { $0.kind != .micro && cal.component(.hour, from: $0.start) >= 18 }
        if let night { return "e \(DayText.head(night.label)) à noite" }
        if let golden = plan.stops.first(where: { $0.tag?.uppercased() == "SOL" }) {
            return "e \(DayText.head(golden.label)) no golden"
        }
        return nil
    }

    static func countryName(_ region: Region) -> String {
        region.countryName
    }
}

// MARK: - Gestos

/// Gestos da capa (`Nav.png` › Gestos): pra cima = Linha do dia; pra baixo = Bom dia (antes das 10h) ou Boa noite
/// (depois das 21h); pra esquerda = Dicas; pra direita = Bolso.
enum CapaSwipe: Equatable, Sendable {
    case up, down, left, right

    /// Distância mínima (pt) e eixo dominante.
    static let threshold: CGFloat = 60

    static func from(_ translation: CGSize) -> CapaSwipe? {
        let dx = translation.width, dy = translation.height
        if abs(dy) >= abs(dx) {
            guard abs(dy) >= threshold else { return nil }
            return dy < 0 ? .up : .down
        }
        guard abs(dx) >= threshold else { return nil }
        return dx < 0 ? .left : .right
    }

    /// Pra baixo de manhã (04–10h) abre o briefing; à noite (21h–04h) o fechamento; no meio do dia, nada.
    static func route(for swipe: CapaSwipe, now: Date, region: Region) -> Route? {
        let hour = region.calendar.component(.hour, from: now)
        switch swipe {
        case .up: return .linha(date: region.calendar.startOfDay(for: now))
        case .down:
            if (4..<10).contains(hour) { return .bomDia }
            if hour >= 21 || hour < 4 { return .boaNoite }
            return nil
        case .left: return .dicas
        // O Bolso agora mora dentro dos Atalhos (prompt 25 · D): a capa abre o painel (`action`), não empilha a tela.
        case .right: return .bolso
        }
    }

    /// O que o deslize faz na capa: pra direita abre o painel de Atalhos por cima; os outros empilham a tela.
    static func action(for swipe: CapaSwipe, now: Date, region: Region) -> CapaAction? {
        if swipe == .right { return .atalhos }
        return route(for: swipe, now: now, region: region).map(CapaAction.route)
    }
}

enum CapaAction: Equatable, Sendable {
    case route(Route)
    case atalhos
}

// MARK: - Capa com foto

/// Quando a capa usa a foto do bairro (01b/01c, `CapaFoto.png`): **só quando a foto já está no aparelho** — a do Google
/// de um Must do bairro (Lugar aberto ou dia baixado) ou a do Commons já escolhida e baixada pelo pré-download do Wi-Fi.
/// A capa nunca baixa nada pra si; sem foto no disco (ou no Modo de Pouco Dados, que não deixa o pré-download trazer
/// fotos), fica a cor do lugar. Nos prints (`-debugScreen`), a cor é fixa e `-capaFoto` força a foto.
enum CapaPhotoPolicy {
    static func usesPhoto(hasDiskPhoto: Bool, forced: Bool, debugScreen: Bool) -> Bool {
        if forced { return true }
        if debugScreen { return false }
        return hasDiskPhoto
    }
}
