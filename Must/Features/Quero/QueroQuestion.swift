import Foundation
import Observation
import SwiftData

/// Quero… × pergunta (v9, `Assistente-3.png`). O Quero… só acha lugar físico; quando o texto é uma **pergunta**
/// ("dá tempo do Gyoen antes do pôr do sol?") ele mostra a faixa "✦ isso é uma pergunta" com a resposta curta e a ação
/// "Continuar no Assistente", sem misturar com a lista de lugares. Heurística no aparelho; a resposta vem do mesmo
/// `ChatModel` do Assistente (Foundation Models quando disponível, senão as respostas por palavra-chave).
enum QueroQuestion {
    /// Começos que fazem de uma frase uma pergunta mesmo sem "?". Em minúsculas e sem acento: o texto é normalizado antes.
    static let starters = ["da tempo", "quanto", "quantos", "quantas", "quando", "como", "posso", "vale", "e se", "o que", "por que",
                           "porque", "sera que", "qual", "quais", "preciso", "tem como", "da pra", "da para", "devo"]

    static func isQuestion(_ text: String) -> Bool {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        if raw.hasSuffix("?") || raw.hasSuffix("？") { return true }
        let normalized = normalize(raw)
        // Uma palavra só ("como", "café") nunca é pergunta sem interrogação.
        guard normalized.split(separator: " ").count >= 2 else { return false }
        return starters.contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// Até duas frases: o Quero… mostra a resposta curta, a conversa inteira fica no Assistente.
    static func shorten(_ answer: String, maxCharacters: Int = 220) -> String {
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        var out = ""
        var count = 0
        clean.enumerateSubstrings(in: clean.startIndex..., options: .bySentences) { sentence, _, _, stop in
            guard let sentence else { return }
            if !out.isEmpty, out.count + sentence.count > maxCharacters { stop = true; return }
            out += sentence
            count += 1
            if count >= 2 { stop = true }
        }
        if out.isEmpty { out = clean }
        if out.count > maxCharacters + 40 { out = String(out.prefix(maxCharacters)) + "…" }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static let fallback = "Não consegui responder aqui. Continue no Assistente."
}

/// A pergunta que o Quero… reconheceu e a resposta curta (`nil` enquanto o aparelho pensa).
struct QueroQuestionState: Equatable, Sendable {
    var text: String
    var answer: String?
}

/// Responde no aparelho, com o retrato do Assistente (board, dia, tempo). Nunca sai pra rede além do que o Assistente já faz.
/// Sem Foundation Models (ou nas perguntas que o `QuestionAnswerer` reconhece) a resposta é determinística.
@MainActor
enum QueroAnswerer {
    static func answer(_ question: String, context: ModelContext, region: Region, services: Services, useModel: Bool,
                       engine: (any DayEngine)? = nil) async -> String {
        let chat = ChatModel()
        let snapshot = AssistantSnapshot.make(context: context, region: region, services: services)
        let clock = engine.map { DayClock.read(engine: $0, region: region, context: context, at: snapshot.now, position: snapshot.here) }
        await chat.send(question, snapshot: snapshot, useModel: useModel, clock: clock)
        guard let reply = chat.messages.last(where: { $0.role == .assistant }), !reply.text.isEmpty else { return QueroQuestion.fallback }
        return QueroQuestion.shorten(reply.text)
    }
}
