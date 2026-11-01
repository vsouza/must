import Foundation

/// Resposta do assistente: texto, cartões de ação, frase de justificativa e respostas rápidas.
struct AssistantReply: Sendable {
    var text: String
    var actions: [AssistantAction] = []
    var note: String?
    var quickReplies: [String] = []
    /// Entendeu o pedido (dados exatos); falso = só o texto de ajuda.
    var recognized = true
}

/// Assistente sem modelo (aparelho sem Apple Intelligence, ou modelo desligado em Ajustes):
/// entende os pedidos mais comuns por palavra-chave e responde com os mesmos dados.
enum FallbackAssistant {
    static func answer(_ question: String, snapshot s: AssistantSnapshot) -> AssistantReply {
        let t = question.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        var parts: [String] = []
        var actions: [AssistantAction] = []
        var note: String?
        var quick: [String] = []

        if has("gastei", "gasto", "quanto ja", "quanto foi", "fui", "orcamento", "meta") {
            parts.append(AssistantEngine.spentText(s))
        }
        if has("troca", "trocar", "substitui", "outro lugar", "no lugar") {
            if let stop = AssistantEngine.targetStop(s, text: question) {
                let cheaper = has("barato", "economi")
                let nearAnchor = has("jantar", "reserva", "perto do")
                let options = AssistantEngine.swapCandidates(s, stop: stop, cheaper: cheaper, nearAnchor: nearAnchor)
                if options.isEmpty {
                    parts.append("Não achei outro \(s.listName(stop.place)) elegível pro horário do \(stop.place.name).")
                } else {
                    parts.append("No lugar do \(stop.place.name), achei \(options.count == 1 ? "uma opção" : "\(options.count) opções") do board:")
                    actions = options.enumerated().map { i, o in
                        AssistantAction(kind: .swap(stopId: stop.id, replacing: stop.place.name), place: o.place, meta: o.note, highlighted: i == 0)
                    }
                    note = "\(stop.place.name) fica pro outro dia — o resto do roteiro não muda."
                    if let first = options.first { quick.append("Trocar pelo \(first.place.name)") }
                    quick.append("Deixa sem \(stop.place.sub?.lowercased() ?? "essa parada")")
                }
            } else {
                parts.append("Não tem dia montado hoje pra trocar parada. Monta pelo Hoje → Montar o dia.")
            }
        }
        if has("sugere", "sugestao", "recomenda", "indica", "onde comer", "onde beber", "onde tomar", "um lugar pra", "algum lugar") && !has("troca") {
            let found = AssistantEngine.search(s, query: question).filter { AssistantEngine.sameCity($0, s) && !$0.done }
            if found.isEmpty {
                parts.append("Não achei nada assim no board de \(s.cityName ?? s.region.displayName). Quer adicionar por link?")
            } else {
                let top = found.prefix(3)
                parts.append("Do seu board: " + top.map { "\($0.name) (\($0.area ?? s.listName($0)), \(s.region.money($0.cost)))" }.joined(separator: ", ") + ".")
                actions += top.prefix(2).enumerated().map { i, p in
                    AssistantAction(kind: .go, place: p, meta: [p.area, p.sub, s.region.money(p.cost)].compactMap { $0 }.joined(separator: " · "), highlighted: i == 0)
                }
            }
        }
        if has("aberto", "abertos", "perto", "por aqui", "agora") && !has("troca", "sugere", "recomenda", "indica") {
            let (places, confirmed) = AssistantEngine.openNow(s)
            if places.isEmpty {
                parts.append("Não achei musts num raio de 1,5 km de \(s.areaName).")
            } else {
                let names = places.prefix(4).map(\.name).joined(separator: ", ")
                parts.append(confirmed ? "Abertos agora perto de \(s.areaName): \(names)."
                             : "Perto de \(s.areaName): \(names) — sem horário confirmado (sincronize em Ajustes).")
                actions += places.prefix(2).enumerated().map { i, p in
                    AssistantAction(kind: .go, place: p, meta: [p.area, s.listName(p)].compactMap { $0 }.joined(separator: " · "), highlighted: i == 0)
                }
            }
        }
        if has("ultimo metro", "ultimo trem", "metro pra casa", "trem pra casa", "voltar pra casa") {
            parts.append(AssistantEngine.lastTrainText(s))
        }
        if has("tempo", "chuva", "chover", "frio", "calor", "previsao") {
            parts.append(AssistantEngine.weatherText(s, tomorrow: has("amanha")))
        }
        if has("roteiro", "plano", "o que vem", "proxima", "hoje tem", "programa") {
            parts.append(AssistantEngine.planText(s))
            if let next = s.nextStop {
                actions.append(AssistantAction(kind: .go, place: next.place, meta: "próxima · \(s.region.timeString(next.at))", highlighted: true))
            }
        }
        if has("feito", "marca", "terminei", "acabei") {
            if let next = s.nextStop {
                parts.append("Quer marcar 済 no \(next.place.name)?")
                actions.append(AssistantAction(kind: .markDone, place: next.place, meta: "registrar o gasto e marcar 済", highlighted: true))
            }
        }
        if parts.isEmpty {
            parts.append("Consigo: ver o que está aberto perto, trocar uma parada do dia, dizer quanto você gastou, o último metrô e o tempo. É só pedir.")
            quick = ["O que está aberto perto de mim?", "Quanto gastei hoje?"]
            return AssistantReply(text: parts.joined(separator: " "), actions: [], note: nil, quickReplies: quick, recognized: false)
        }
        return AssistantReply(text: parts.joined(separator: " "), actions: actions, note: note, quickReplies: quick)
    }

    /// Sugestões da tela vazia, montadas a partir do estado (há dia? está perto de algo? passou da meta?).
    static func suggestions(_ s: AssistantSnapshot) -> [String] {
        var list = ["O que está aberto perto de mim?"]
        if let lunch = s.stops.first(where: { !$0.done && $0.place.role == .eat && !$0.isAnchor }) {
            list.append(lunch.place.cost > 0 ? "Troca o \(DaySolver.window(at: AssistantEngine.minute(lunch.at, s)).label) por algo mais barato"
                                             : "Troca o \(lunch.place.name)")
        } else {
            list.append("O que tem no roteiro de hoje?")
        }
        list.append(s.spentDay > s.budget ? "Quanto passei da meta hoje?" : "Quanto gastei hoje?")
        list.append(s.region == .jp ? "Qual o último metrô pra casa?" : "Vai chover amanhã?")
        return list
    }
}
