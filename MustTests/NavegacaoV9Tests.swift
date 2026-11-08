import Foundation
import Testing
@testable import Must

/// Navegação v9 (prompt 31): rota das Dicas, abas, barra e a detecção de pergunta do Quero….
@MainActor
struct NavegacaoV9Tests {
    @Test func dicasAbremOAssistenteSemEmpilharTela() {
        let router = AppRouter()
        router.push(.dicas, on: .hoje)
        #expect(router.sheet == .assistant)
        #expect(router.paths[.hoje]?.isEmpty ?? true)
    }

    @Test func linkDoAssistenteAbreASheet() {
        let router = AppRouter()
        router.handle(url: URL(string: "must://assistente")!, region: .jp)
        #expect(router.sheet == .assistant)
    }

    @Test func presenteNovoEmpilhaNaAbaMusts() {
        let router = AppRouter()
        router.push(.presenteNovo, on: .musts)
        #expect(router.tab == .musts)
        #expect(router.paths[.musts]?.last == .presenteNovo)
    }

    @Test func barraTemQuatroAbasComExplorarNoLugarDoGuia() {
        #expect(MustTab.allCases.map(\.title) == ["Hoje", "Explorar", "Musts", "Viagem"])
    }

    @Test func barraSomeComOQueroAberto() {
        let router = AppRouter()
        #expect(!router.hidesNavBar)
        router.setQuero("capa", open: true)
        #expect(router.hidesNavBar)
    }

    @Test func idsDeSheetDistinguemAsPerguntas() {
        #expect(AppRouter.Sheet.assistantAsk(text: "a").id != AppRouter.Sheet.assistantAsk(text: "b").id)
        #expect(AppRouter.Sheet.assistantAsk(text: "a").id != AppRouter.Sheet.assistant.id)
    }

    @Test func perguntaPorInterrogacao() {
        #expect(QueroQuestion.isQuestion("dá tempo do Gyoen antes do pôr do sol?"))
        #expect(QueroQuestion.isQuestion("ramen?"))
        #expect(QueroQuestion.isQuestion("  vale a pena o teamLab？ "))
    }

    @Test func perguntaPorComeco() {
        #expect(QueroQuestion.isQuestion("dá tempo do Gyoen antes do pôr do sol"))
        #expect(QueroQuestion.isQuestion("quanto custa o tour"))
        #expect(QueroQuestion.isQuestion("como chegar no Gyoen"))
        #expect(QueroQuestion.isQuestion("posso entrar de tênis no templo"))
        #expect(QueroQuestion.isQuestion("e se chover amanhã"))
        #expect(QueroQuestion.isQuestion("O que fazer na chuva"))
    }

    @Test func vontadeNaoEPergunta() {
        #expect(!QueroQuestion.isQuestion("comprar um Seiko"))
        #expect(!QueroQuestion.isQuestion("café"))
        #expect(!QueroQuestion.isQuestion("como"))
        #expect(!QueroQuestion.isQuestion("comer ramen"))
        #expect(!QueroQuestion.isQuestion("comodidade perto"))
        #expect(!QueroQuestion.isQuestion(""))
    }

    @Test func respostaCurtaTemNoMaximoDuasFrases() {
        let long = "Hoje não: o Gyoen fechou às 16:30. Amanhã abre 9h. O pôr do sol é às 16:31. Último ingresso às 16:00."
        let short = QueroQuestion.shorten(long)
        #expect(short.hasPrefix("Hoje não"))
        #expect(!short.contains("Último ingresso"))
    }
}
