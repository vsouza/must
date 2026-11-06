import XCTest

/// Base dos UI tests (rodada 23 · G). Abre o app como o `scripts/qa-screens.sh` faz — região, data e GPS simulados,
/// todos os fakes ligados (nenhuma chamada paga, nada de cota) e um board novo do seed numa pasta temporária
/// (`-debugFreshStore`), sem tocar no board do simulador.
///
/// Matriz: `MUST_UI_MATRIX="bh:wifi,jp:slow,it:offline"` (no `xcodebuild`, `TEST_RUNNER_MUST_UI_MATRIX=…`).
/// Sem ela, cada cenário roda em BH, JP e IT com a rede normal e em BH com `slow` e `offline`.
@MainActor
class MustUITestCase: XCTestCase {
    enum Area: String, CaseIterable {
        case bh, jp, it

        /// Data (fixa: `-dev.simSetAt 0`) e GPS de cada região, os mesmos do `qa-screens.sh`.
        var date: String {
            switch self {
            case .bh: "2026-11-07T14:35:00-03:00"
            case .jp: "2026-11-15T14:20:00+09:00"
            case .it: "2027-04-15T11:40:00+02:00"
            }
        }

        var gps: (lat: Double, lng: Double) {
            switch self {
            case .bh: (-19.9385, -43.9343) // Savassi
            case .jp: (35.6909, 139.7003) // Shinjuku
            case .it: (41.8897, 12.4695) // Trastevere
            }
        }

        /// Um lugar do seed de cada região (Lugar, Editar).
        var samplePlace: String {
            switch self {
            case .bh: "p01"
            case .jp: "j05"
            case .it: "r02"
            }
        }

        /// Outra região, pro pulo do GPS (troca automática de região com a tela aberta).
        var other: Area { self == .jp ? .bh : .jp }
    }

    /// `normal` não passa `-debugNetwork` (rede do Mac).
    enum Net: String, CaseIterable {
        case normal, wifi, slow, flaky, dropping, offline
    }

    struct Config: CustomStringConvertible {
        var area: Area
        var net: Net
        var description: String { "\(area.rawValue)·\(net.rawValue)" }
    }

    private(set) var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        if let app, app.state != .notRunning { app.terminate() }
    }

    /// Matriz pedida (env) ou o padrão do cenário.
    func matrix(default fallback: [Config]? = nil) -> [Config] {
        if let raw = ProcessInfo.processInfo.environment["MUST_UI_MATRIX"], !raw.isEmpty {
            return raw.split(separator: ",").compactMap { item in
                let parts = item.split(separator: ":").map(String.init)
                guard let area = Area(rawValue: parts.first ?? "") else { return nil }
                return Config(area: area, net: Net(rawValue: parts.count > 1 ? parts[1] : "normal") ?? .normal)
            }
        }
        return fallback ?? [
            Config(area: .bh, net: .normal), Config(area: .jp, net: .normal), Config(area: .it, net: .normal),
            Config(area: .bh, net: .slow), Config(area: .bh, net: .offline),
        ]
    }

    static func epoch(_ iso: String) -> String {
        let date = ISO8601DateFormatter().date(from: iso) ?? Date()
        return String(Int(date.timeIntervalSince1970))
    }

    /// Argumentos de lançamento do cenário. `screen` vira `-debugScreen`; `extra` vai no fim.
    func arguments(_ config: Config, screen: String? = nil, extra: [String] = []) -> [String] {
        var args = [
            "-region", config.area.rawValue, "-region.auto", "YES",
            "-skipOnboarding", "YES", "-debugFreshStore", "YES",
            "-dev.simDateOn", "YES", "-dev.simDate", Self.epoch(config.area.date), "-dev.simSetAt", "0",
            "-dev.simGPSOn", "YES", "-dev.simLat", "\(config.area.gps.lat)", "-dev.simLng", "\(config.area.gps.lng)",
            // Fakes: nenhuma chamada paga (Places, Nearby, AeroDataBox, dicas, Routes, Autocomplete, Em cartaz).
            "-debugPlaces", "fake", "-debugNearby", "fake", "-debugFlight", "fake", "-debugTips", "fake",
            "-debugRoutes", "fake", "-debugAutocomplete", "fake", "-debugEvents", "fake", "-debugPhotos", "fake",
            // Teclado de software (o `typeText` digita nele) e sem o "Mostrar teclas" do primeiro uso.
            "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
        ]
        if config.net != .normal { args += ["-debugNetwork", config.net.rawValue] }
        if config.net == .dropping { args += ["-debugNetworkPeriod", "4"] }
        if let screen { args += ["-debugScreen", screen] }
        return args + extra
    }

    @discardableResult
    func launch(_ config: Config, screen: String? = nil, extra: [String] = []) -> XCUIApplication {
        if let app, app.state != .notRunning { app.terminate() }
        let app = XCUIApplication()
        app.launchArguments = arguments(config, screen: screen, extra: extra)
        app.launch()
        self.app = app
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "[\(config)] app não abriu")
        return app
    }

    // MARK: Vivo?

    /// Falha (sem parar) se o app caiu. Devolve se ainda está de pé.
    @discardableResult
    func assertAlive(_ what: String, _ config: Config, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let alive = app.state == .runningForeground
        if !alive {
            XCTFail("[\(config)] CRASH/saiu em: \(what) (estado \(app.state.rawValue))", file: file, line: line)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "crash-\(config)-\(what)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        return alive
    }

    func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Achar coisas

    func element(_ id: String, timeout: TimeInterval = 8) -> XCUIElement? {
        let el = app.descendants(matching: .any).matching(identifier: id).firstMatch
        return el.waitForExistence(timeout: timeout) ? el : nil
    }

    /// Botão cujo rótulo começa com algum dos textos (botões com várias linhas de texto juntam tudo no rótulo).
    func button(startingWith prefixes: [String], timeout: TimeInterval = 6) -> XCUIElement? {
        let format = prefixes.map { _ in "label BEGINSWITH[c] %@" }.joined(separator: " OR ")
        let el = app.buttons.matching(NSPredicate(format: format, argumentArray: prefixes)).firstMatch
        return el.waitForExistence(timeout: timeout) ? el : nil
    }

    /// Rola até o elemento aparecer (listas preguiçosas só criam a linha perto da tela).
    func scrollTo(_ find: () -> XCUIElement?, maxSwipes: Int = 14) -> XCUIElement? {
        for _ in 0..<maxSwipes {
            if let el = find(), el.isHittable { return el }
            app.swipeUp(velocity: .fast)
        }
        return find()
    }

    // MARK: Digitação dirigida (monkey)

    /// Amostras: acentos, emoji, japonês, italiano, pontuação e quebra de linha.
    static let samples = [
        "Café com pão de queijo · ação, coração, açúcar ",
        "🍜🍣🍶 ramen 😋👍🏽 ",
        "東京 渋谷 ラーメン 一蘭 ",
        "Trattoria da Enzo al 29 — cacio e pepe, supplì ",
        "!@#$%^&*()_+-=[]{};':\",./<>?\\| ",
        "naïve résumé Ñandú São Paulo ",
    ]

    /// Texto longo (legenda colada): ~5.000 caracteres com tudo misturado.
    static let longText: String = {
        var out = ""
        var i = 0
        while out.count < 5_000 {
            out += samples[i % samples.count]
            if i % 4 == 3 { out += "\n📍 Lugar \(i) · Shinjuku\n" }
            i += 1
        }
        return String(out.prefix(5_000))
    }()

    /// Digita em rajadas no campo (sem esperar a UI entre elas), apaga tudo e digita de novo.
    func hammer(_ field: XCUIElement, _ config: Config, rounds: Int = 2, texts: [String] = MustUITestCase.samples) {
        guard field.waitForExistence(timeout: 5) else { XCTFail("[\(config)] campo sumiu"); return }
        for round in 0..<rounds {
            for text in texts {
                type(text, into: field)
                guard app.state == .runningForeground else { return }
            }
            if round < rounds - 1 { clear(field) }
        }
    }

    /// O campo está com o teclado (o "\n" de buscar, a troca de aba e o fundo tiram o foco).
    func hasFocus(_ field: XCUIElement) -> Bool {
        field.exists && (field.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
    }

    /// Digita no campo, tocando antes se ele perdeu o foco. Campo que sumiu (a tela trocou) não é falha do app.
    func type(_ text: String, into field: XCUIElement) {
        guard field.exists else { return }
        if !hasFocus(field) {
            guard field.isHittable else { return }
            field.tap()
        }
        guard hasFocus(field) else { return }
        field.typeText(text)
    }

    /// Toque que não falha se o elemento sumiu entre o achar e o tocar (troca de região, sheet fechando).
    func safeTap(_ element: XCUIElement) {
        guard element.exists, element.isHittable else { return }
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    /// Apaga o que tem no campo (backspace repetido; o `value` diz quanto tem).
    func clear(_ field: XCUIElement) {
        guard field.exists else { return }
        let current = (field.value as? String) ?? ""
        let count = max(current.count, 10) + 5
        type(String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(count, 400)), into: field)
    }

    /// Cola um texto no campo pelo menu de edição (Colar/Paste). Sem o menu, digita uma parte.
    func paste(_ text: String, into field: XCUIElement, fallbackPrefix: Int = 300) {
        UIPasteboard.general.string = text
        guard field.exists, field.isHittable else { return }
        field.tap()
        guard field.exists else { return }
        field.press(forDuration: 1.1)
        let menu = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Colar", "Paste"])).firstMatch
        if menu.waitForExistence(timeout: 2) {
            menu.tap()
            // Aviso "permitir colar" (só quando o app lê sozinho; pelo menu não deveria aparecer).
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons
                .matching(NSPredicate(format: "label IN %@", ["Permitir Colar", "Allow Paste"])).firstMatch
            if allow.waitForExistence(timeout: 1) { allow.tap() }
        } else {
            type(String(text.prefix(fallbackPrefix)), into: field)
        }
    }

    /// Campos de texto visíveis agora (TextField de uma linha e os de várias linhas, que viram textView).
    func visibleFields() -> [XCUIElement] {
        let fields = app.textFields.allElementsBoundByIndex + app.textViews.allElementsBoundByIndex
        return fields.filter { $0.exists && $0.isHittable }
    }

    /// Digita em cada campo visível (e nos que aparecem rolando). Os 23 dígitos vão primeiro: com texto antes, o campo
    /// numérico já virou nil e o resto não chega no `Int(_:)` (foi assim que o crash do `KindExtraFields` passou batido).
    func typeIntoAllFields(_ config: Config, swipes: Int = 3, texts: [String] = ["12345678901234567890123", " Ação 東京 🍜 ", "nan"]) {
        var done = Set<String>()
        for _ in 0...swipes {
            for field in visibleFields() {
                let key = "\(field.identifier)|\(field.placeholderValue ?? "")|\(field.label)"
                guard !done.contains(key) else { continue }
                done.insert(key)
                for text in texts {
                    type(text, into: field)
                    guard app.state == .runningForeground else { return }
                }
                clear(field)
                type(texts[0], into: field)
            }
            dismissKeyboard()
            app.swipeUp(velocity: .slow)
        }
    }

    /// Gira a tela e volta (o app é só retrato no iPhone: tem que ignorar sem quebrar).
    func rotate() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
    }

    /// Manda pro fundo e volta (o `scenePhase` dispara sync, GPS e guia no meio da digitação).
    func backgroundAndBack() {
        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackground, timeout: 3)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 8)
    }

    /// Fecha a sheet arrastando pra baixo (com texto pela metade).
    func swipeSheetDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Esconde o teclado (toque no "Return/OK" quando houver, senão arrasta a rolagem).
    func dismissKeyboard() {
        if app.keyboards.count == 0 { return }
        for key in ["OK", "Done", "Concluído", "return", "Return", "Retorno", "Buscar", "Search", "Ir", "Go"] {
            let button = app.keyboards.buttons[key]
            if button.exists && button.isHittable { button.tap(); return }
        }
        app.swipeDown(velocity: .slow)
    }
}

extension XCUIElement {
    /// `typeText` que toca antes se o campo perdeu o foco, e não faz nada se o campo sumiu (a tela trocou).
    func enter(_ text: String) {
        guard exists else { return }
        if !(value(forKey: "hasKeyboardFocus") as? Bool ?? false) {
            guard isHittable else { return }
            tap()
        }
        guard exists, value(forKey: "hasKeyboardFocus") as? Bool ?? false else { return }
        typeText(text)
    }
}
