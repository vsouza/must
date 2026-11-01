import Foundation
import FoundationModels

/// Modelo no aparelho (Apple Foundation Models).
enum OnDeviceAI {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Por que não dá pra usar (pra mostrar em Ajustes).
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "este iPhone não tem Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence desligada nos Ajustes do iOS"
        case .unavailable(.modelNotReady): return "modelo ainda baixando"
        case .unavailable: return "modelo no aparelho indisponível"
        }
    }
}

/// Saída estruturada do modelo pro "ou diga…" (mapeada pra `DayIntent`).
@Generable
struct GeneratedDayIntent {
    @Guide(description: "Tipo de dia pedido, ou none", .anyOf(["none", "free", "shopping", "night", "photo", "temples", "rest"]))
    var kind: String
    @Guide(description: "Listas que o usuário quer incluir (eat, drink, see, listen, shop, photo, sport)")
    var turnOn: [String]
    @Guide(description: "Listas que o usuário quer tirar (eat, drink, see, listen, shop, photo, sport)")
    var turnOff: [String]
    @Guide(description: "Orçamento do dia em número, ou 0 se não falou")
    var budget: Int
    @Guide(description: "Quanto andar", .anyOf(["none", "low", "normal", "high"]))
    var walk: String
    @Guide(description: "Nomes de lugares que ele quer que entrem")
    var mustInclude: [String]
    @Guide(description: "Nomes de lugares que ele quer tirar")
    var mustExclude: [String]
    @Guide(description: "Sub-listas preferidas, ex.: Ramen, Sushi, Café, Bar, Templos, Arte, Mirante")
    var preferSubs: [String]
    @Guide(description: "Quer começar cedo?")
    var startEarly: Bool
    @Guide(description: "Pediu duas refeições na mesma janela (ex.: sushi e ramen no almoço)?")
    var mealsException: Bool
    @Guide(description: "Pediu algo especial/caro (jantar bom, caprichar)?")
    var splurge: Bool
}

/// Texto/voz → parâmetros do dia. Foundation Models quando disponível; senão palavras-chave.
enum IntentParser {
    static let instructions = """
    Você converte pedidos curtos em português sobre como montar um dia de passeio em parâmetros.
    Não invente lugares: em mustInclude/mustExclude use só nomes que o usuário disse.
    Se algo não foi dito, use none, 0, listas vazias ou false.
    """

    static func parse(_ text: String, placeNames: [String], useModel: Bool) async -> DayIntent {
        let regex = RegexIntentParser.parse(text, placeNames: placeNames)
        guard useModel, OnDeviceAI.isAvailable, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return regex }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text, generating: GeneratedDayIntent.self)
            let intent = map(response.content, placeNames: placeNames)
            Log.intelligence.info("intenção no aparelho: \(String(describing: intent), privacy: .private)")
            return merge(intent, regex)
        } catch {
            Log.intelligence.error("intenção: \(error.localizedDescription, privacy: .public) — usando palavras-chave")
            return regex
        }
    }

    static func map(_ g: GeneratedDayIntent, placeNames: [String]) -> DayIntent {
        var intent = DayIntent()
        intent.kind = DayKind(rawValue: g.kind)
        intent.walk = WalkLevel(rawValue: g.walk)
        intent.budget = g.budget > 0 ? Double(g.budget) : nil
        for r in g.turnOn.compactMap(StopRole.init(rawValue:)) { intent.roles[r] = .on }
        for r in g.turnOff.compactMap(StopRole.init(rawValue:)) { intent.roles[r] = .off }
        // Só nomes que existem no board.
        func board(_ names: [String]) -> [String] {
            names.compactMap { n in placeNames.first { PlaceMatcher.similar($0, n) || $0.localizedCaseInsensitiveContains(n) } }
        }
        intent.mustInclude = board(g.mustInclude)
        intent.mustExclude = board(g.mustExclude)
        intent.preferSubs = g.preferSubs
        intent.startEarly = g.startEarly ? true : nil
        intent.mealsException = g.mealsException
        intent.splurge = g.splurge
        return intent
    }

    /// O modelo manda; o regex completa o que ele deixou vazio.
    static func merge(_ model: DayIntent, _ regex: DayIntent) -> DayIntent {
        var out = model
        out.kind = model.kind ?? regex.kind
        out.walk = model.walk ?? regex.walk
        out.budget = model.budget ?? regex.budget
        out.startEarly = model.startEarly ?? regex.startEarly
        for (role, mode) in regex.roles where out.roles[role] == nil { out.roles[role] = mode }
        if out.mustInclude.isEmpty { out.mustInclude = regex.mustInclude }
        if out.mustExclude.isEmpty { out.mustExclude = regex.mustExclude }
        out.preferSubs = Array(Set(model.preferSubs + regex.preferSubs))
        out.mealsException = model.mealsException || regex.mealsException
        out.splurge = model.splurge || regex.splurge
        out.splurgeWindow = regex.splurgeWindow
        return out
    }
}
