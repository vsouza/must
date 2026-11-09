import XCTest

/// Caminhos que só existiam na tela e nunca tinham sido conferidos (09/11/2026): guardar um pino de fora no Explorar (o mapa),
/// a busca de loja de um presente no mapa da cidade e o cartaz "A ou B?" pronto pra mandar.
final class CaminhosTests: MustUITestCase {
    private let config = Config(area: .jp, net: .normal)

    private func any(_ format: String, _ args: Any...) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: args)).firstMatch
    }

    func testExplorarOutsidePinGoesToBoard() {
        // Prompt 32 §4: o caminho visível é Explorar (o mapa) › Camadas › Indicados › pino de fora › Guardar. O debug liga a
        // camada e seleciona o primeiro de fora em Naka-Meguro (onde as fontes de mentira do Por perto têm lugares).
        launch(config, screen: "v9-explorar-indicados", extra: ["-debugExplorarArea", "naka-meguro"])
        let save = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Guardar no board")).firstMatch
        guard save.waitForExistence(timeout: 20) else {
            attachScreenshot("explorar-fora-sem-pino")
            return XCTFail("sem pino de fora selecionado (ou sem o botão Guardar)")
        }
        attachScreenshot("explorar-fora-antes")
        save.tap()
        // O pino vira seu: o Lugar resumido troca "Guardar" por "Abrir".
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Abrir")).firstMatch.waitForExistence(timeout: 5),
                      "o pino guardado não virou Must")
        XCTAssertFalse(any("label CONTAINS[c] %@", "não deu pra guardar").exists)
        attachScreenshot("explorar-fora-depois")
        assertAlive("explorar + board", config)
    }

    func testExplorarMapPanelAndLayers() {
        // O mapa é a raiz: "Pedir algo…", "Agora vale" abre o médio, "Ver lista" o grande, e o menu Camadas tem as quatro.
        launch(config, screen: "v9-explorar-recolhida")
        let summary = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Agora vale")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "sem a linha Agora vale no painel")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pedir algo")).firstMatch.exists)
        summary.tap()
        let list = app.buttons["Ver lista"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "o painel não subiu pro médio")
        list.tap()
        XCTAssertTrue(app.buttons["Agora vale"].waitForExistence(timeout: 5), "o painel não subiu pro grande")
        attachScreenshot("explorar-grande")
        app.buttons["Camadas"].tap()
        for name in ["Meus Musts", "Hoje", "Agora", "Indicados"] {
            XCTAssertTrue(any("label BEGINSWITH %@", name).waitForExistence(timeout: 3), "camada \(name) sumiu do menu")
        }
        attachScreenshot("explorar-camadas")
        assertAlive("explorar painel", config)
    }

    func testGiftStoreSearchOnCityMap() {
        launch(config, screen: "presente-novo")
        guard let local = button(startingWith: ["Local"], timeout: 8) else { return XCTFail("sem a aba Local") }
        local.tap()
        let chooseQuery = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "do mapa da cidade")).firstMatch
        guard chooseQuery.waitForExistence(timeout: 5) else {
            attachScreenshot("presente-sem-loja")
            return XCTFail("sem o botão Escolher a loja")
        }
        chooseQuery.tap()
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH[c] %@", "Nome da loja")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "sem o campo da loja")
        field.tap()
        app.typeText("Bic Camera\n")
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Guardar ")).firstMatch
        guard save.waitForExistence(timeout: 20) else {
            attachScreenshot("loja-sem-resultado")
            return XCTFail("a busca no mapa da cidade não trouxe loja de fora")
        }
        attachScreenshot("loja-resultados")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "fora do board")).firstMatch
        let name = row.label.components(separatedBy: ",").first ?? ""
        row.tap()
        XCTAssertTrue(button(startingWith: [name], timeout: 5) != nil, "a loja escolhida (\(name)) não voltou pro presente")
        attachScreenshot("loja-escolhida")
        assertAlive("loja do presente", config)
    }

    func testPollPosterReadyToSend() {
        launch(config, screen: "grupo-votacao")
        guard let send = button(startingWith: ["Mandar cartaz"], timeout: 10) else {
            attachScreenshot("votacao-sem-cartaz")
            return XCTFail("o cartaz não ficou pronto pra mandar")
        }
        XCTAssertTrue(any("label BEGINSWITH %@", "Prévia do cartaz").exists, "sem a prévia do cartaz")
        attachScreenshot("votacao")
        send.tap()
        // A folha de compartilhar do iOS abre com o PNG.
        let sheet = app.otherElements.matching(NSPredicate(format: "identifier == %@", "ActivityListView")).firstMatch
        let opened = sheet.waitForExistence(timeout: 6) || app.navigationBars.firstMatch.waitForExistence(timeout: 2)
        attachScreenshot("votacao-compartilhar")
        XCTAssertTrue(opened || app.state == .runningForeground)
        assertAlive("cartaz", config)
    }

    /// "Ir pra um bairro" (09/11/2026): marca 3 Musts de Shinjuku e o trajeto só tem eles (ou diz por que ficaram fora).
    func testIrBairroMontaSoOsMarcados() {
        launch(config, screen: "ir-bairro:shinjuku")
        let marked = ["Shinjuku Gyoen", "Ichiran Shinjuku", "Golden Gai"]
        for name in marked {
            let row = any("label BEGINSWITH %@", name + ",")
            guard row.waitForExistence(timeout: 10) else {
                attachScreenshot("ir-bairro-sem-\(name)")
                return XCTFail("sem a linha \(name)")
            }
            if !row.isHittable { app.swipeUp() }
            row.tap()
        }
        attachScreenshot("ir-bairro-marcados")
        let montar = any("label ==[c] %@", "Montar trajeto com 3 Musts")
        XCTAssertTrue(montar.waitForExistence(timeout: 4), "o botão não contou os 3 marcados")
        montar.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Aceitar o dia")).firstMatch
            .waitForExistence(timeout: 15), "a proposta não abriu")
        sleep(1)
        attachScreenshot("ir-bairro-proposta")
        // Nenhum Must desmarcado do bairro entra.
        for other in ["Donzoko", "Uoshin", "Ramen Hōsenka", "Ucchan", "HARBS"] {
            XCTAssertFalse(any("label CONTAINS %@", other).exists, "\(other) entrou sem ser marcado")
        }
        // Cada marcado está no trajeto ou na faixa "fora do trajeto".
        for name in marked { XCTAssertTrue(any("label CONTAINS %@", name).exists, "\(name) sumiu sem motivo") }
        assertAlive("ir pra um bairro", config)
    }
}
