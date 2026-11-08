import SwiftData
import SwiftUI

// O "quero…" do corte fora da capa (prompt 30 · etapa 2): as peças que a capa, o Lugar e a Lista compartilham.
// A capa mostra as peças dentro da própria tela; o Lugar e a Lista abrem `CorteQueroOverlay` por cima (a mesma fenda,
// as mesmas faixas), só com outra origem (`QueroEnv.atPlace`) ou outro filtro (`QueroEnv.scoped`).

/// "Vontades de agora": os chips quadrados de borda 2 pt (sem raio) que mapeiam pros verbos do Quero….
struct CorteWishChips: View {
    var state: CorteState
    var makeEnv: () -> QueroEnv
    var label = "vontades de agora"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(label, size: 10, color: V8.mute)
            CorteFlow(spacing: 8) {
                ForEach(CorteWish.all) { wish in
                    Button { state.choose(wish, env: makeEnv()) } label: {
                        Text(wish.label.uppercased())
                            .font(V8Font.mono(11, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(state.quero.text == wish.text ? V8.paper : V8.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(state.quero.text == wish.text ? V8.ink : Color.clear)
                            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Régua dura de 2 pt entre as linhas do índice (papel).
struct CorteRule2: View {
    var body: some View { Rectangle().fill(V8.ink).frame(height: 2).accessibilityHidden(true) }
}

/// O que o resultado pede pra fora (rota, Lugar, board, dia).
struct CorteResultActions {
    var openPlace: (String) -> Void
    var route: (CorteRow) -> Void
    var addToBoard: (CorteRow) -> Void
    var fitToday: (CorteRow) -> Void
}

/// O resultado em duas faixas: laranja = seus Musts da cidade, mesmo longe; tinta = o que tem perto, fora do board.
struct CorteResultBands: View {
    var state: CorteState
    /// De onde a busca saiu ("Shinjuku", o nome do Lugar): "procurando perto de …".
    var placeName: String
    var actions: CorteResultActions
    /// Pro "ampliar pra 5 km" e "outro bairro" do vazio.
    var makeEnv: () -> QueroEnv

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "presente" (prompt 31): primeira faixa laranja, os presentes pendentes com a loja mais perto, a qualquer distância.
            if !state.quero.giftRows.isEmpty, state.quero.phase != .searching {
                GiftWantBand(rows: state.quero.giftRows,
                             onGo: { MapsLinks.openApple(to: $0.coordinate, name: $0.storeName) },
                             onOpen: { row in
                                 if let id = row.storeId { actions.openPlace(id) } else { MapsLinks.openApple(to: row.coordinate, name: row.storeName) }
                             })
            }
            if !(state.quero.intent == nil && !state.quero.giftRows.isEmpty) { mainBands }
        }
    }

    @ViewBuilder private var mainBands: some View {
        let query = state.quero.intent?.object ?? state.quero.text
        let origin = state.originName(fallback: placeName)
        if state.quero.phase == .searching {
            Text("procurando perto de \(origin)…")
                .font(V8Font.text(14)).foregroundStyle(V8.mute)
                .padding(20)
        } else if state.quero.phase == .idle {
            Text("Não entendi. Diga o que você quer: café, ramen, um mirante, jazz.")
                .font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if state.split.board.isEmpty && state.split.outside.isEmpty {
            emptyBlock(query: query, origin: origin)
        } else {
            HStack {
                MonoLabel("seus musts · \(state.split.board.count)", size: 10, color: V8.ink)
                Spacer(minLength: 8)
                MonoLabel("mesmo longe", size: 10, color: V8.ink)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(V8.orange)
            if state.split.board.isEmpty {
                Text("nenhum \(query) seu nesta cidade")
                    .font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(state.split.board) { line in
                CorteResultRow(line: line, dark: false, added: false,
                               onTap: { if let id = line.row.result.boardPlaceId { actions.openPlace(id) } },
                               onAction: { line.action == .go ? actions.route(line) : (line.row.result.boardPlaceId.map(actions.openPlace) ?? ()) },
                               onFit: line.row.slot != nil ? { actions.fitToday(line) } : nil)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MonoLabel("aqui perto agora · \(state.quero.offline ? 0 : state.split.outside.count)", size: 10, color: V8.white)
                    Spacer(minLength: 8)
                    MonoLabel("fora do board", size: 10, color: V8.muteDark)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                if state.quero.offline {
                    Text("sem internet · só seus Musts")
                        .font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.white)
                        .padding(.horizontal, 20).padding(.bottom, 20)
                } else if state.split.outside.isEmpty {
                    Text(CorteEmpty.outsideLine(offline: false, note: state.quero.outsideNote) ?? "nada aberto perto, fora do seu board")
                        .font(V8Font.text(14)).foregroundStyle(V8.muteDark)
                        .padding(.horizontal, 20).padding(.bottom, 20)
                }
                ForEach(state.quero.offline ? [] : state.split.outside) { line in
                    CorteResultRow(line: line, dark: true, added: state.added.contains(line.id),
                                   onTap: { actions.route(line) }, onAction: { actions.addToBoard(line) },
                                   onFit: line.row.slot != nil ? { actions.fitToday(line) } : nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.ink)
        }
    }

    /// As duas faixas vazias: o porquê, "ampliar pra 5 km" e os bairros perto (chips quadrados de borda 2 pt).
    private func emptyBlock(query: String, origin: String) -> some View {
        let env = state.lastEnv.map { state.adjusted($0) }
        let total = CorteEmpty.total(query: query, areaName: origin, offline: state.quero.offline, note: state.quero.outsideNote,
                                     radiusMeters: env?.radiusMeters)
        return VStack(alignment: .leading, spacing: 14) {
            Text(total.headline)
                .font(V8Font.display(30)).tracking(-0.8).foregroundStyle(V8.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(total.reason)
                .font(V8Font.text(15)).foregroundStyle(V8.ink)
                .fixedSize(horizontal: false, vertical: true)
            if total.canWiden {
                Button { state.widen(makeEnv()) } label: {
                    Text("AMPLIAR PRA 5 KM").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                        .padding(.horizontal, 14).padding(.vertical, 12).background(V8.orange)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            let others = state.otherAreas()
            if !others.isEmpty && !state.quero.offline {
                MonoLabel("outro bairro", size: 10, color: V8.mute)
                CorteFlow(spacing: 8) {
                    ForEach(others) { area in
                        Button { state.pickArea(area, env: makeEnv()) } label: {
                            Text(area.name.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Salvar e encaixar (a capa, o Lugar e a Lista gravam do mesmo jeito)

@MainActor
enum CorteSave {
    /// "+ board": guarda o lugar de fora na lista certa (a mesma lógica do Quero…).
    static func addToBoard(_ row: CorteRow, state: CorteState, env: QueroEnv, lists: [MustList], services: Services, context: ModelContext) {
        guard let place = QueroSave.place(for: row.row, intent: state.quero.intent, text: state.quero.text, lists: lists, cityId: env.cityId,
                                          region: env.region, sync: services.sync, context: context) else { return }
        state.markAdded(row.id, note: "Guardado em \(place.list?.name.capitalized ?? "Musts")")
    }

    /// Toque longo: "Encaixar hoje" (prompt 25). `true` quando encaixou (a tela fecha o quero e abre a Linha do dia).
    static func fitToday(_ row: CorteRow, state: CorteState, env: QueroEnv, lists: [MustList], services: Services, context: ModelContext) -> Bool {
        guard row.row.slot != nil,
              let place = QueroSave.place(for: row.row, intent: state.quero.intent, text: state.quero.text, lists: lists, cityId: env.cityId,
                                          region: env.region, sync: services.sync, context: context),
              (try? QueroSave.encaixar(row.row, place: place, env: env, context: context)) != nil else { return false }
        return true
    }
}

// MARK: - A fenda aberta por cima de outra tela (Lugar e Lista)

/// O "quero…" aberto por cima de uma tela: bloco da foto encolhido com a frase "<assunto>, quero", fenda laranja, régua
/// ("↑ fechar") e o papel com as vontades de agora ou o resultado em duas faixas. Cobre a tela inteira (e a barra de abas
/// já saiu: `AppRouter.queroOpen`). Quem abre decide a origem e o filtro pelo `makeEnv`.
struct CorteQueroOverlay: View {
    var state: CorteState
    /// Foto que o app já tem (nunca baixa).
    var photo: URL?
    /// "Blue Bottle", "Must eat": a frase vira "<assunto>, quero".
    var subject: String
    /// De onde a busca sai, pra "procurando perto de …".
    var originName: String
    var makeEnv: () -> QueroEnv
    var actions: CorteResultActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CutBand(photo: photo) {
                switch state.stage {
                case .result: resultBand
                default: askingBand
                }
            }
            .frame(height: state.stage == .result ? CorteLayout.resultBand : CorteLayout.askingBand)
            if state.stage == .asking {
                CorteSlit(model: state.quero, focused: $focused, speech: state.speech, onSubmit: { state.submit(makeEnv()) })
                    .frame(height: CorteLayout.askingSlit, alignment: .bottom)
                    .clipped()
            }
            CutRule(pullLabel: "↑ fechar")
                .cutPull(state.pull, reduceMotion: reduceMotion, onOpen: {}, onClose: { state.close() })
                .accessibilityAction(named: "Fechar quero") { state.close() }
            paper.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(V8.paper.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.82), value: state.stage)
        .onAppear { focused = state.stage == .asking }
        .onChange(of: state.stage) { _, stage in focused = stage == .asking }
        .onChange(of: state.quero.phase) { _, _ in state.resultArrived() }
        .task {
            state.speech.onFinal = { text in
                state.quero.text = text
                state.submit(makeEnv())
            }
        }
    }

    private var phrase: some View {
        Text("\(subject),\nquero")
            .font(V8Font.display(38))
            .tracking(-1.2)
            .lineSpacing(-8)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(subject), quero")
    }

    private var askingBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            phrase
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
    }

    private var resultBand: some View {
        let count = state.split.board.count + state.split.outside.count
        return Button { state.askAgain() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    MonoLabel("quero · \(originName)", size: 10, color: V8.white)
                    Spacer(minLength: 8)
                    if state.quero.phase == .done { MonoLabel(count == 1 ? "1 achado" : "\(count) achados", size: 10, color: V8.white) }
                }
                Spacer(minLength: 4)
                Text(state.quero.intent?.display ?? state.quero.text)
                    .font(V8Font.display(52))
                    .tracking(-1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("toque pra pedir outra coisa")
    }

    @ViewBuilder private var paper: some View {
        switch state.stage {
        case .result:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CorteResultBands(state: state, placeName: originName, actions: actions, makeEnv: makeEnv)
                    Color.clear.frame(height: 60)
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) { BottomFade(color: V8.paper, height: 60) }
        default:
            VStack(alignment: .leading, spacing: 10) {
                CorteWishChips(state: state, makeEnv: makeEnv)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }
}

// MARK: - Origem e filtro do quero (puro)

extension QueroEnv {
    /// O quero aberto no Lugar: de onde se sai, o "perto" e as distâncias passam a ser as do **lugar**, não as do GPS. O board
    /// é o da cidade do lugar (a qualquer distância) sem o próprio lugar.
    @MainActor
    func atPlace(_ place: Place, places: [Place]) -> QueroEnv {
        var e = self
        let point = place.coordinate
        e.origin = point
        e.center = point
        e.areaName = place.area ?? place.name
        e.cityId = place.cityId
        e.cityGroup = AreaCatalog.cityGroup(forCityId: place.cityId)
        e.board = QueroEnv.board(places, cityGroup: e.cityGroup, now: now, timeZone: region.timeZone).filter { $0.id != place.id }
        e.boardAnyDistance = true
        return e
    }

    /// O quero aberto numa Lista: o board que entra é só o da lista ("seus musts" = os desta lista).
    func scoped(toList listId: String) -> QueroEnv {
        var e = self
        e.board = board.filter { $0.listId == listId }
        return e
    }
}

/// O pedido que a Lista faz sozinha: o texto e o verbo da lista (Must eat → "comer", Must drink → "beber"…).
enum CorteListWish {
    static func wish(listId: String, name: String) -> CorteWish {
        switch listId {
        case "eat": CorteWish(label: name, text: "comer", verb: .comer)
        case "drink": CorteWish(label: name, text: "beber", verb: .beber)
        case "shop": CorteWish(label: name, text: "lojas", verb: .comprar)
        case "see", "photo", "art": CorteWish(label: name, text: "ver", verb: .ver)
        case "do", "sport": CorteWish(label: name, text: "fazer", verb: .fazer)
        default: CorteWish(label: name, text: name.lowercased(), verb: nil)
        }
    }
}
