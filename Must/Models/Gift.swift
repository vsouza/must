import CoreLocation
import Foundation
import SwiftData

// Lista de presentes (prompt 31 · item 7): o que comprar pra quem, no container da viagem. Aditivo: todos os campos têm padrão
// (migração leve). Pessoas não têm tabela: são os nomes distintos de `Gift.person`.

/// De onde veio o presente (aba usada no "Novo presente").
enum GiftSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case name, link, video, place, photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Nome"
        case .link: "Link"
        case .video: "Vídeo"
        case .place: "Local"
        case .photo: "Foto"
        }
    }

    /// "do vídeo", "link" (meta da linha).
    var metaLabel: String? {
        switch self {
        case .name: nil
        case .link: "link"
        case .video: "do vídeo"
        case .place: "do board"
        case .photo: "da foto"
        }
    }
}

@Model
final class Gift {
    @Attribute(.unique) var id: String = UUID().uuidString
    var title: String = ""
    /// Nome da pessoa ("Ana"). Vazio = "Sem pessoa".
    var person: String = ""
    var quantity: Int = 1
    /// Preço de uma unidade, na moeda da viagem.
    var estimatedPrice: Double = 0
    /// Quanto pagou (total), depois de comprado.
    var paidPrice: Double?
    var boughtAt: Date?
    var sourceRaw: String = GiftSource.name.rawValue
    var sourceURL: String?
    /// "@tokyosnacks" (autor do vídeo/link), pro "veio de".
    var sourceLabel: String = ""
    /// Item da caixa do Share Extension de onde veio o vídeo.
    var videoInboxId: String?
    /// "0:12–0:19": o trecho do vídeo onde o presente aparece.
    var videoClip: String?
    var photoId: String?
    /// Loja do board (`Place.id`).
    var placeId: String?
    /// Loja fora do board (do Explorar) ou rede: nome, coordenada opcional.
    var storeName: String = ""
    var storeLat: Double?
    var storeLng: Double?
    /// "Qualquer <rede>": só vira loja concreta dentro do quero, sob demanda.
    var chain: Bool = false
    var note: String = ""
    var order: Int = 0
    /// Loja (Must) onde foi comprado: o Must "feito por" este presente.
    var boughtPlaceId: String?
    var expenseId: UUID?
    var createdAt: Date = AppClock.now

    init(id: String = UUID().uuidString, title: String, person: String = "", quantity: Int = 1, estimatedPrice: Double = 0,
         source: GiftSource = .name, placeId: String? = nil, storeName: String = "", note: String = "", order: Int = 0,
         createdAt: Date = AppClock.now) {
        self.id = id
        self.title = title
        self.person = person
        self.quantity = max(1, quantity)
        self.estimatedPrice = estimatedPrice
        self.sourceRaw = source.rawValue
        self.placeId = placeId
        self.storeName = storeName
        self.note = note
        self.order = order
        self.createdAt = createdAt
    }

    var source: GiftSource {
        get { GiftSource(rawValue: sourceRaw) ?? .name }
        set { sourceRaw = newValue.rawValue }
    }

    var isBought: Bool { boughtAt != nil }
    /// Previsto da linha (unidade × quantidade).
    var estimatedTotal: Double { estimatedPrice * Double(quantity) }
    /// O que conta no previsto: o pago, se comprou e anotou; senão o estimado.
    var committedTotal: Double { isBought ? (paidPrice ?? estimatedTotal) : estimatedTotal }
    var personName: String {
        let trimmed = person.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? GiftLogic.noPerson : trimmed
    }
    var hasStoreCoordinate: Bool { storeLat != nil && storeLng != nil }
}

extension ModelContext {
    /// Presentes da viagem, na ordem em que foram criados.
    func gifts() -> [Gift] {
        let items = (try? fetch(FetchDescriptor<Gift>())) ?? []
        return items.sorted { ($0.order, $0.createdAt, $0.id) < ($1.order, $1.createdAt, $1.id) }
    }
}

// MARK: - Lógica pura

/// Um presente ao alcance de uma loja: a loja resolvida, a distância e se está aberta.
struct GiftNearby: Identifiable, Equatable {
    var id: String { giftId }
    var giftId: String
    var title: String
    var person: String
    var quantity: Int
    var storeName: String
    var storeId: String?
    var coordinate: CLLocationCoordinate2D
    var meters: Double
    var minutes: Int
    var isOpen: Bool

    static func == (a: GiftNearby, b: GiftNearby) -> Bool { a.giftId == b.giftId && a.meters == b.meters && a.isOpen == b.isOpen }
}

struct GiftGroup: Identifiable, Equatable {
    var id: String { person }
    var person: String
    var gifts: [Gift]
    var pending: Int { gifts.filter { !$0.isBought }.count }
    var subtotal: Double { gifts.reduce(0) { $0 + $1.committedTotal } }

    static func == (a: GiftGroup, b: GiftGroup) -> Bool { a.person == b.person && a.gifts.map(\.id) == b.gifts.map(\.id) }
}

enum GiftLogic {
    static let noPerson = "Sem pessoa"
    /// "Perto" = a até 10 min a pé.
    static let nearMinutes = 10
    static let streetFactor = 1.25

    /// Agrupa por pessoa: quem tem item perto primeiro, depois alfabética (sem pessoa por último). Dentro do grupo, os que faltam
    /// antes dos comprados.
    static func groups(_ gifts: [Gift], nearby: Set<String> = []) -> [GiftGroup] {
        let byPerson = Dictionary(grouping: gifts, by: \.personName)
        let groups = byPerson.map { person, items in
            GiftGroup(person: person, gifts: items.sorted { a, b in
                if a.isBought != b.isBought { return !a.isBought }
                if nearby.contains(a.id) != nearby.contains(b.id) { return nearby.contains(a.id) }
                return (a.order, a.createdAt, a.id) < (b.order, b.createdAt, b.id)
            })
        }
        return groups.sorted { a, b in
            if (a.person == noPerson) != (b.person == noPerson) { return b.person == noPerson }
            let x = a.gifts.contains { nearby.contains($0.id) && !$0.isBought }
            let y = b.gifts.contains { nearby.contains($0.id) && !$0.isBought }
            if x != y { return x }
            return a.person.localizedCaseInsensitiveCompare(b.person) == .orderedAscending
        }
    }

    /// Quantos ainda faltam comprar (soma de itens, não de unidades).
    static func pendingCount(_ gifts: [Gift]) -> Int { gifts.filter { !$0.isBought }.count }
    /// Previsto: pago onde já comprou, estimado onde falta.
    static func plannedTotal(_ gifts: [Gift]) -> Double { gifts.reduce(0) { $0 + $1.committedTotal } }
    static func people(_ gifts: [Gift]) -> [String] {
        Array(Set(gifts.map(\.personName).filter { $0 != noPerson })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Resolve a loja de um presente: o lugar do board (com coordenada) ou a coordenada guardada. "Qualquer rede" sem lugar
    /// concreto não tem loja aqui (só no quero).
    static func store(of gift: Gift, places: [Place]) -> (name: String, id: String?, coordinate: CLLocationCoordinate2D, place: Place?)? {
        if let id = gift.placeId, let place = places.first(where: { $0.id == id }) {
            return (place.name, place.id, place.coordinate, place)
        }
        if let lat = gift.storeLat, let lng = gift.storeLng {
            return (gift.storeName, nil, CLLocationCoordinate2D(latitude: lat, longitude: lng), nil)
        }
        return nil
    }

    /// Presentes pendentes cuja loja está a ≤ 10 min a pé e aberta (horário desconhecido não é "fechado"). Do mais perto.
    static func nearby(gifts: [Gift], places: [Place], here: CLLocationCoordinate2D?, now: Date, timeZone: TimeZone,
                       maxMinutes: Int = nearMinutes) -> [GiftNearby] {
        guard let here else { return [] }
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        var out: [GiftNearby] = []
        for gift in gifts where !gift.isBought {
            guard let store = store(of: gift, places: places) else { continue }
            let meters = CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude).distance(from: origin) * streetFactor
            let minutes = Walk.minutes(meters)
            guard minutes <= maxMinutes else { continue }
            let state = store.place?.openState(at: now, timeZone: timeZone)
            if let state, case .closed = state { continue }
            out.append(GiftNearby(giftId: gift.id, title: gift.title, person: gift.personName == noPerson ? "" : gift.personName,
                                  quantity: gift.quantity, storeName: store.name, storeId: store.id, coordinate: store.coordinate,
                                  meters: meters, minutes: minutes, isOpen: state?.isOpen ?? true))
        }
        return out.sorted { ($0.meters, $0.giftId) < ($1.meters, $1.giftId) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    /// O pedido do quero é sobre presente? ("presente", "comprar presente", "lembrancinha", ou o nome de uma pessoa da lista).
    static func isGiftWant(_ text: String, people: [String]) -> Bool {
        let t = fold(text)
        if t.contains("present") || t.contains("lembranc") { return true }
        let words = Set(t.split { !$0.isLetter }.map(String.init))
        return people.contains { words.contains(fold($0)) }
    }

    /// "Kit Kat de matcha × 3" quando a quantidade passa de 1.
    static func titleWithQty(_ gift: Gift) -> String { gift.quantity > 1 ? "\(gift.title) × \(gift.quantity)" : gift.title }

    /// Comprou: grava o pago, a data e o gasto do dia (categoria compras, nota "presente · item · pessoa"). Devolve o gasto criado.
    @discardableResult
    static func markBought(_ gift: Gift, paid: Double, at date: Date, context: ModelContext, store: Place?) -> Expense {
        gift.paidPrice = paid
        gift.boughtAt = date
        gift.boughtPlaceId = store?.id ?? gift.placeId
        let expense = Expense(at: date, amount: paid, category: .shop, place: store, method: .card)
        expense.note = "presente · \(gift.title)\(gift.personName == noPerson ? "" : " · \(gift.personName)")"
        context.insert(expense)
        gift.expenseId = expense.id
        try? context.save()
        return expense
    }

    /// Desfazer: tira o gasto e volta a "falta comprar".
    static func undoBought(_ gift: Gift, context: ModelContext) {
        if let id = gift.expenseId,
           let expense = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first {
            context.delete(expense)
        }
        gift.expenseId = nil
        gift.paidPrice = nil
        gift.boughtAt = nil
        gift.boughtPlaceId = nil
        try? context.save()
    }

    /// Renomeia a pessoa em todos os presentes.
    static func rename(person: String, to newName: String, in gifts: [Gift]) {
        for g in gifts where g.personName == person { g.person = newName }
    }
}
