import CoreLocation
import Foundation
import Observation

/// Estado do fluxo Nova viagem (prompt 28 · F3): o `NewTripDraft` + o passo atual + as regras (noites, datas das cidades,
/// total e câmbio, conferência dos lugares). Sem rede: tudo aqui roda no aparelho. Quem grava é o `TripCreating`.
@MainActor
@Observable
final class NewTripModel {
    static let stepCount = 9
    /// Passos de pergunta (a barra tem 8 segmentos; o 9 é o Pronto).
    static let questionSteps = 8

    var draft: NewTripDraft
    var step: Int
    /// Mês mostrado no calendário (primeiro dia).
    var visibleMonth: Date
    /// O usuário mexeu nas noites à mão: parar de redistribuir sozinho.
    private(set) var nightsEdited = false
    /// Texto do câmbio digitado.
    var fxText = ""
    /// Passo 6: de onde vieram os lugares ("texto colado", "links", "Maps").
    var placesSource = ""
    var startedEmpty = false

    enum CreateState: Equatable {
        case idle, creating, failed(String), done(String)
    }
    var createState: CreateState = .idle

    private let now: () -> Date

    init(draft: NewTripDraft = NewTripDraft(), step: Int = 1, now: @escaping () -> Date = { AppClock.now }) {
        self.draft = draft
        self.step = min(max(step, 1), Self.stepCount)
        self.now = now
        self.visibleMonth = Self.firstOfMonth(draft.start ?? now())
        if draft.fxRate == nil, !draft.currency.isEmpty { self.draft.fxRate = NewTripCatalog.cachedRate(draft.currency) }
    }

    // MARK: Calendário (UTC fixo: a data do calendário é "dia", sem hora; evita deslocar por fuso)

    nonisolated static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        c.firstWeekday = 2
        return c
    }()

    static func firstOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute)) ?? Date()
    }

    func shiftMonth(_ delta: Int) {
        visibleMonth = Self.calendar.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
    }

    /// Toque no dia: 1º define a ida; 2º (depois da ida) fecha a volta; um toque antes da ida troca a ida; com as duas, recomeça.
    func tapDay(_ date: Date) {
        let d = Self.calendar.startOfDay(for: date)
        if draft.start == nil || draft.end != nil {
            draft.start = d
            draft.end = nil
        } else if let start = draft.start, d < start {
            draft.start = d
        } else if d == draft.start {
            draft.start = d
        } else {
            draft.end = d
        }
        redistributeIfNeeded()
    }

    func clearDates() {
        draft.start = nil
        draft.end = nil
    }

    /// Dias da viagem (inclusive): 12–20 mar = 9.
    var tripDays: Int? { draft.tripNights.map { $0 + 1 } }

    /// Dias até embarcar (0 se já começou); nil sem data de ida.
    var daysUntilStart: Int? {
        guard let start = draft.start else { return nil }
        let today = Self.calendar.startOfDay(for: now())
        let local = Calendar.current.dateComponents([.year, .month, .day], from: now())
        let todayLocal = Self.calendar.date(from: local) ?? today
        return max(0, Self.calendar.dateComponents([.day], from: todayLocal, to: start).day ?? 0)
    }

    // MARK: Passo 1

    func choose(country: NewTripCatalog.Country) {
        let changed = draft.countryCode != country.code
        draft.countryCode = country.code
        draft.name = country.name
        draft.currency = country.currency
        draft.timeZoneId = country.timeZoneId
        draft.colorHex = NewTripCatalog.coverHex(for: country.code)
        draft.fxRate = NewTripCatalog.cachedRate(country.currency)
        if changed { fxText = "" }
    }

    /// Digitado à mão (offline, sem lista): nome livre, país desconhecido.
    func chooseManual(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let match = NewTripCatalog.search(clean, limit: 1).first, NewTripCatalog.fold(match.name) == NewTripCatalog.fold(clean) {
            choose(country: match)
            return
        }
        draft.name = clean
        if draft.timeZoneId.isEmpty { draft.timeZoneId = TimeZone.current.identifier }
        if draft.colorHex.isEmpty { draft.colorHex = NewTripCatalog.hex(NewTripCatalog.swatches[0]) }
    }

    var hasDestination: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Passo 3 · cidades e noites

    func addCity(name: String, latitude: Double = 0, longitude: Double = 0, timeZoneId: String? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft.cities.append(.init(name: clean, latitude: latitude, longitude: longitude, nights: 1,
                                  timeZoneId: timeZoneId ?? (draft.timeZoneId.isEmpty ? nil : draft.timeZoneId)))
        redistributeIfNeeded()
    }

    func removeCity(id: String) {
        draft.cities.removeAll { $0.id == id }
        redistributeIfNeeded()
    }

    func moveCities(from: IndexSet, to: Int) {
        draft.cities.move(fromOffsets: from, toOffset: to)
    }

    func moveCity(id: String, by delta: Int) {
        guard let i = draft.cities.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard draft.cities.indices.contains(j) else { return }
        draft.cities.swapAt(i, j)
    }

    func setNights(_ nights: Int, cityId: String) {
        guard let i = draft.cities.firstIndex(where: { $0.id == cityId }) else { return }
        draft.cities[i].nights = min(max(nights, 0), 60)
        nightsEdited = true
    }

    /// Divide as noites da viagem entre as cidades (o resto vai pras primeiras). Só se o usuário não mexeu à mão.
    func redistributeIfNeeded() {
        guard !nightsEdited else { return }
        distributeNights()
    }

    func distributeNights() {
        guard let total = draft.tripNights, !draft.cities.isEmpty, total >= 0 else { return }
        let n = draft.cities.count
        let base = total / n, extra = total % n
        for i in draft.cities.indices { draft.cities[i].nights = base + (i < extra ? 1 : 0) }
    }

    /// "8 noites de 8" quando há datas; sem datas, só a soma.
    var nightsCheck: (sum: Int, of: Int?, matches: Bool) {
        let sum = draft.totalNights
        guard let total = draft.tripNights else { return (sum, nil, true) }
        return (sum, total, sum == total)
    }

    /// Entrada e saída de cada cidade (a partir da ida, somando as noites). Nil sem datas.
    func cityRange(at index: Int) -> (from: Date, to: Date)? {
        guard let start = draft.start, draft.cities.indices.contains(index) else { return nil }
        let before = draft.cities[..<index].reduce(0) { $0 + $1.nights }
        let from = Self.calendar.date(byAdding: .day, value: before, to: start) ?? start
        let to = Self.calendar.date(byAdding: .day, value: draft.cities[index].nights, to: from) ?? from
        return (from, to)
    }

    // MARK: Passo 4 · hospedagem

    func setLodging(cityId: String, name: String, address: String, checkIn: Date?, checkOut: Date?, fromEmail: Bool) {
        guard let i = draft.cities.firstIndex(where: { $0.id == cityId }) else { return }
        draft.cities[i].lodgingName = name.isEmpty ? nil : name
        draft.cities[i].lodgingAddress = address.isEmpty ? nil : address
        draft.cities[i].checkIn = checkIn
        draft.cities[i].checkOut = checkOut
        draft.cities[i].lodgingFromEmail = fromEmail
        draft.cities[i].neighborhoodOnly = nil
    }

    func setNeighborhood(cityId: String, _ text: String) {
        guard let i = draft.cities.firstIndex(where: { $0.id == cityId }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.cities[i].neighborhoodOnly = clean.isEmpty ? nil : clean
        if !clean.isEmpty {
            draft.cities[i].lodgingName = nil
            draft.cities[i].lodgingAddress = nil
        }
    }

    func clearLodging(cityId: String) {
        guard let i = draft.cities.firstIndex(where: { $0.id == cityId }) else { return }
        draft.cities[i].lodgingName = nil
        draft.cities[i].lodgingAddress = nil
        draft.cities[i].neighborhoodOnly = nil
        draft.cities[i].checkIn = nil
        draft.cities[i].checkOut = nil
        draft.cities[i].lodgingFromEmail = false
    }

    var lodgingFilled: Int {
        draft.cities.filter { $0.lodgingName != nil || $0.neighborhoodOnly != nil }.count
    }

    // MARK: Passo 5 · voos

    func addFlight(_ flight: NewTripDraft.FlightDraft) {
        draft.flights.append(flight)
        draft.flights.sort { ($0.departure ?? .distantFuture) < ($1.departure ?? .distantFuture) }
    }

    func removeFlight(at index: Int) {
        guard draft.flights.indices.contains(index) else { return }
        draft.flights.remove(at: index)
    }

    /// Voo lido: ida ou volta? Com datas, a metade final da viagem é volta; sem, o 1º é ida e o resto volta.
    func isReturn(departure: Date?, order: Int) -> Bool {
        if let departure, let start = draft.start, let end = draft.end {
            let mid = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            return departure > mid
        }
        return order > 0
    }

    // MARK: Passo 6 · lugares

    func cityId(for text: String, lat: Double?, lng: Double?) -> String? {
        let folded = NewTripCatalog.fold(text)
        if let hit = draft.cities.first(where: { folded.contains(NewTripCatalog.fold($0.name)) }) { return hit.id }
        if let lat, let lng {
            let here = CLLocation(latitude: lat, longitude: lng)
            let near = draft.cities
                .filter { $0.latitude != 0 || $0.longitude != 0 }
                .map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
                .min { $0.1 < $1.1 }
            if let near, near.1 < 80_000 { return near.0.id }
        }
        return draft.cities.count == 1 ? draft.cities.first?.id : nil
    }

    /// Texto de IA/lista → lugares (o `TravelTextParser` e o `PlaceExtractor` de sempre, no aparelho).
    @discardableResult
    func importText(_ raw: String) -> Int {
        let parsed = TravelTextParser.parse(raw, knownAreas: draft.cities.map(\.name))
        var added = 0
        for place in parsed.places {
            let dayTitle = place.dayIndex.flatMap { parsed.days.indices.contains($0) ? parsed.days[$0].title : nil } ?? ""
            let hint = [place.area ?? "", place.hint, dayTitle].joined(separator: " ")
            let draftPlace = NewTripDraft.PlaceDraft(
                name: place.name, cityId: cityId(for: hint, lat: place.lat, lng: place.lng), listId: place.category?.rawValue,
                latitude: place.lat, longitude: place.lng, googlePlaceId: place.placeId, note: place.sub)
            added += append(draftPlace) ? 1 : 0
        }
        if added > 0 { placesSource = "do texto colado" }
        return added
    }

    /// Um link por linha: Maps traz nome e coordenada no próprio endereço; o resto entra pelo nome do caminho.
    @discardableResult
    func importLinks(_ raw: String) -> Int {
        var added = 0
        for token in raw.split(whereSeparator: \.isWhitespace) {
            let resolved = LinkResolver.resolve(String(token))
            guard let url = resolved.url else { continue }
            var name: String?
            var lat: Double?, lng: Double?
            if resolved.source == .maps {
                let maps = LinkResolver.parseMaps(url)
                name = maps.name; lat = maps.lat; lng = maps.lng
            }
            if name == nil {
                let slug = url.pathComponents.last { $0 != "/" && !$0.isEmpty && Int($0) == nil } ?? (url.host() ?? "")
                name = slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: ".html", with: "").capitalized
            }
            guard let name, !name.isEmpty else { continue }
            let p = NewTripDraft.PlaceDraft(name: name, cityId: cityId(for: name, lat: lat, lng: lng), listId: nil,
                                            latitude: lat, longitude: lng, googlePlaceId: nil, note: url.absoluteString)
            added += append(p) ? 1 : 0
        }
        if added > 0 { placesSource = "dos links" }
        return added
    }

    @discardableResult
    func importSaved(_ data: Data) -> Int {
        var added = 0
        for saved in SavedPlacesImporter.parse(data) {
            let p = NewTripDraft.PlaceDraft(name: saved.name, cityId: cityId(for: saved.name, lat: saved.lat, lng: saved.lng),
                                            listId: nil, latitude: saved.lat, longitude: saved.lng, googlePlaceId: nil, note: saved.note)
            added += append(p) ? 1 : 0
        }
        if added > 0 { placesSource = "dos salvos do Maps" }
        return added
    }

    private func append(_ p: NewTripDraft.PlaceDraft) -> Bool {
        let key = NewTripCatalog.fold(p.name)
        guard !draft.places.contains(where: { NewTripCatalog.fold($0.name) == key }) else { return false }
        draft.places.append(p)
        return true
    }

    func removePlace(at index: Int) {
        guard draft.places.indices.contains(index) else { return }
        draft.places.remove(at: index)
    }

    /// "9 em Lisboa · 3 no Porto" (+ "2 sem cidade").
    var placesBreakdown: String {
        var parts: [String] = []
        for city in draft.cities {
            let n = draft.places.filter { $0.cityId == city.id }.count
            if n > 0 { parts.append("\(n) \(Self.preposition(city.name)) \(city.name)") }
        }
        let loose = draft.places.filter { p in !draft.cities.contains { $0.id == p.cityId } }.count
        if loose > 0 { parts.append("\(loose) sem cidade") }
        return parts.joined(separator: " · ")
    }

    /// "em Lisboa", "no Porto": "no" só nos nomes que carregam o artigo.
    static func preposition(_ name: String) -> String {
        ["Porto", "Rio de Janeiro", "Cairo"].contains(name) ? "no" : "em"
    }

    // MARK: Passo 7 · orçamento

    func stepBudget(_ delta: Double) {
        let step: Double = draft.currency == "JPY" ? 1000 : 10
        draft.perDayBudget = max(0, (draft.perDayBudget ?? 0) + delta * step)
    }

    var totalBudget: Double? {
        guard let per = draft.perDayBudget, let days = tripDays else { return nil }
        return per * Double(days)
    }

    var totalInReais: Double? {
        guard let total = totalBudget, let rate = draft.fxRate, draft.currency != "BRL" else { return nil }
        return total * rate
    }

    func setFX(text: String) {
        fxText = text
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), value > 0 {
            draft.fxRate = value
            NewTripCatalog.storeRate(value, for: draft.currency)
        }
    }

    // MARK: Navegação

    func next() { step = min(step + 1, Self.stepCount) }
    func back() { step = max(step - 1, 1) }

    /// Cabeçalho "NOVA VIAGEM · 3 DE 8" + a linha de contexto do passo (canto direito do design).
    var contextLine: String {
        let short = Date.FormatStyle().locale(NewTripCatalog.locale).weekday(.abbreviated).day().month(.abbreviated)
        func fmt(_ d: Date) -> String {
            var style = short
            style.timeZone = Self.calendar.timeZone
            return d.formatted(style).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "").uppercased()
        }
        switch step {
        case 1: return "PAÍS E COR"
        case 2:
            if let s = draft.start, let e = draft.end { return "\(fmt(s)) → \(fmt(e))" }
            return draft.start.map { fmt($0) } ?? "DATAS"
        case 3: return draft.cities.isEmpty ? "CIDADES" : draft.cities.map(\.name).joined(separator: " · ").uppercased()
        case 4: return "\(lodgingFilled) DE \(max(draft.cities.count, 0))"
        case 5: return "\(draft.flights.count) \(draft.flights.count == 1 ? "VOO" : "VOOS")"
        case 6: return draft.places.isEmpty ? "LUGARES" : "\(draft.places.count) \(draft.places.count == 1 ? "LIDO" : "LIDOS")"
        case 7:
            let sym = NewTripCatalog.currencySymbol(draft.currency)
            return "\(sym) \(Int(draft.perDayBudget ?? 0)) POR DIA"
        case 8: return "\(estimatedMB) MB"
        default: return "PRONTO"
        }
    }

    // MARK: Passo 8 · mapas offline

    /// Pack do catálogo `data/map-packs.json` que cobre a cidade (pela coordenada). Nil = não existe.
    func pack(for city: NewTripDraft.City) -> MapPack? {
        guard city.latitude != 0 || city.longitude != 0 else { return nil }
        let c = CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)
        return MapPack.catalog.first { $0.contains(c) }
    }

    /// Id sugerido pro pack que falta: "pt-porto".
    func suggestedPackId(for city: NewTripDraft.City) -> String {
        let country = draft.countryCode.lowercased()
        let slug = NewTripCatalog.fold(city.name).replacingOccurrences(of: " ", with: "-")
        return country.isEmpty ? slug : "\(country)-\(slug)"
    }

    /// Comando do `scripts/tiles.sh` que o Vinicius roda pra gerar o pack que falta.
    func tilesCommand(for city: NewTripDraft.City) -> String { "scripts/tiles.sh \"\" \(suggestedPackId(for: city))" }

    /// Tamanho estimado: packs do catálogo (se estão no servidor) + ~1,5 MB por lugar de foto.
    func estimatedBytes(maps: OfflineMaps?) -> Int64 {
        let ids = Set(draft.cities.compactMap { pack(for: $0)?.id })
        let mapBytes = ids.reduce(Int64(0)) { $0 + (maps?.bytes($1) ?? 0) }
        return mapBytes + Int64(draft.places.count) * 1_500_000
    }

    var estimatedMB: Int { Int((estimatedBytes(maps: nil) / 1_000_000)) }

    // MARK: Passo 9 · criar

    func create(with creator: any TripCreating) async {
        guard createState != .creating else { return }
        createState = .creating
        do {
            let id = try await creator.create(draft)
            createState = .done(id)
        } catch {
            // O rascunho fica como está: o usuário tenta de novo ou volta e ajusta.
            createState = .failed("Não consegui criar a viagem agora. Seu rascunho está guardado; tente de novo em instantes.")
        }
    }
}
