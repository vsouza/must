import CoreLocation
import Foundation

/// Id de viagem (prompt 28 §3.1). As três de fábrica ficam com os ids de região de antes (`bh`, `jp`, `it`): os
/// arquivos `must-bh.store`, `must-jp.store`, `must-it.store` não mudam. Viagem nova: `<slug>-<4 letras>`.
typealias TripID = String

/// Uma viagem do registro (`trips.json` no App Group, `TripRegistry`). Não é SwiftData: o board, os gastos e as
/// cidades com hospedagem continuam no container da viagem (`must-<id>.store`). Aqui só o que a lista "Minhas
/// viagens" e a região automática precisam sem abrir container.
struct Trip: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Hashable, Sendable {
        /// A cidade de casa (BH): sempre disponível, último recurso do automático.
        case home
        case trip
    }

    var id: TripID
    /// "Japão", "Belo Horizonte", "Portugal".
    var name: String
    /// Rótulo curto ("BH"). `nil` = o nome.
    var shortName: String?
    /// ISO 3166-1 alfa-2.
    var countryCode: String
    /// ISO 4217.
    var currency: String
    /// Fuso padrão (cada cidade pode ter o seu).
    var timeZone: String
    /// Cor da capa (`#RRGGBB`). `nil` = a do país.
    var colorHex: String?
    var kind: Kind
    /// "yyyy-MM-dd" no fuso da viagem. `nil` = viagem em plano ("ainda não sei").
    var start: String?
    var end: String?
    var cities: [TripCity]
    var home: TripHome?
    var createdAt: Date
    var archived: Bool
    /// `bh` | `jp` | `it` pras de fábrica (seed no bundle, bairros curados). `nil` nas criadas no app.
    var seedId: String?

    struct TripCity: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: String
        var lat: Double
        var lng: Double
        var from: String?
        var to: String?
        var tz: String?
    }

    /// Hospedagem ou bairro base (passo 4 da Nova viagem).
    struct TripHome: Codable, Hashable, Sendable {
        var name: String?
        var address: String?
        var lat: Double?
        var lng: Double?
        var neighborhood: String?
    }

    // MARK: Derivados

    var displayShortName: String { shortName ?? name }
    var isBuiltIn: Bool { seedId != nil }
    var storeFileName: String { "must-\(id).store" }
    var tz: TimeZone { TimeZone(identifier: timeZone) ?? CountryProfile.forCountry(countryCode).tz }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.locale = Locale(identifier: "pt_BR")
        return cal
    }

    /// Centro padrão: a primeira cidade, senão o centro do país.
    var center: CLLocationCoordinate2D {
        if let c = cities.first { return CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng) }
        if let c = CountryProfile.forCountry(countryCode).center { return c.clCoordinate }
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    /// Datas como intervalo de dias (início do dia no fuso da viagem). `nil` sem as duas datas.
    var range: ClosedRange<Date>? {
        let dates = BoardDates(timeZone: tz)
        guard let start = start.flatMap(dates.day(from:)), let end = end.flatMap(dates.day(from:)), start <= end else { return nil }
        return start...end
    }

    /// Hoje está entre as datas (no fuso da viagem)?
    func contains(_ now: Date) -> Bool {
        guard let range else { return false }
        return range.contains(calendar.startOfDay(for: now))
    }

    // MARK: Id novo

    /// "Portugal" → "portugal-k3f9". Só letras/dígitos ASCII; 4 letras aleatórias (sem colidir com `taken`).
    static func newID(name: String, taken: Set<TripID> = [], random: () -> String = { Trip.randomSuffix() }) -> TripID {
        var slug = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
            .reduce(into: "") { out, ch in if !(ch == "-" && out.hasSuffix("-")) { out.append(ch) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "viagem" }
        slug = String(slug.prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        for _ in 0..<50 {
            let id = "\(slug)-\(random())"
            if !taken.contains(id), !BuiltInTrip.ids.contains(id) { return id }
        }
        return "\(slug)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    static func randomSuffix() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }
}

/// As três viagens de fábrica (o que era o `enum Region`): ids, nomes e datas como estavam no código.
/// O registro é semeado com estas na primeira abertura depois do update (prompt 28 §3.2).
enum BuiltInTrip {
    static let ids: [TripID] = ["bh", "jp", "it"]

    static let createdAt = Date(timeIntervalSince1970: 1_798_761_600) // 01/01/2027 00:00 UTC: só pra ordenar, nunca exibido

    static let bh = Trip(id: "bh", name: "Belo Horizonte", shortName: "BH", countryCode: "BR", currency: "BRL",
                         timeZone: "America/Sao_Paulo", colorHex: nil, kind: .home, start: nil, end: nil,
                         cities: [.init(id: "bh", name: "Belo Horizonte", lat: -19.9245, lng: -43.9352, tz: "America/Sao_Paulo")],
                         home: nil, createdAt: createdAt.addingTimeInterval(-3), archived: false, seedId: "bh")

    /// 11–24 nov 2026, Tóquio → Kyoto → Tóquio (`CLAUDE.md`).
    static let jp = Trip(id: "jp", name: "Japão", shortName: "Japão", countryCode: "JP", currency: "JPY",
                         timeZone: "Asia/Tokyo", colorHex: nil, kind: .trip, start: "2026-11-11", end: "2026-11-24",
                         cities: [.init(id: "tokyo1", name: "Tóquio", lat: 35.6762, lng: 139.6503, tz: "Asia/Tokyo")],
                         home: nil, createdAt: createdAt.addingTimeInterval(-2), archived: false, seedId: "jp")

    /// Datas [A CONFIRMAR] (prompt 24): fica em plano, sem datas no registro.
    static let it = Trip(id: "it", name: "Roma", shortName: "Roma", countryCode: "IT", currency: "EUR",
                         timeZone: "Europe/Rome", colorHex: nil, kind: .trip, start: nil, end: nil,
                         cities: [.init(id: "roma", name: "Roma", lat: 41.8955, lng: 12.4823, tz: "Europe/Rome")],
                         home: nil, createdAt: createdAt.addingTimeInterval(-1), archived: false, seedId: "it")

    static let all: [Trip] = [bh, jp, it]

    static func trip(_ id: TripID) -> Trip? { all.first { $0.id == id } }
}
