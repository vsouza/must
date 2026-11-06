import XCTest

/// Profiling (rodada 23 · G): abertura fria/quente, memória, relógio e hitches ao rolar as telas grandes.
/// Os números ficam no `.xcresult` (Xcode › Report navigator) e no `QA.md` › "Robustez e profiling (rodada 23)".
/// Simulador num Mac compartilhado: vale a ordem de grandeza e a comparação entre rodadas, não o número absoluto.
final class PerformanceTests: MustUITestCase {

    private func options(_ iterations: Int = 5) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    // MARK: Abertura

    /// Fria: o app sai do zero a cada iteração (`XCTApplicationLaunchMetric` mata o processo antes).
    func testLaunchCold() {
        let app = XCUIApplication()
        app.launchArguments = arguments(Config(area: .bh, net: .offline))
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options()) {
            app.launch()
        }
        app.terminate()
    }

    /// Quente: o processo volta do fundo (o que o Vinicius faz na rua o dia todo). Cache quente, offline.
    func testLaunchWarmResume() {
        launch(Config(area: .jp, net: .offline))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)], options: options()) {
            XCUIDevice.shared.press(.home)
            _ = app.wait(for: .runningBackground, timeout: 5)
            app.activate()
            _ = app.wait(for: .runningForeground, timeout: 5)
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 5)
        }
    }

    // MARK: Rolagem

    /// Rola uma tela pra cima e pra baixo medindo hitches, memória, CPU e relógio.
    private func measureScroll(_ config: Config, screen: String, before: (() -> Void)? = nil, swipes: Int = 4) {
        launch(config, screen: screen)
        sleep(3)
        before?()
        let metrics: [any XCTMetric] = [
            XCTHitchMetric(application: app), XCTMemoryMetric(application: app), XCTCPUMetric(application: app), XCTClockMetric(),
        ]
        let measured = options(3)
        measured.invocationOptions = [.manuallyStop]
        measure(metrics: metrics, options: measured) {
            for _ in 0..<swipes { app.swipeUp(velocity: .fast) }
            for _ in 0..<swipes { app.swipeDown(velocity: .fast) }
            stopMeasuring()
        }
        assertAlive("rolar \(screen)", config)
    }

    /// Lista longa: Eat do Japão (48 lugares, agrupados por bairro).
    func testScrollListEatJapan() { measureScroll(Config(area: .jp, net: .offline), screen: "lista:eat", swipes: 6) }

    /// Musts (hub com as listas e as capas).
    func testScrollMusts() { measureScroll(Config(area: .jp, net: .offline), screen: "musts") }

    /// Linha do dia (precisa de um dia aceito: monta antes com o motor, como o qa-screens.sh).
    func testScrollLinhaDoDia() {
        launch(Config(area: .jp, net: .offline), screen: "aceitar-dia:shinjuku",
               extra: ["-dev.simDate", Self.epoch("2026-11-15T08:30:00+09:00")])
        sleep(6)
        measureScroll(Config(area: .jp, net: .offline), screen: "dia")
    }

    /// Coleção (os feitos).
    func testScrollColecao() { measureScroll(Config(area: .jp, net: .offline), screen: "colecao") }

    /// Mapa (MapLibre): arrastar e pinçar em vez de rolar.
    func testPanMap() {
        let config = Config(area: .jp, net: .offline)
        launch(config, screen: "mapa-pino")
        sleep(4)
        let measured = options(3)
        measured.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTHitchMetric(application: app), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)],
                options: measured) {
            let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            for dx in [0.25, -0.25, 0.25, -0.25] {
                center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: dx * 300, dy: dx * 200)))
            }
            app.pinch(withScale: 2, velocity: 2)
            app.pinch(withScale: 0.5, velocity: -2)
            stopMeasuring()
        }
        assertAlive("mapa", config)
    }
}
