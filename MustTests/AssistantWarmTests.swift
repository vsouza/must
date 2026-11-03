import Testing
@testable import Must

/// Modelo no aparelho (prompt 18 · A.7): nenhuma sessão na abertura do app; aquecer só com o Assistente aberto
/// e só com o modelo ligado.
@MainActor
struct AssistantWarmTests {
    @Test func criarOAssistenteNaoCriaSessao() {
        let before = ChatModel.sessionsMade
        _ = ChatModel()
        #expect(ChatModel.sessionsMade == before)
    }

    @Test func aquecerSemModeloNaoCriaSessao() throws {
        let before = ChatModel.sessionsMade
        let chat = ChatModel()
        // Modelo desligado nas Ajustes (ou sem IA no aparelho): nada de sessão, em nenhum caso.
        chat.warm(snapshot: try tokyoSnapshot(), useModel: false)
        #expect(ChatModel.sessionsMade == before)
    }

    @Test func aquecerRespeitaIAIndisponivel() throws {
        let before = ChatModel.sessionsMade
        let chat = ChatModel()
        chat.warm(snapshot: try tokyoSnapshot(), useModel: true)
        // Com a IA do aparelho disponível, aquece uma sessão; sem ela, não cria nada.
        #expect(ChatModel.sessionsMade == before + (OnDeviceAI.isAvailable ? 1 : 0))
    }
}
