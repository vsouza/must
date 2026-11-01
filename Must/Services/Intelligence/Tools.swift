import CoreLocation
import Foundation
import FoundationModels

/// Guarda as ações que as ferramentas propõem durante uma resposta (o chat vira cartões).
actor ActionCollector {
    private(set) var actions: [AssistantAction] = []
    private(set) var notes: [String] = []

    func add(_ action: AssistantAction) { if !actions.contains(action) { actions.append(action) } }
    func note(_ text: String) { notes.append(text) }
    func drain() -> (actions: [AssistantAction], notes: [String]) {
        defer { actions = []; notes = [] }
        return (actions, notes)
    }
}

// Ferramentas determinísticas sobre o retrato local. Nenhuma acessa rede nem recebe chave.

struct SearchBoardTool: Tool {
    let name = "searchBoard"
    let description = "Busca lugares do board do usuário por nome, bairro, prato ou lista (ex.: \"sushi\", \"ramen barato\"). Use pra qualquer sugestão. Só retorna lugares que existem no board."
    let snapshot: AssistantSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Texto de busca: nome, bairro, prato (ex.: ramen, Shibuya). Vazio = todos.")
        var query: String
        @Guide(description: "Papel opcional (photo = spot de foto, sport = corrida/trilha/jogo)", .anyOf(["any", "eat", "drink", "see", "listen", "shop", "photo", "sport"]))
        var role: String
        @Guide(description: "Só abertos agora?")
        var openNow: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        var found = AssistantEngine.search(snapshot, query: arguments.query, role: StopRole(rawValue: arguments.role))
            .filter { AssistantEngine.sameCity($0, snapshot) }
        if arguments.openNow { found = found.filter { $0.hours?.isOpen(at: snapshot.now, timeZone: snapshot.region.timeZone) == true } }
        guard !found.isEmpty else { return "Nada no board com isso." }
        return found.prefix(8).map { p in
            "\(p.name) [id \(p.id)] · \(snapshot.listName(p))\(p.sub.map { " · \($0)" } ?? "") · \(p.area ?? "") · \(snapshot.region.money(p.cost))"
                + (AssistantEngine.kindNote(p, snapshot).map { " · \($0)" } ?? "")
        }.joined(separator: "\n")
    }
}

struct OpenNowTool: Tool {
    let name = "openNow"
    let description = "Lugares do board abertos agora perto do usuário (raio em km). Adiciona cartões 'Ir' pros 2 mais perto."
    let snapshot: AssistantSnapshot
    let collector: ActionCollector

    @Generable
    struct Arguments {
        @Guide(description: "Raio em km (padrão 1.5)", .range(0.3...10))
        var radiusKm: Double
        @Guide(description: "Papel opcional (photo = spot de foto, sport = corrida/trilha/jogo)", .anyOf(["any", "eat", "drink", "see", "listen", "shop", "photo", "sport"]))
        var role: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (places, confirmed) = AssistantEngine.openNow(snapshot, radiusKm: arguments.radiusKm, role: StopRole(rawValue: arguments.role))
        for (i, p) in places.prefix(2).enumerated() {
            await collector.add(AssistantAction(kind: .go, place: p, meta: [p.area, snapshot.listName(p)].compactMap { $0 }.joined(separator: " · "), highlighted: i == 0))
        }
        guard !places.isEmpty else { return "Nenhum must num raio de \(arguments.radiusKm) km de \(snapshot.areaName)." }
        let header = confirmed ? "Abertos agora perto de \(snapshot.areaName):" : "Perto de \(snapshot.areaName) (sem horário confirmado):"
        return header + "\n" + places.prefix(6).map { p in
            "\(p.name) · \(p.area ?? "") · \(snapshot.listName(p))" + (AssistantEngine.kindNote(p, snapshot).map { " · \($0)" } ?? "")
        }.joined(separator: "\n")
    }
}

struct SpentTodayTool: Tool {
    let name = "spentToday"
    let description = "Quanto o usuário gastou hoje (dia + exceção aceita) e quanto sobra da meta."
    let snapshot: AssistantSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Sempre true")
        var includeException: Bool
    }

    func call(arguments: Arguments) async throws -> String { AssistantEngine.spentText(snapshot) }
}

struct TodayPlanTool: Tool {
    let name = "todayPlan"
    let description = "As paradas do dia de hoje, com horário, id da parada e se já foi feita."
    let snapshot: AssistantSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Sempre true")
        var includeDone: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        guard !snapshot.stops.isEmpty else { return "Sem dia montado hoje." }
        return snapshot.stops.map { s in
            "parada \(s.id): \(snapshot.region.timeString(s.at)) \(s.place.name) · \(snapshot.listName(s.place))\(s.place.sub.map { " · \($0)" } ?? "")\(s.done ? " · feito" : "")\(s.isAnchor ? " · reserva fixa" : "")"
        }.joined(separator: "\n")
    }
}

struct SwapStopTool: Tool {
    let name = "swapStop"
    let description = """
    Prepara a troca de uma parada do dia (não aplica). Passe o id da parada (de todayPlan) ou uma palavra \
    como "bar", "almoço", "jantar", e opcionalmente o id de um lugar do board. Sem lugar, escolhe até 2 opções \
    elegíveis; o usuário confirma tocando em Trocar.
    """
    let snapshot: AssistantSnapshot
    let collector: ActionCollector

    @Generable
    struct Arguments {
        @Guide(description: "Id da parada ou palavra (bar, almoço, jantar, café)")
        var stop: String
        @Guide(description: "Id de um lugar do board, ou vazio pra eu escolher")
        var placeId: String
        @Guide(description: "Preferir perto da reserva/jantar?")
        var nearAnchor: Bool
        @Guide(description: "Preferir mais barato?")
        var cheaper: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let target = snapshot.stops.first { $0.id == arguments.stop } ?? AssistantEngine.targetStop(snapshot, text: arguments.stop)
        guard let target else { return "Não achei essa parada no dia de hoje." }
        if target.isAnchor { return "\(target.place.name) é reserva fixa — não troco." }
        var options = AssistantEngine.swapCandidates(snapshot, stop: target, cheaper: arguments.cheaper, nearAnchor: arguments.nearAnchor)
        if !arguments.placeId.isEmpty, let chosen = snapshot.catalog.first(where: { $0.id == arguments.placeId }) {
            options = [(chosen, [chosen.area, chosen.sub?.lowercased()].compactMap { $0 }.joined(separator: " · "))]
        }
        guard !options.isEmpty else { return "Nenhuma alternativa elegível pro \(target.place.name) nesse horário." }
        for (i, o) in options.enumerated() {
            await collector.add(AssistantAction(kind: .swap(stopId: target.id, replacing: target.place.name), place: o.place, meta: o.note, highlighted: i == 0))
        }
        await collector.note("\(target.place.name) fica pro outro dia.")
        return "Opções no lugar do \(target.place.name): " + options.map { "\($0.place.name) (\($0.note))" }.joined(separator: "; ")
            + ". Os cartões já aparecem pro usuário confirmar."
    }
}

struct LastTrainTool: Tool {
    let name = "lastTrainHome"
    let description = "Último metrô/trem pra casa hoje."
    let snapshot: AssistantSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Sempre true")
        var today: Bool
    }

    func call(arguments: Arguments) async throws -> String { AssistantEngine.lastTrainText(snapshot) }
}

struct WeatherTool: Tool {
    let name = "weather"
    let description = "Previsão de hoje ou amanhã (temperatura, condição, chance de chuva)."
    let snapshot: AssistantSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Qual dia", .anyOf(["hoje", "amanhã"]))
        var day: String
    }

    func call(arguments: Arguments) async throws -> String {
        AssistantEngine.weatherText(snapshot, tomorrow: arguments.day != "hoje")
    }
}

struct DistanceTool: Tool {
    let name = "distance"
    let description = "Distância e tempo a pé entre dois lugares do board (por id), ou do usuário até um lugar (from vazio)."
    let snapshot: AssistantSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Id do lugar de origem, ou vazio pra posição atual")
        var from: String
        @Guide(description: "Id do lugar de destino")
        var to: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let to = snapshot.catalog.first(where: { $0.id == arguments.to }) else { return "Destino não está no board." }
        let fromCoord: CLLocationCoordinate2D?
        if let from = snapshot.catalog.first(where: { $0.id == arguments.from }) {
            fromCoord = CLLocationCoordinate2D(latitude: from.lat, longitude: from.lng)
        } else {
            fromCoord = snapshot.here
        }
        guard let fromCoord else { return "Sem posição atual." }
        let leg = DaySolver.leg(fromCoord, CLLocationCoordinate2D(latitude: to.lat, longitude: to.lng), walkMax: snapshot.walkMaxKm)
        return "\(Walk.distanceText(leg.km * 1000)) · \(leg.mode == .walk ? "\(leg.minutes) min a pé" : "metrô ~\(leg.minutes) min")"
    }
}

enum AssistantTools {
    static func all(_ s: AssistantSnapshot, collector: ActionCollector) -> [any Tool] {
        [SearchBoardTool(snapshot: s), OpenNowTool(snapshot: s, collector: collector), SpentTodayTool(snapshot: s),
         TodayPlanTool(snapshot: s), SwapStopTool(snapshot: s, collector: collector), LastTrainTool(snapshot: s),
         WeatherTool(snapshot: s), DistanceTool(snapshot: s)]
    }
}
