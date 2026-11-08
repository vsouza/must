import CoreLocation
import Foundation
import Observation

/// Estado do corte na capa (prompt 30): o arrasto da régua, o passo da capa (repouso / pedindo / resultado), o `QueroModel`
/// por baixo (nenhuma API nova), o passo a passo e o contador de puxadas. Nada de rede aqui: a busca é a do Quero….
@MainActor
@Observable
final class CorteState {
    let pull = CutPull()
    private(set) var stage: CorteLayout.Stage = .rest
    private(set) var quero: QueroModel
    let speech = SpeechInput()
    /// Passo do passo a passo (`nil` = sem passo a passo).
    private(set) var walk: CorteWalk.Step?
    private(set) var coach: CutCoach
    /// Ids guardados no board nesta sessão ("+ board" vira "no board").
    private(set) var added: Set<String> = []
    private(set) var savedNote: String?
    /// As duas faixas do resultado (calculadas quando a busca termina, nunca no `body`).
    private(set) var split = CorteSplit.Result(board: [], outside: [])
    /// O ambiente da última busca (de onde se sai, pro "9 min · trem" e pro "perto").
    @ObservationIgnored private(set) var lastEnv: QueroEnv?
    /// Cutucão em andamento (pt que a régua desce além do dedo).
    var nudge: CGFloat = 0
    /// A pessoa já tocou na capa nesta aparição (o cutucão só vale parada).
    var touched = false
    @ObservationIgnored private var walkTripId: String?
    @ObservationIgnored private let prefs: CortePrefs
    @ObservationIgnored private let makeModel: @MainActor () -> QueroModel

    init(prefs: CortePrefs = CortePrefs(), makeModel: @escaping @MainActor () -> QueroModel = { CorteState.defaultModel() }) {
        self.prefs = prefs
        self.makeModel = makeModel
        coach = prefs.coach
        quero = makeModel()
    }

    static func defaultModel() -> QueroModel {
        let model = QueroModel(provider: QueroView.provider())
        model.defaultWhen = .hoje
        model.rowLimit = 40
        return model
    }

    // MARK: Abrir e fechar

    /// A régua travou aberta (ou o toque no bairro): a fenda aparece e o campo ganha foco.
    func open() {
        if !pull.isOpen { pull.lock() }
        stage = .asking
        if walk == .pull { advance(.pulledOpen) }
    }

    func close() {
        pull.close()
        stage = .rest
        speech.cancel()
        quero = makeModel()
        savedNote = nil
        added = []
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
        stage = .result
        lastEnv = env
        split = CorteSplit.Result(board: [], outside: [])
        quero.submit(Self.corteEnv(env))
    }

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

    /// A busca terminou com linhas: conta a puxada (3 e o texto encurta) e avança o passo a passo.
    func resultArrived() {
        guard quero.phase == .done, let env = lastEnv else { return }
        split = CorteSplit.split(quero.rows, origin: env.origin, region: env.region, walkMaxKm: env.walkMaxKm)
        guard !quero.rows.isEmpty else { return }
        coach.recordResult()
        prefs.coach = coach
        if walk == .write { advance(.gotResult) }
    }

    func markAdded(_ id: String, note: String) {
        added.insert(id)
        savedNote = note
    }

    // MARK: Passo a passo

    func startWalk(tripId: String, force: Bool = false) {
        guard force || CorteWalk.shouldPresent(tripId: tripId, seen: prefs.seenTrips) else { return }
        walkTripId = tripId
        walk = .pull
    }

    func skipWalk() {
        advance(.skip)
    }

    func finishWalk() { advance(.skip) }

    private func advance(_ event: CorteWalk.Event) {
        guard let step = walk else { return }
        walk = CorteWalk.next(step, event)
        if walk == nil, let id = walkTripId { prefs.markPresented(id) }
        // Passo 2: a fenda aberta já traz "café" pronto pra enviar.
        if walk == .write, quero.text.isEmpty { quero.text = "café" }
    }
}
