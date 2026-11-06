import XCTest

/// Digitação dirigida em cada campo de texto do app (rodada 23 · G): rajadas, apagar, colar, números gigantes,
/// fechar pela metade. Cada cenário roda na matriz padrão (BH/JP/IT normais, BH lenta e offline).
final class FieldsTypingTests: MustUITestCase {

    /// Quero… (o `+` da barra): vontade, buscar, e as abas Link / Texto / Nome por cima.
    func testQuero() {
        for config in matrix() {
            launch(config, screen: "quero")
            let field = app.textFields["O que você quer"]
            guard field.waitForExistence(timeout: 8) else { XCTFail("[\(config)] Quero sem campo"); continue }
            hammer(field, config, rounds: 2)
            field.typeText("\n")
            assertAlive("Quero buscar", config)
            clear(field)
            field.typeText("quero comer um ramen\n")
            sleep(2)
            assertAlive("Quero resultado", config)
            dismissKeyboard()
            for tab in ["Texto", "Link", "Nome"] {
                let button = app.buttons[tab]
                guard button.waitForExistence(timeout: 3), button.isHittable else { continue }
                button.tap()
                assertAlive("Quero › \(tab)", config)
                let id = ["Texto": "colar.text", "Link": "add.link", "Nome": "buscar.query"][tab]!
                if let inner = element(id, timeout: 5) {
                    if tab == "Texto" { paste(Self.longText, into: inner) } else { hammer(inner, config, rounds: 1) }
                }
                assertAlive("Quero › \(tab) digitando", config)
                swipeSheetDown()
                _ = field.waitForExistence(timeout: 3)
            }
            assertAlive("Quero fim", config)
        }
    }

    /// Adicionar › Link: lixo, URL quebrada, link do Maps; e a legenda colada quando o link não traz texto.
    func testAddLink() {
        for config in matrix() {
            launch(config, screen: "adicionar")
            guard let field = element("add.link") else { XCTFail("[\(config)] sem campo de link"); continue }
            hammer(field, config, rounds: 1)
            clear(field)
            for url in ["htp:/ /quebrado 🍜", "https://www.instagram.com/reel/ABC123/", "https://maps.app.goo.gl/xyz",
                        "https://www.google.com/maps/place/Xapuri/@-19.8517,-43.9733,17z"] {
                field.tap()
                clear(field)
                field.typeText(url + "\n")
                sleep(1)
                guard assertAlive("link \(url)", config) else { break }
                if let caption = element("add.caption", timeout: 2) { paste(Self.longText, into: caption) }
            }
            assertAlive("Adicionar › Link", config)
        }
    }

    /// Adicionar › Texto: 5.000 caracteres colados, emoji, japonês e italiano; "Ler texto" e editar de novo.
    func testColarTexto() {
        for config in matrix() {
            launch(config, screen: "colar-texto")
            guard let field = element("colar.text") else { XCTFail("[\(config)] sem campo do Colar texto"); continue }
            paste(Self.longText, into: field)
            field.typeText("\n📍 Ichiran Shibuya\n📍 Trattoria da Enzo al 29\n")
            assertAlive("colar 5.000", config)
            dismissKeyboard()
            if let read = button(startingWith: ["Ler texto"], timeout: 3) {
                read.tap()
                // Lê no aparelho: espera sair do "Lendo o texto…" (sem spinner infinito: 30 s no máximo).
                let reading = app.staticTexts["Lendo o texto…"]
                let deadline = Date().addingTimeInterval(30)
                while reading.exists, Date() < deadline { sleep(1) }
                XCTAssertFalse(reading.exists, "[\(config)] Colar texto ficou lendo mais de 30 s")
            }
            assertAlive("Ler texto", config)
            rotate()
            backgroundAndBack()
            assertAlive("Colar texto depois do fundo", config)
        }
    }

    /// Buscar por nome com o Autocomplete de mentira: digitar, apagar, digitar de novo, escolher.
    func testBuscarNome() {
        for config in matrix() {
            launch(config, screen: "buscar-nome:")
            guard let field = element("buscar.query") else { XCTFail("[\(config)] sem campo do Buscar por nome"); continue }
            hammer(field, config, rounds: 2, texts: ["ko", "ffee", " mam", "🍜", "東京"])
            clear(field)
            field.typeText("koffee mam")
            let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'koffee'")).firstMatch
            if first.waitForExistence(timeout: 6) { first.tap() }
            assertAlive("Buscar por nome › escolher", config)
            swipeSheetDown()
            assertAlive("Buscar por nome › fechar", config)
        }
    }

    /// Montar › "ou diga…": texto livre e o parser do dia.
    func testMontarOuDiga() {
        for config in matrix() {
            launch(config, screen: "montar")
            guard let field = element("montar.ask") ?? scrollTo({ element("montar.ask", timeout: 0.5) }) else {
                XCTFail("[\(config)] sem o \"ou diga\""); continue
            }
            hammer(field, config, rounds: 1)
            clear(field)
            field.typeText("templo cedo, ramen, andar pouco, jantar bom 🍣\n")
            sleep(2)
            assertAlive("Montar ou diga", config)
        }
    }

    /// Assistente: várias perguntas seguidas, sem esperar a resposta.
    func testAssistente() {
        for config in matrix() {
            launch(config, screen: "assistente")
            guard let field = element("assistant.input") else { XCTFail("[\(config)] sem campo do Assistente"); continue }
            for question in ["tô cansado, troca o bar de hoje", "quanto já gastei? 💸", "東京 ramen perto",
                             String(Self.longText.prefix(600))] {
                field.tap()
                field.typeText(question + "\n")
                guard assertAlive("Assistente \(question.prefix(20))", config) else { break }
            }
            sleep(3)
            assertAlive("Assistente respostas", config)
        }
    }

    /// Gasto: o teclado próprio, rápido, com vírgula e apagar.
    func testGasto() {
        for config in matrix() {
            launch(config, screen: "gasto")
            guard app.buttons["1"].waitForExistence(timeout: 8) else { XCTFail("[\(config)] sem teclado do Gasto"); continue }
            let sequence = ["1", "2", ",", "5", "5", "5", "Apagar", "Apagar", "9", "9", "9", "9", "9", "9", "9", "9", "9", "9",
                            "000", ",", "0", "Apagar", "Apagar", "Apagar"]
            for key in sequence where app.buttons[key].exists { app.buttons[key].tap() }
            assertAlive("Gasto teclado", config)
        }
    }

    /// SOS › Seu seguro / Seu plano: todos os campos, depois Guardar.
    func testSOSSeguro() {
        for config in matrix() {
            launch(config, screen: "sos")
            guard let line = scrollTo({ button(startingWith: ["Seu seguro", "Seu plano"], timeout: 1) }) else {
                XCTFail("[\(config)] SOS sem a linha do seguro"); continue
            }
            line.tap()
            typeIntoAllFields(config, swipes: 2)
            assertAlive("SOS seguro", config)
            if let save = button(startingWith: ["Guardar"], timeout: 3) ?? scrollTo({ button(startingWith: ["Guardar"], timeout: 0.5) }) {
                save.tap()
            }
            assertAlive("SOS guardar", config)
        }
    }

    /// Carteira: um item novo com todos os campos (saldo gigante incluído).
    func testCarteira() {
        for config in matrix(default: [Config(area: .jp, net: .normal), Config(area: .bh, net: .normal), Config(area: .it, net: .offline)]) {
            launch(config, screen: "carteira")
            let add = app.buttons["Adicionar à carteira"]
            guard add.waitForExistence(timeout: 8) else { XCTFail("[\(config)] Carteira sem o +"); continue }
            add.tap()
            typeIntoAllFields(config, swipes: 3)
            assertAlive("Carteira campos", config)
            swipeSheetDown()
            assertAlive("Carteira fechar pela metade", config)
        }
    }

    /// Ingresso › Revisar (PDF de exemplo na caixa): preço com 23 dígitos relia `Int(_:)` e derrubava a tela.
    func testIngressoRevisar() {
        for config in matrix(default: [Config(area: .jp, net: .normal), Config(area: .bh, net: .slow)]) {
            launch(config, screen: "ingresso-revisar")
            sleep(4)
            typeIntoAllFields(config, swipes: 3)
            assertAlive("Revisar ingresso", config)
        }
    }

    /// Lista art (KindExtraFields): "inteira", "estudante", "duração" com números gigantes — o crash do `Int(1e20)`.
    func testArtListExtraFields() {
        for config in matrix(default: [Config(area: .bh, net: .normal), Config(area: .jp, net: .normal), Config(area: .it, net: .normal)]) {
            launch(config, screen: "lista:art")
            guard let add = scrollTo({ button(startingWith: ["Adicionar à mão", "Nada aqui ainda"], timeout: 1) }) else {
                XCTFail("[\(config)] Lista art sem Adicionar à mão"); continue
            }
            add.tap()
            guard element("edit.name") != nil else { XCTFail("[\(config)] Novo lugar não abriu"); continue }
            typeIntoAllFields(config, swipes: 5)
            assertAlive("campos do tipo art com números gigantes", config)
        }
    }
}
