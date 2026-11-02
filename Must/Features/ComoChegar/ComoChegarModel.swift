import CoreLocation
import Foundation
import Observation

/// Estado da tela Como chegar: as alternativas (metrô, a pé, táxi), a porta (Street View) e o "⇅" (inverter).
/// Carrega sem bloquear: a tela abre com a estimativa e troca quando o Routes responde.
@MainActor
@Observable
final class ComoChegarModel {
    let placeName: String
    let destination: CLLocationCoordinate2D
    let region: Region
    /// Âncora do dia (reserva ou ingresso): a chegada tem que ser antes dela.
    let anchor: Date?
    /// Frase da porta (primeira linha das notas do lugar).
    let doorNote: String?

    private(set) var options: [TravelOption] = []
    private(set) var card: StreetViewCard?
    private(set) var loading = false
    private(set) var departAt: Date
    /// Origem e destino trocados (o "⇅").
    private(set) var reversed = false
    var selected: TravelOption.Mode = .transit
    private(set) var origin: CLLocationCoordinate2D?

    init(placeName: String, destination: CLLocationCoordinate2D, region: Region, anchor: Date?, doorNote: String?, now: Date) {
        self.placeName = placeName
        self.destination = destination
        self.region = region
        self.anchor = anchor
        self.doorNote = doorNote
        departAt = now
    }

    var start: CLLocationCoordinate2D? { reversed ? destination : origin }
    var end: CLLocationCoordinate2D { reversed ? (origin ?? destination) : destination }

    var selectedOption: TravelOption? { options.first { $0.mode == selected } ?? options.first }

    /// Hora de sair e de chegar da alternativa escolhida (estimativa quando o Routes não respondeu).
    var departs: Date { selectedOption?.departs ?? departAt }
    var arrives: Date { selectedOption?.arrives ?? departAt.addingTimeInterval(TimeInterval((selectedOption?.minutes ?? 0) * 60)) }

    /// Minutos sobrando antes da âncora (chip verde). `nil` quando não há âncora ou não sobra tempo.
    var slackMinutes: Int? {
        guard let anchor else { return nil }
        let slack = Int(anchor.timeIntervalSince(arrives) / 60)
        return slack > 0 ? slack : nil
    }

    func load(origin: CLLocationCoordinate2D?, routes: any RoutesProviding, now: Date = AppClock.now) async {
        self.origin = origin
        guard let from = start else { return }
        departAt = now
        loading = true
        let to = end
        let streetCard = Task { try? await Self.streetCard(for: destination, caption: doorNote) }
        options = await TravelOptions.build(from: from, to: to, departAt: now, region: region, routes: routes)
        // Sem transporte (sem rede, sem rota), a tela abre em "a pé".
        if !options.contains(where: { $0.mode == .transit }) { selected = .walk }
        loading = false
        card = await streetCard.value
    }

    /// Troca origem e destino e recalcula. O cartão da porta não muda.
    func swapEnds(routes: any RoutesProviding, now: Date = AppClock.now) async {
        reversed.toggle()
        await load(origin: origin, routes: routes, now: now)
    }

    /// A porta: com o Google sem orçamento ou sem chave, `nil` e o card some.
    static func streetCard(for destination: CLLocationCoordinate2D, caption: String?) async throws -> StreetViewCard? {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "debugRoutes") == "fake" {
            return StreetViewCard(panoId: "fake", date: "2025-03", copyright: "© Google", heading: 120,
                                  imageFile: URL.temporaryDirectory.appending(path: "fake-streetview.jpg"), caption: caption)
        }
        #endif
        return try await StreetViewService().card(for: destination, caption: caption)
    }

    /// Primeiro ponto do trajeto: a parada de embarque (se houver) ou o próprio lugar.
    var firstStop: (coordinate: CLLocationCoordinate2D, walking: Bool) {
        if let step = selectedOption?.steps.first(where: { $0.kind == .transit }), let lat = step.from?.lat, let lng = step.from?.lng,
           selectedOption?.steps.first?.kind == .walk {
            return (CLLocationCoordinate2D(latitude: lat, longitude: lng), true)
        }
        return (end, selectedOption?.mode != .transit)
    }
}

extension ComoChegarModel {
    /// "Naka-Meguro" / "Aqui": o nome da origem na linha de cima. Sem GPS, o nome da cidade.
    static func originLabel(hasGPS: Bool, cityName: String?) -> String {
        hasGPS ? "Aqui" : (cityName ?? "Início")
    }

    /// "Placa branca 鮨 … no térreo" → primeira linha, sem espaço sobrando, no máximo 90 caracteres.
    static func doorLine(_ notes: String) -> String? {
        let line = notes.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return line.isEmpty ? nil : String(line.prefix(90))
    }
}
