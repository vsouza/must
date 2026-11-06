import XCTest

/// Navegação inteira com internet ruim (rodada 23 · G): cada `-debugScreen` de `MustApp.swift` (que cobre as rotas do
/// `Router.swift`) e os links `must://`, com `-debugNetwork flaky` (latência 0,5–8 s, 40% de falha, resposta cortada,
/// JSON inválido, 429/500) e `dropping` (cai e volta a cada 4 s). Em cada tela: não cai, não fica vazia, não fica com
/// spinner pra sempre, rola e volta.
final class NavigationStressTests: MustUITestCase {

    /// Telas do `DebugLaunch` (o `%p` vira o lugar de exemplo da região). Uma entrada por rota do `Router`.
    static let screens = [
        "capa", "inicio", "inicio-aceito", "hoje-aceito", "aceitar", "aceitar-dia", "bom-dia", "agora", "dia", "noite",
        "montar", "proposta", "guia", "dicas", "dicas:%p", "bolso", "proximos", "musts", "lista:eat", "lista:art", "fim",
        "board", "board:editar", "editar-lista:eat", "nova-lista", "lugar:%p", "painel:%p", "3d:%p", "museu:%p",
        "lugar-amigos:%p", "lugar-emcartaz:%p", "filmes:%p", "editar:%p", "ir:%p", "como-chegar:%p", "como-chegar-encontro",
        "adicionar", "colar-texto", "buscar-nome:koffee mam", "quero:quero comer um ramen", "atalhos", "luz", "mapa",
        "mapa:aceitar", "mapa-pino", "bairros", "bairros:shinjuku", "ajustar", "viagem", "reservas", "voos", "viagem-voos",
        "viagem-reservas", "experiencias", "descobrir", "carteira", "ingresso", "ingresso-entrada", "ingresso-revisar",
        "compras", "compras-regras", "gasto", "assistente", "ajustes", "regiao", "mapas-offline", "uso-google",
        "sincronizar", "avisos", "compartilhar", "sos", "emcartaz", "colecao", "colecionavel-novo:%p", "trocar-viagem",
        "capa-inteligente",
    ]

    /// Links que o app abre (avisos, Live Activity, Share Extension, dia mandado), inclusive quebrados.
    static let links = [
        "must://hoje", "must://mapa", "must://montar?date=2026-11-08", "must://montar?date=lixo", "must://lugar/%p",
        "must://lugar/nao-existe", "must://bom-dia", "must://agora", "must://noite", "must://sos",
        "must://add?url=https%3A%2F%2Fwww.instagram.com%2Freel%2FABC", "must://import?id=nao-existe", "must://d/lixo",
        "must://d/", "must://desconhecido",
    ]

    private var defaultMatrix: [Config] {
        [Config(area: .bh, net: .flaky), Config(area: .jp, net: .dropping), Config(area: .it, net: .flaky)]
    }

    func testEveryScreenWithBadNetwork() {
        for config in matrix(default: defaultMatrix) {
            for raw in Self.screens {
                let screen = raw.replacingOccurrences(of: "%p", with: config.area.samplePlace)
                visit(screen: screen, config)
            }
        }
    }

    func testDeepLinksWithBadNetwork() {
        for config in matrix(default: [Config(area: .bh, net: .flaky), Config(area: .jp, net: .dropping)]) {
            launch(config)
            for raw in Self.links {
                guard let url = URL(string: raw.replacingOccurrences(of: "%p", with: config.area.samplePlace)) else { continue }
                app.open(url)
                sleep(2)
                guard assertAlive("link \(url.absoluteString)", config) else { launch(config); continue }
                app.swipeUp(velocity: .fast)
                app.swipeDown(velocity: .fast)
            }
        }
    }

    /// Abre a tela, espera a rede ruim agir, rola, confere o que dá pra conferir sem conhecer a tela.
    private func visit(screen: String, _ config: Config) {
        launch(config, screen: screen)
        sleep(3)
        guard assertAlive("abrir \(screen)", config) else { return }
        // Vazia: nenhuma palavra na tela depois de 3 s (o cache/placeholder tem que aparecer na hora).
        let texts = app.staticTexts.count + app.buttons.count
        XCTAssertGreaterThan(texts, 2, "[\(config)] \(screen) ficou vazia")
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .slow)
        app.swipeDown(velocity: .fast)
        guard assertAlive("rolar \(screen)", config) else { return }
        // Spinner infinito: até 20 s com rede ruim (8 s de latência × 2 tentativas + folga).
        let deadline = Date().addingTimeInterval(20)
        while app.activityIndicators.count > 0, Date() < deadline { sleep(1) }
        if app.activityIndicators.count > 0 {
            attachScreenshot("spinner-\(config)-\(screen)")
            XCTFail("[\(config)] \(screen): spinner há mais de 20 s")
        }
        assertAlive("esperar \(screen)", config)
    }
}
