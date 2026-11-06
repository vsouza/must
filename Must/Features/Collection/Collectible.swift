import Foundation

// Colecionável (prompt 27 §4, RODADA-23 · D): cada "feito" vira um card, derivado dos dados que já existem
// (`Place.done`, bairro, lista). Sem modelo SwiftData novo: a ordem é a posição entre os feitos por `done.at`,
// então desfazer o feito remove o card e recalcula a ordem.

enum CollectibleVariant: String, Hashable, Sendable, CaseIterable {
    /// Cor da viagem (padrão).
    case trip
    /// Tinta: âncora (ingresso, reserva) — os "raros".
    case anchor
    /// Papel com contorno: ar livre (photo, see, sport).
    case outdoor
}

struct Collectible: Identifiable, Hashable, Sendable {
    var placeId: String
    /// Ordem do feito na coleção (1 = o primeiro) e o total do board.
    var order: Int
    var total: Int
    var variant: CollectibleVariant
    var title: String
    var area: String?
    var listId: String?
    var doneAt: Date
    /// Sigla latina do selo (SJK, GNZ, SAV). Nunca kanji.
    var stampCode: String = ""
    var cityId: String = ""
    var cityName: String = ""
    var listName: String = ""
    /// "tsukemen · Must eat".
    var subLine: String = ""
    /// Quantos feitos a região tem (o "38 no Japão" do momento).
    var doneCount: Int = 0
    var timeZoneId: String = "America/Sao_Paulo"
    /// Gasto registrado (só aparece no momento, nunca no card).
    var spent: Double?

    var id: String { placeId }
    var isRare: Bool { variant == .anchor }

    /// Colecionável de um lugar feito; `nil` se ainda não foi feito.
    @MainActor
    static func make(from place: Place, in all: [Place], region: Region? = nil) -> Collectible? {
        guard let done = place.done else { return nil }
        var doneOnes: [(id: String, at: Date)] = []
        for p in all { if let d = p.done { doneOnes.append((p.id, d.at)) } }
        doneOnes.sort { l, r in l.at != r.at ? l.at < r.at : l.id < r.id }
        let order = (doneOnes.firstIndex { $0.id == place.id } ?? doneOnes.count) + 1
        let city = CollectibleText.cityName(cityId: place.cityId)
        let list = place.list
        let kind = list?.kind ?? .place
        let color = list?.color
        let anchor = !place.tickets.isEmpty || place.reservation != nil
        let outdoor = kind == .photo || kind == .sport || color == .see || color == .temple
        let variant: CollectibleVariant = anchor ? .anchor : (outdoor ? .outdoor : .trip)
        let listName = list?.displayName ?? ""
        let sub = (place.sub ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return Collectible(placeId: place.id, order: order, total: all.count, variant: variant,
                           title: place.name, area: place.area, listId: list?.id, doneAt: done.at,
                           stampCode: CollectibleText.stamp(area: place.area, city: city, region: region),
                           cityId: place.cityId, cityName: city, listName: listName,
                           subLine: [sub, listName].filter { !$0.isEmpty }.joined(separator: " · "),
                           doneCount: doneOnes.count,
                           timeZoneId: (region?.timeZone ?? TimeZone(identifier: "America/Sao_Paulo")!).identifier,
                           spent: done.spent)
    }
}

/// Textos do card: tudo em letras latinas (nunca japonês, nunca coordenada).
enum CollectibleText {
    static func cityName(cityId: String) -> String {
        switch AreaCatalog.cityGroup(forCityId: cityId) {
        case "tokyo": "Tóquio"
        case "kyoto": "Kyoto"
        case "bh": "Belo Horizonte"
        default: cityId.prefix(1).uppercased() + cityId.dropFirst()
        }
    }

    /// Sigla do bairro: tabela (`Area.seal`), senão 3 letras do nome, senão da cidade.
    @MainActor
    static func stamp(area: String?, city: String, region: Region?) -> String {
        if let area, !area.isEmpty {
            let key = AreaName.key(area)
            let areas = region.map(AreaCatalog.areas(for:)) ?? AreaCatalog.all
            if let hit = areas.first(where: { AreaName.key($0.name) == key || $0.aliases.contains { AreaName.key($0) == key } }) {
                return hit.seal.uppercased()
            }
            if let code = AreaCode.derive(area) { return code.uppercased() }
        }
        return (AreaCode.derive(city) ?? "MUST").uppercased()
    }

    /// Tira CJK (kanji, kana) e ideogramas de largura cheia: o card só leva letras latinas.
    static func latinOnly(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { s in
            switch s.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x3000...0x303F: false
            default: true
            }
        }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
    }

    /// "sáb 15 nov 2026" no fuso do lugar.
    static func dateLabel(_ date: Date, timeZoneId: String, withYear: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = TimeZone(identifier: timeZoneId) ?? .current
        f.dateFormat = withYear ? "EEE d MMM yyyy" : "d MMM"
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func number(_ n: Int) -> String { String(format: "%03d", n) }
}

/// Estado da Coleção no aparelho, por região (`UserDefaults`): vitrine (até 3), visão escolhida, escondidos e os ids
/// que já tiveram a celebração.
struct CollectionPrefs {
    var regionId: String
    var defaults: UserDefaults = .standard

    enum Group: String, CaseIterable, Sendable { case city, list, date
        var label: String { switch self { case .city: "Cidade"; case .list: "Lista"; case .date: "Data" } }
    }

    static let maxPinned = 3

    private func key(_ name: String) -> String { "collection.\(name).\(regionId)" }

    var pinned: [String] {
        get { defaults.stringArray(forKey: key("pinned")) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(Self.maxPinned)), forKey: key("pinned")) }
    }
    var hidden: [String] {
        get { defaults.stringArray(forKey: key("hidden")) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: key("hidden")) }
    }
    var group: Group {
        get { Group(rawValue: defaults.string(forKey: key("group")) ?? "") ?? .city }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key("group")) }
    }
    var celebrated: Set<String> {
        get { Set(defaults.stringArray(forKey: key("celebrated")) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: key("celebrated")) }
    }

    /// Fixa (até 3; o mais antigo sai) ou desafixa.
    func togglePin(_ id: String) {
        var list = pinned
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else {
            list.append(id)
            if list.count > Self.maxPinned { list.removeFirst(list.count - Self.maxPinned) }
        }
        pinned = list
    }

    func toggleHidden(_ id: String) {
        var list = hidden
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id); pinned = pinned.filter { $0 != id } }
        hidden = list
    }
}

/// O momento de ganhar um colecionável ao marcar "Feito" (`ColecionavelNovo.png`). Quem marca feito (Lugar, Agora) só
/// chama `present`; `CollectibleCelebrationHost` (montado na `RootView`) escuta a notificação e mostra a tela.
@MainActor
enum CollectibleCelebration {
    static let notification = Notification.Name("must.collectible.new")
    static func present(for placeId: String) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: ["placeId": placeId])
    }
}
