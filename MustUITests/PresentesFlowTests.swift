import XCTest

/// Presentes como lista fácil (09/11/2026): campo "Novo presente…" no fim, deslizar pra apagar com desfazer.
/// Confere no app de verdade o que os testes de unidade não alcançam (o campo, o swipe e a barra de desfazer).
final class PresentesFlowTests: MustUITestCase {
    private let config = Config(area: .jp, net: .offline)

    func testAddInlineThenDeleteAndUndo() {
        launch(config, screen: "presentes")

        let fieldQuery = app.textFields.matching(NSPredicate(format: "label == 'Novo presente' OR placeholderValue BEGINSWITH 'Novo presente'")).firstMatch
        guard let field = scrollTo({ fieldQuery.exists ? fieldQuery : nil }) else {
            return XCTFail("campo Novo presente não apareceu")
        }
        // Até o fim da lista: o campo pode estar "tocável" por baixo da faixa agora.
        app.swipeUp(velocity: .fast); app.swipeUp(velocity: .fast)
        field.tap()
        // O campo se redesenha com o foco: digita no que estiver com o teclado.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4), "o teclado não abriu")
        app.typeText("Pocky de matcha pra Ana\n")

        // O grupo da Ana pode estar fora da tela: a linha do campo confirma o que entrou e onde.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Adicionado: Pocky de matcha, em Ana")).firstMatch
            .waitForExistence(timeout: 4), "sem a confirmação do que entrou")
        attachScreenshot("presentes-novo")

        // Só a Ana: a linha nova aparece no filtro dela.
        if app.keyboards.count > 0 { app.swipeDown() }
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Ana")).firstMatch.tap()
        let row = text("Pocky de matcha")
        XCTAssertTrue(row.waitForExistence(timeout: 4), "o presente novo não entrou na lista da Ana")

        // Apagar pelo deslizar e desfazer: volta e continua depois do prazo de 5 s.
        row.swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Apagar")).firstMatch
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        XCTAssertTrue(text("Apagado: Pocky de matcha").waitForExistence(timeout: 3), "sem a barra de desfazer")
        attachScreenshot("presentes-desfazer")
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "desfazer")).firstMatch.tap()
        sleep(6)
        XCTAssertTrue(text("Pocky de matcha").exists, "desfazer não devolveu o presente")

        // Apagar de novo e deixar o prazo passar: some de vez.
        text("Pocky de matcha").swipeLeft()
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        sleep(6)
        XCTAssertFalse(text("Pocky de matcha").exists, "o presente apagado voltou")
        XCTAssertFalse(text("Apagado: Pocky de matcha").exists, "a barra de desfazer não sumiu")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Adicionado: Pocky")).firstMatch.exists, "a confirmação ficou depois de apagar")
        assertAlive("presentes", config)
    }

    private func text(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
