import Observation
import SwiftUI

/// Destinos empilháveis dentro de qualquer aba.
enum Route: Hashable {
    case list(id: String, sub: String? = nil)
    case saveForEnd
    case place(id: String)
    case settings
    case offlineMaps
    /// Montar o dia (meia-noite do dia, no fuso da região).
    case montar(date: Date)
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

        var id: String {
            switch self {
            case .addLink(let url, let list): "add-\(url ?? "")-\(list ?? "")"
            case .editPlace(let id): "edit-\(id)"
            case .newPlace(let list): "new-\(list ?? "")"
            case .expense(let id): "expense-\(id ?? "")"
            case .assistant: "assistant"
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

    var tab: MustTab = .inicio
    var paths: [MustTab: [Route]] = [:]
    var sheet: Sheet?
    var cover: Cover?
    /// Modo pedido pro Mapa ao chegar do card "Perto de você" (prompt 06).
    var mapShowsOpenNow = false

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
            select(.mapa)
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
            case .montar(let date): MontarView(date: date)
            case .trip: TripView()
            case .reservations: ReservationsView()
            case .day(let date): TodayView(date: date)
            case .light(let date): LightDayView(date: date)
            case .board(let edit): BoardView(startEditing: edit)
            case .ticket(let placeId, let ticketId): TicketView(placeId: placeId, ticketId: ticketId)
            }
        }
    }
}
