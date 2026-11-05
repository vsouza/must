import Observation
import SwiftUI

/// Destinos empilháveis dentro de qualquer aba.
enum Route: Hashable {
    case list(id: String, sub: String? = nil)
    case saveForEnd
    case place(id: String)
    case settings
    case offlineMaps
    /// Montar o dia (meia-noite do dia, no fuso da região). `focusArea`: "Ajustar" da sheet de Bairros (prompt 18 · C.15).
    case montar(date: Date, focusArea: String? = nil)
    case trip
    case reservations
    /// Um dia aceito que não é hoje.
    case day(date: Date)
    /// Luz de hoje (dia de fotografia), meia-noite do dia.
    case light(date: Date)
    /// Board completo (Musts › Ver tudo · editar). `edit` abre já em modo edição (prints de QA).
    case board(edit: Bool = false)
    /// Ingresso de um lugar (Reservas, Lugar › Ingresso).
    case ticket(placeId: String, ticketId: String)
    /// Experiências (Must do): colar link e as salvas (prompt 14 · C).
    case experiences
    /// Por perto, agora (prompt 14 · B). Só da Home e daqui: nunca push.
    case discover
    /// Carteira da viagem: cartões, passes, eSIM, QR de entrada e documentos (prompt 15 · B).
    case carteira
    /// Agenda da viagem (Viagem › calendário): abas Voos e Reservas (prompt 15 · C).
    case schedule(tab: ScheduleTab)
    /// Ajustes › Dados › Uso do Google (contador por SKU e teto diário).
    case googleUsage
    /// Como chegar (prompt 17 · A): a rota de transporte até o lugar (ou ao ponto de encontro do ingresso).
    case comoChegar(placeId: String, meeting: Bool = false)
    /// Compras da viagem (prompt 17 · B): a lista, com previsto, cota e categorias.
    case compras
    /// Regras da volta (prompt 17 · B): tax-free, Na mala, Entrando no Brasil, Comida/Vigiagro.
    case regrasVolta
    /// Bairros (prompt 18 · C.14): mapa de bolhas e a sheet do bairro. `areaId` abre já com o bairro escolhido (prints).
    case bairros(areaId: String? = nil)
    /// Guia do dia (prompt 18 · C.16): a visão por bairro do dia aceito, meia-noite do dia.
    case guia(date: Date)

    // MARK: v8 (prompt 23 §2) — contrato da rodada 22, telas-stub até os agentes C e D entregarem.
    /// 02 · Bom dia (07–09h). Agente C.
    case bomDia
    /// 03 · Agora (no caminho). Agente C.
    case agora
    /// 04 · Linha do dia (meia-noite do dia). Agente C.
    case linha(date: Date)
    /// 13 · Ir (no caminho) até um lugar do board. Agente C.
    case ir(placeId: String)
    /// 14 · Boa noite (22h+). Agente C.
    case boaNoite
    /// 07 · Dicas pra hoje. Agente D.
    case dicas
    /// 08 · Bolso (utilidades offline). Agente D.
    case bolso
    /// 12 · Próximos (Viagem). Agente D.
    case proximos
    /// Mapa do dia (toggle Linha/Mapa e Guia); era a aba Mapa no v5.
    case mapa

    // MARK: prompt 25 — contrato (telas-stub até os agentes 25/1 e 25/2 entregarem)
    /// SOS do país da região (agente 25/2). Também em Bolso, Atalhos e na Quick Action.
    case sos
    /// Dia que alguém mandou (`must://d/<payload>`, agente 25/2): só leitura, o dia vem dentro do link.
    case diaRecebido(payload: String)
}

/// Navegação do app: aba atual, pilha de cada aba e o que está apresentado por cima.
@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Hashable {
        case addLink(url: String?, listId: String?)
        case editPlace(id: String)
        case newPlace(listId: String?)
        case expense(placeId: String?)
        case assistant
        /// Trazer ingresso (prompt 15 · A). `inboxId`: item da caixa do Share Extension, se veio por `must://import`.
        case ticketImport(inboxId: String?)
        /// Buscar por nome (prompt 17 · A): sheet, cobre a tab bar. `query` pré-preenche o campo.
        case buscarNome(query: String, listId: String?)
        /// Quero… (prompt 25 · A, agente 25/1): vontade → lugar físico → parada. O `+` da barra abre aqui.
        case quero(text: String?)
        /// Mandar o dia (prompt 25 · B, agente 25/2): cartaz, link, PDF. `date` nil = a viagem inteira.
        case mandar(date: Date?)

        var id: String {
            switch self {
            case .addLink(let url, let list): "add-\(url ?? "")-\(list ?? "")"
            case .editPlace(let id): "edit-\(id)"
            case .newPlace(let list): "new-\(list ?? "")"
            case .expense(let id): "expense-\(id ?? "")"
            case .assistant: "assistant"
            case .ticketImport(let id): "import-\(id ?? "")"
            case .buscarNome(let query, let list): "buscar-\(query)-\(list ?? "")"
            case .quero(let text): "quero-\(text ?? "")"
            case .mandar(let date): "mandar-\(date?.timeIntervalSince1970 ?? 0)"
            }
        }
    }

    enum Cover: Identifiable, Hashable {
        case newList
        case gallery
        /// Editar lista (nome, cor, ícone, sub-listas, ordem, apagar).
        case editList(id: String)

        var id: Self { self }
    }

    var tab: MustTab = .hoje
    var paths: [MustTab: [Route]] = [:]
    var sheet: Sheet?
    var cover: Cover?
    /// Modo pedido pro Mapa ao chegar do card "Perto de você" (prompt 06).
    var mapShowsOpenNow = false

    /// Telas v8 sem barra de abas (design): Montar (e a proposta), Ir/Como chegar e o Lugar em tela cheia.
    var hidesNavBar: Bool {
        switch paths[tab]?.last {
        case .montar, .ir, .comoChegar, .place, .sos: true
        default: false
        }
    }

    func path(for tab: MustTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route, on tab: MustTab? = nil) {
        let target = tab ?? self.tab
        self.tab = target
        paths[target, default: []].append(route)
    }

    func select(_ tab: MustTab) {
        if self.tab == tab {
            paths[tab] = [] // tocar na aba atual volta pra raiz
        }
        self.tab = tab
    }

    /// `must://add?url=…`, `must://hoje`, `must://montar?date=2026-11-16`, `must://lugar/<id>`, `must://mapa`
    func handle(url: URL, region: Region) {
        guard url.scheme == "must" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host() {
        case "add":
            sheet = .addLink(url: items.first { $0.name == "url" }?.value, listId: nil)
        case "hoje":
            sheet = nil
            select(.hoje)
            paths[.hoje] = []
        case "mapa":
            sheet = nil
            paths[.hoje] = []
            push(.mapa, on: .hoje)
        case "montar":
            sheet = nil
            let dates = BoardDates(timeZone: region.timeZone)
            let day = items.first { $0.name == "date" }?.value.flatMap(dates.day(from:))
                ?? region.calendar.startOfDay(for: AppClock.now)
            paths[.hoje] = []
            push(.montar(date: day), on: .hoje)
        case "lugar":
            sheet = nil
            let id = url.pathComponents.dropFirst().first
            if let id { push(.place(id: id), on: .musts) }
        // Avisos do guia v8 (prompt 23 §4): o toque abre o momento do dia.
        case "bom-dia":
            sheet = nil
            paths[.hoje] = []
            select(.hoje)
            push(.bomDia, on: .hoje)
        case "agora":
            sheet = nil
            paths[.hoje] = []
            select(.hoje)
            push(.agora, on: .hoje)
        case "noite":
            sheet = nil
            paths[.hoje] = []
            select(.hoje)
            push(.boaNoite, on: .hoje)
        case "import":
            // Caixa do Share Extension: o id é o nome da pasta (UUID); a tela confere se ainda existe.
            sheet = .ticketImport(inboxId: items.first { $0.name == "id" }?.value)
        // Link do dia (prompt 25 · B.2): `must://d/<payload>`, o dia comprimido dentro do link (sem servidor).
        case "d":
            guard let payload = DayLink.payload(from: url) else { return }
            sheet = nil
            paths[.hoje] = []
            tab = .hoje
            push(.diaRecebido(payload: payload), on: .hoje)
        // SOS (prompt 25 · C.3): Live Activity à noite e a Quick Action levam aqui.
        case "sos":
            sheet = nil
            paths[.hoje] = []
            tab = .hoje
            push(.sos, on: .hoje)
        default:
            Log.app.info("link desconhecido: \(url.absoluteString, privacy: .public)")
        }
    }
}

extension View {
    /// Destinos comuns das pilhas de navegação.
    func mustDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .list(let id, let sub): ListView(listId: id, initialSub: sub)
            case .saveForEnd: ListView(listId: nil, initialSub: nil, saveForEndOnly: true)
            case .place(let id): PlaceView(placeId: id)
            case .settings: SettingsView()
            case .offlineMaps: OfflineMapsView()
            case .montar(let date, let focusArea): MontarView(date: date, focusArea: focusArea)
            case .trip: TripView()
            case .reservations: ReservationsView()
            case .day(let date): TodayView(date: date)
            case .light(let date): LightDayView(date: date)
            case .board(let edit): BoardView(startEditing: edit)
            case .ticket(let placeId, let ticketId): TicketView(placeId: placeId, ticketId: ticketId)
            case .experiences: ExperiencesView()
            case .discover: DiscoverView()
            case .carteira: WalletView()
            case .schedule(let tab): ScheduleView(tab: tab)
            case .googleUsage: GoogleUsageView()
            case .comoChegar(let placeId, let meeting): ComoChegarView(placeId: placeId, meeting: meeting)
            case .compras: ShoppingView()
            case .regrasVolta: ShoppingRulesView()
            case .bairros(let areaId): BairrosView(initialArea: areaId)
            case .guia(let date): GuiaBairroView(date: date)
            case .bomDia: BomDiaView()
            case .agora: AgoraView()
            case .linha(let date): LinhaDoDiaView(date: date)
            case .ir(let placeId): IrView(placeId: placeId)
            case .boaNoite: BoaNoiteView()
            case .dicas: DicasView()
            case .bolso: BolsoView()
            case .proximos: ProximosView()
            case .mapa: MapView()
            case .sos: SOSView()
            case .diaRecebido(let payload): DiaRecebidoView(payload: payload)
            }
        }
    }
}
