import XCTest

/// Prioridade nº 1 da rodada 23 · G: "ao digitar na tela de adicionar na lista o app quebra" (Vinicius).
/// Caminho real: Musts › Lista › "Adicionar à mão" (`EditPlaceView(newInListId:)`), todos os campos, rajadas, apagar,
/// colar, girar, mandar pro fundo, fechar pela metade e — o suspeito — o GPS trocar de região com a sheet aberta.
final class AddToListTypingTests: MustUITestCase {

    /// Abre a Lista (`-debugScreen lista:<id>`) e toca "Adicionar à mão" (ou "Nada aqui ainda", lista vazia).
    @discardableResult
    func openNewPlaceFromList(_ config: Config, list: String = "eat", extra: [String] = []) -> Bool {
        launch(config, screen: "lista:\(list)", extra: extra)
        guard let add = scrollTo({ button(startingWith: ["Adicionar à mão", "Nada aqui ainda"], timeout: 1) }) else {
            XCTFail("[\(config)] sem o botão Adicionar à mão na Lista \(list)")
            attachScreenshot("sem-adicionar-\(config)")
            return false
        }
        safeTap(add)
        guard element("edit.name") != nil else {
            XCTFail("[\(config)] o Novo lugar não abriu")
            attachScreenshot("sem-novo-lugar-\(config)")
            return false
        }
        return true
    }

    /// Todos os campos do Novo lugar, em rajadas, com apagar e redigitar.
    func typeAllFields(_ config: Config) {
        let ids = ["edit.name", "edit.nameLocal", "edit.price", "edit.area", "edit.notes"]
        for id in ids {
            guard let field = element(id, timeout: 4) ?? scrollTo({ element(id, timeout: 0.5) }) else {
                XCTFail("[\(config)] sem o campo \(id)"); continue
            }
            switch id {
            case "edit.price":
                safeTap(field)
                for text in ["12,50", "1.250,00", "abc", "9999999999", ",,,", ".5"] {
                    field.enter(text)
                    clear(field)
                }
                field.enter("38,90")
            case "edit.nameLocal":
                hammer(field, config, rounds: 2, texts: ["一蘭 渋谷店", "ラーメン", "Ñ🍜"])
            default:
                hammer(field, config, rounds: 2)
            }
            guard assertAlive("digitando \(id)", config) else { return }
        }
    }

    // MARK: Cenários

    /// O fluxo do relato: lista, +, digitar em tudo, salvar. Em BH, JP, IT e com rede lenta/offline.
    func testTypeEverythingAndSave() {
        for config in matrix() {
            guard openNewPlaceFromList(config) else { continue }
            typeAllFields(config)
            guard assertAlive("antes de salvar", config) else { continue }
            dismissKeyboard()
            if let save = element("edit.save", timeout: 3) { safeTap(save) }
            assertAlive("salvar", config)
            // Volta pra Lista e o lugar novo aparece (nome é o último texto digitado no campo nome).
            XCTAssertTrue(button(startingWith: ["Adicionar à mão"], timeout: 6) != nil || app.state == .runningForeground,
                          "[\(config)] não voltou pra Lista")
        }
    }

    /// Colar: legenda de 5.000 caracteres nas notas e no nome; depois girar, fundo e voltar.
    func testPasteLongTextRotateBackground() {
        for config in matrix(default: [Config(area: .bh, net: .normal), Config(area: .jp, net: .flaky)]) {
            guard openNewPlaceFromList(config) else { continue }
            if let name = element("edit.name") { paste(String(Self.longText.prefix(400)), into: name) }
            assertAlive("colar no nome", config)
            if let notes = element("edit.notes") ?? scrollTo({ element("edit.notes", timeout: 0.5) }) {
                paste(Self.longText, into: notes)
                assertAlive("colar 5.000 nas notas", config)
                notes.enter(" e mais 🍡")
            }
            rotate()
            assertAlive("girar", config)
            backgroundAndBack()
            assertAlive("fundo e volta", config)
            if let name = element("edit.name") { hammer(name, config, rounds: 1) }
            assertAlive("digitar depois de voltar", config)
        }
    }

    /// Fecha a sheet com texto pela metade, abre de novo, digita; três vezes seguidas.
    func testCloseHalfTypedAndReopen() {
        for config in matrix(default: [Config(area: .bh, net: .normal), Config(area: .it, net: .slow)]) {
            guard openNewPlaceFromList(config) else { continue }
            for round in 0..<3 {
                if let name = element("edit.name") { safeTap(name); name.enter("Meio digitado \(round) 🍜") }
                swipeSheetDown()
                assertAlive("fechar pela metade \(round)", config)
                guard let add = scrollTo({ button(startingWith: ["Adicionar à mão", "Nada aqui ainda"], timeout: 1) }) else { break }
                safeTap(add)
                assertAlive("reabrir \(round)", config)
            }
        }
    }

    /// O suspeito: digitando no Novo lugar, o GPS pula pra outra região (automático) e o app troca o container.
    /// Também com o sync rodando a cada 3 s (grava no board durante a digitação).
    func testRegionSwitchByGPSWhileTyping() {
        for config in matrix(default: [Config(area: .bh, net: .normal), Config(area: .jp, net: .normal),
                                       Config(area: .it, net: .normal), Config(area: .bh, net: .dropping)]) {
            let other = config.area.other.gps
            let back = config.area.gps
            let hop = "7:\(other.lat),\(other.lng);16:\(back.lat),\(back.lng)"
            guard openNewPlaceFromList(config, extra: ["-debugGPSHop", hop, "-debugSyncEvery", "3"]) else { continue }
            let deadline = Date().addingTimeInterval(24)
            var rounds = 0
            while Date() < deadline, app.state == .runningForeground {
                // Depois da troca a árvore é outra: o Novo lugar some; abre de novo pelo caminho da Lista se der.
                if let name = element("edit.name", timeout: 1.5) {
                    name.enter("Troca \(rounds) ação 東京 ")
                    if let notes = element("edit.notes", timeout: 0.5) { notes.enter("nota \(rounds) 🍜 ") }
                } else if let add = button(startingWith: ["Adicionar à mão", "Nada aqui ainda"], timeout: 1) {
                    safeTap(add)
                } else {
                    app.swipeUp(velocity: .fast)
                }
                rounds += 1
            }
            assertAlive("troca de região pelo GPS com o Novo lugar aberto (\(rounds) rodadas)", config)
        }
    }

    /// Editar um lugar que já existe (`-debugScreen editar:<id>`), com a troca de região no meio.
    func testEditExistingPlace() {
        for config in matrix(default: [Config(area: .bh, net: .normal), Config(area: .jp, net: .normal), Config(area: .it, net: .offline)]) {
            launch(config, screen: "editar:\(config.area.samplePlace)",
                   extra: ["-debugGPSHop", "9:\(config.area.other.gps.lat),\(config.area.other.gps.lng)"])
            guard let name = element("edit.name") else { XCTFail("[\(config)] Editar não abriu"); continue }
            clear(name)
            hammer(name, config, rounds: 1)
            if let price = element("edit.price", timeout: 2) { safeTap(price); clear(price); price.enter("1.234,5") }
            if let area = element("edit.area", timeout: 2) { hammer(area, config, rounds: 1, texts: ["Shinjuku 新宿 ", "Savassi"]) }
            assertAlive("editar existente", config)
            // Espera o pulo do GPS (9 s) com a sheet aberta e digita de novo.
            let until = Date().addingTimeInterval(8)
            while Date() < until, app.state == .runningForeground {
                if let name = element("edit.name", timeout: 1) { name.enter("x") } else { break }
            }
            assertAlive("editar existente com troca de região", config)
            if let save = element("edit.save", timeout: 2) { safeTap(save) }
            assertAlive("salvar existente", config)
        }
    }

    /// Nova lista › "2 de 2 · adicionar lugares" (`AddItemsView`): busca no board a cada tecla, Places (fake), marcar,
    /// "manual" (o Novo lugar com o nome buscado) e salvar. Outra leitura de "tela de adicionar na lista".
    func testNewListAddItems() {
        for config in matrix() {
            launch(config, screen: "nova-lista")
            guard let name = element("newlist.name", timeout: 10) ?? scrollTo({ element("newlist.name", timeout: 0.5) }) else {
                XCTFail("[\(config)] Nova lista sem nome"); attachScreenshot("nova-lista-\(config)"); continue
            }
            hammer(name, config, rounds: 2, texts: ["kissa", "ten ☕️", " 喫茶店", " ação"])
            clear(name)
            name.enter("kissaten teste")
            dismissKeyboard()
            guard let create = scrollTo({ button(startingWith: ["Criar e adicionar lugares"], timeout: 1) }) else {
                XCTFail("[\(config)] sem Criar e adicionar"); continue
            }
            safeTap(create)
            let search = app.textFields["Buscar nome ou bairro…"]
            guard search.waitForExistence(timeout: 8) else { XCTFail("[\(config)] Adicionar lugares não abriu"); continue }
            hammer(search, config, rounds: 2)
            clear(search)
            search.enter("caf")
            assertAlive("busca no board", config)
            // Places (fake) com a busca digitada aos poucos (o .task(id:) cancela a anterior).
            if let places = button(startingWith: ["Places"], timeout: 2) {
                safeTap(places)
                safeTap(search)
                search.enter("é ramen 🍜")
                sleep(2)
                assertAlive("busca no Places", config)
            }
            if let board = button(startingWith: ["Do board"], timeout: 2) { safeTap(board) }
            dismissKeyboard()
            if let manual = app.buttons["manual"].exists ? app.buttons["manual"] : nil {
                safeTap(manual)
                if let field = element("edit.name") {
                    hammer(field, config, rounds: 1)
                    if let save = element("edit.save", timeout: 2) { safeTap(save) }
                }
            }
            assertAlive("Nova lista › manual", config)
        }
    }
}
