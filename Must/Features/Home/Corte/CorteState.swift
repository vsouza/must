import CoreLocation
import Foundation
import Observation

/// Estado do corte na capa (prompt 30): o arrasto da régua, o passo da capa (repouso / pedindo / resultado), o `QueroModel`
/// por baixo (nenhuma API nova). Nada de rede aqui: a busca é a do Quero….
@MainActor
@Observable
final class CorteState {
    let pull = CutPull()
    private(set) var stage: CorteLayout.Stage = .rest
    private(set) var quero: QueroModel
    let speech = SpeechInput()
    /// Ids guardados no board nesta sessão ("+ board" vira "no board").
    private(set) var added: Set<String> = []
    private(set) var savedNote: String?
    /// As duas faixas do resultado (calculadas quando a busca termina, nunca no `body`).
    private(set) var split = CorteSplit.Result(board: [], outside: [])
    /// O ambiente da última busca (de onde se sai, pro "9 min · trem" e pro "perto").
    @ObservationIgnored private(set) var lastEnv: QueroEnv?
    /// "Ampliar pra 5 km" (vale até fechar o quero).
    private(set) var widened = false
    /// "Outro bairro": o bairro escolhido à mão no vazio (vale até fechar o quero).
    private(set) var areaOverride: Area?
    /// Responde perguntas digitadas no quero (a capa liga: tem o contexto e os serviços).
    @ObservationIgnored var answerer: (@MainActor (String) async -> String)? {
        didSet { quero.answerer = answerer }
    }
    @ObservationIgnored private let makeModel: @MainActor () -> QueroModel

    init(makeModel: @escaping @MainActor () -> QueroModel = { CorteState.defaultModel() }) {
        self.makeModel = makeModel
        quero = makeModel()
    }

    static func defaultModel() -> QueroModel {
        let model = QueroModel(provider: QueroView.provider(), extras: QueroView.extras())
        model.defaultWhen = .hoje
        model.rowLimit = 40
        return model
    }

    // MARK: Abrir e fechar

    /// A régua travou aberta (ou o toque no bairro): a fenda aparece e o campo ganha foco.
    func open() {
        if !pull.isOpen { pull.lock() }
        stage = .asking
    }

    func close() {
        pull.close()
        stage = .rest
        speech.cancel()
        quero = makeModel()
        quero.answerer = answerer
        savedNote = nil
        added = []
        widened = false
        areaOverride = nil
    }

    /// A Lista abre o quero já com o pedido da lista (texto + verbo); a pessoa só confirma ou muda.
    func preset(_ wish: CorteWish) {
        quero.text = wish.text
        quero.verbOverride = wish.verb
    }

    /// "Novo pedido": volta pra fenda com o texto anterior.
    func askAgain() { stage = .asking }

    // MARK: Pedir

    func submit(_ env: QueroEnv) {
        guard !quero.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Pergunta (v9): fica na fenda, com a faixa "✦ isso é uma pergunta" e os chips de lugar embaixo.
        stage = QueroQuestion.isQuestion(quero.text) ? .asking : .result
        lastEnv = env
        split = CorteSplit.Result(board: [], outside: [])
        quero.submit(Self.corteEnv(adjusted(env)))
    }

    /// O ambiente com o que a pessoa pediu no vazio: bairro escolhido e raio de 5 km.
    func adjusted(_ env: QueroEnv) -> QueroEnv {
        var e = env
        if let area = areaOverride {
            e.origin = area.centroid.clCoordinate
            e.center = e.origin
            e.areaName = area.name
            e.originBasis = .area
        }
        if widened { e.radiusMeters = CorteEmpty.widenedMeters }
        return e
    }

    /// "Ampliar pra 5 km": a mesma vontade, o raio maior.
    func widen(_ env: QueroEnv) {
        widened = true
        submit(env)
    }

    /// "Outro bairro": a mesma vontade, saindo do centro de outro bairro.
    func pickArea(_ area: Area, env: QueroEnv) {
        areaOverride = area
        submit(env)
    }

    /// Bairros perto de onde a busca saiu (pro "outro bairro").
    func otherAreas() -> [Area] {
        guard let env = lastEnv else { return [] }
        let e = adjusted(env)
        return CorteEmpty.nearbyAreas(AreaCatalog.areas(for: env.region), from: e.origin, cityGroup: env.cityGroup, excluding: e.areaName)
    }

    /// O nome do lugar de onde a busca saiu (o bairro escolhido ou o da capa).
    func originName(fallback: String) -> String { areaOverride?.name ?? fallback }

    func choose(_ wish: CorteWish, env: QueroEnv) {
        quero.text = wish.text
        quero.verbOverride = wish.verb
        submit(env)
    }

    static func corteEnv(_ env: QueroEnv) -> QueroEnv {
        var e = env
        e.boardAnyDistance = true
        return e
    }

    /// A busca terminou: separa as duas faixas.
    func resultArrived() {
        guard quero.phase == .done, let env = lastEnv else { return }
        let e = adjusted(env)
        split = CorteSplit.split(quero.rows, origin: e.origin, region: e.region, walkMaxKm: e.walkMaxKm,
                                 near: e.radiusMeters ?? CorteSplit.nearMeters)
    }

    func markAdded(_ id: String, note: String) {
        added.insert(id)
        savedNote = note
    }
}
