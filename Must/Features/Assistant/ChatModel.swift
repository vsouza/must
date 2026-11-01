import Foundation
import FoundationModels
import Observation
import SwiftData

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var actions: [AssistantAction] = []
    var note: String?
    var quickReplies: [String] = []
    var applied: Set<String> = []
    var isStreaming = false
}

/// Conversa do Assistente (só da sessão; não persiste).
@MainActor
@Observable
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var busy = false
    private(set) var usesModel = false

    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private let collector = ActionCollector()

    static func instructions(_ s: AssistantSnapshot) -> String {
        """
        Você é o assistente do Must, um app pessoal de roteiro do Vinicius em \(s.cityName ?? s.region.displayName). Responda em português, curto e direto.
        Use as ferramentas pra consultar o board, o dia de hoje, gastos, tempo e último metrô. Pra sugerir um lugar, use searchBoard com o prato ou tipo (ex.: sushi) e escolha da lista que voltar. Só fale de lugares que as ferramentas retornarem — nunca invente.
        Pra trocar uma parada use swapStop: ela mostra cartões pro usuário confirmar; não diga que já trocou.
        Valores de dinheiro sempre com o símbolo da moeda (\(s.region.currencySymbol)).
        Agora são \(s.region.timeString(s.now)) e o usuário está em \(s.areaName).
        """
    }

    func send(_ text: String, snapshot: AssistantSnapshot, useModel: Bool) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        messages.append(ChatMessage(role: .user, text: question))

        usesModel = useModel && OnDeviceAI.isAvailable
        // Pedido reconhecido (gasto, troca, abertos, metrô, tempo, roteiro): resposta montada com os dados exatos —
        // o modelo pequeno do aparelho erra número. O modelo fica pras perguntas abertas, com as ferramentas.
        let deterministic = FallbackAssistant.answer(question, snapshot: snapshot)
        guard usesModel, !deterministic.recognized else {
            messages.append(ChatMessage(role: .assistant, text: deterministic.text, actions: deterministic.actions,
                                        note: deterministic.note, quickReplies: deterministic.quickReplies))
            return
        }

        // Sessão nova a cada pergunta, com o retrato atual (o histórico vai junto no prompt).
        let session = LanguageModelSession(tools: AssistantTools.all(snapshot, collector: collector),
                                           instructions: Self.instructions(snapshot))
        self.session = session
        let history = messages.dropLast().suffix(6).map { "\($0.role == .user ? "Usuário" : "Assistente"): \($0.text)" }.joined(separator: "\n")
        let prompt = history.isEmpty ? question : "Conversa até aqui:\n\(history)\n\nUsuário: \(question)"

        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        let index = messages.count - 1
        do {
            for try await partial in session.streamResponse(to: prompt) {
                messages[index].text = partial.content
            }
            let (actions, notes) = await collector.drain()
            messages[index].actions = actions
            messages[index].note = notes.first
            messages[index].quickReplies = actions.first.map { a in
                if case .swap = a.kind { return ["Trocar pelo \(a.place.name)", "Deixa como está"] }
                return []
            } ?? []
        } catch {
            Log.intelligence.error("chat: \(String(describing: error), privacy: .public) — respondendo sem modelo")
            let reply = FallbackAssistant.answer(question, snapshot: snapshot)
            messages[index] = ChatMessage(role: .assistant, text: reply.text, actions: reply.actions, note: reply.note, quickReplies: reply.quickReplies)
        }
        messages[index].isStreaming = false
    }

    /// Executa um cartão no app.
    func apply(_ action: AssistantAction, in messageId: UUID, context: ModelContext, region: Region) -> String? {
        switch action.kind {
        case .swap(let stopId, let replacing):
            guard let uuid = UUID(uuidString: stopId),
                  let stop = try? context.fetch(FetchDescriptor<Stop>(predicate: #Predicate { $0.id == uuid })).first else {
                return "Essa parada não existe mais."
            }
            let placeId = action.place.id
            guard let place = try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.id == placeId })).first else { return nil }
            stop.swappedFrom = stop.place?.id
            stop.place = place
            stop.isException = false
            try? context.save()
            mark(messageId, action.id)
            Log.intelligence.info("troca aplicada: \(replacing, privacy: .public) → \(place.name, privacy: .public)")
            return "Trocado: \(replacing) → \(place.name)."
        case .go:
            MapsLinks.openApple(to: .init(latitude: action.place.lat, longitude: action.place.lng), name: action.place.name, mode: .transit)
            return nil
        case .markDone:
            return nil // a view abre o Registrar gasto
        }
    }

    private func mark(_ messageId: UUID, _ actionId: String) {
        guard let i = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[i].applied.insert(actionId)
    }

    func confirm(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text))
    }
}
