import Foundation

/// SKUs da Google Maps Platform que o Must usa (prompt 17 · A). Cada uma tem a cota grátis por mês.
enum GoogleSKU: String, CaseIterable, Sendable, Identifiable {
    case placesIdsOnly, placesEssentials, placesPro, placePhotos, autocomplete
    case routesEssentials, routesPro, routeMatrix, streetViewMetadata, streetView

    var id: String { rawValue }

    /// Cota grátis por mês. `nil` = sem limite (IDs Only e o metadata do Street View são grátis).
    var freeMonthly: Int? {
        switch self {
        case .placesIdsOnly, .streetViewMetadata: nil
        case .placesEssentials, .autocomplete, .routesEssentials, .routeMatrix, .streetView: 10_000
        case .placesPro, .routesPro: 5_000
        case .placePhotos: 1_000
        }
    }

    var label: String {
        switch self {
        case .placesIdsOnly: "Places · IDs only"
        case .placesEssentials: "Places · Essentials"
        case .placesPro: "Places · Pro"
        case .placePhotos: "Places · Fotos"
        case .autocomplete: "Autocomplete"
        case .routesEssentials: "Routes · Essentials"
        case .routesPro: "Routes · Pro (transporte com tarifa)"
        case .routeMatrix: "Route Matrix (solver)"
        case .streetViewMetadata: "Street View · metadata"
        case .streetView: "Street View · imagem"
        }
    }

    /// Para o que a tela de uso mostra embaixo do nome.
    var detail: String {
        switch self {
        case .placesIdsOnly: "ilimitado · conferir/juntar"
        case .placesEssentials: "10 mil grátis/mês · endereço, coordenada, tipo"
        case .placesPro: "5 mil grátis/mês · horário, nota, preço"
        case .placePhotos: "1 mil grátis/mês · só sem foto do Commons"
        case .autocomplete: "10 mil grátis/mês · Buscar por nome"
        case .routesEssentials: "10 mil grátis/mês · a pé, carro, trajeto"
        case .routesPro: "5 mil grátis/mês · trajeto com tarifa"
        case .routeMatrix: "10 mil elementos grátis/mês · solver"
        case .streetViewMetadata: "grátis · confere se há foto"
        case .streetView: "10 mil grátis/mês · só quando o metadata vem OK"
        }
    }

    /// Só os SKUs de Places (migra o contador antigo `PlacesUsage`).
    static let places: [GoogleSKU] = [.placesIdsOnly, .placesEssentials, .placesPro, .placePhotos]
}

/// Por que uma chamada não sai.
enum ApiBlock: Error, Equatable, Sendable {
    case dailyCapZero
    case dailyCapReached(cap: Int)
    case monthlyCut(sku: GoogleSKU, used: Int)
    case unavailableToday(sku: GoogleSKU)

    var message: String {
        switch self {
        case .dailyCapZero: "teto diário em 0 · Google desligado em Ajustes"
        case .dailyCapReached(let cap): "teto diário de \(cap) chamadas atingido"
        case .monthlyCut(let sku, let used): "\(sku.label) em \(used) · corte de 80% da cota do mês"
        case .unavailableToday(let sku): "\(sku.label) indisponível hoje (a chave recusou)"
        }
    }
}

/// Contador de chamadas Google por SKU e por mês (UserDefaults, como o `FlightQuota`).
/// Antes de cada chamada, `admit`; depois de uma resposta boa, `record`; 403/REQUEST_DENIED marca a SKU indisponível até amanhã.
/// Estado puro e testável: recebe `defaults` e `now`.
enum ApiBudget {
    /// Corte automático: a partir de 80% da cota grátis do mês, a chamada não sai (com log).
    static let cutFraction = 0.8
    /// Teto diário padrão (chamadas somadas, todas as SKUs). Ajustável em Ajustes › Dados.
    static let defaultDailyCap = 300
    static let dailyCapOptions = [0, 50, 100, 200, 300, 500, 1000]

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static func monthKey(_ now: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func dayKey(_ now: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func usedKey(_ sku: GoogleSKU, _ now: Date) -> String { "api.used.\(sku.rawValue).\(monthKey(now))" }
    static func dayTotalKey(_ now: Date) -> String { "api.day.\(dayKey(now))" }
    static func unavailableKey(_ sku: GoogleSKU) -> String { "api.unavailable.\(sku.rawValue)" }
    static let dailyCapKey = "api.dailyCap"

    // MARK: Leitura

    static func used(_ sku: GoogleSKU, now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Int {
        migrateLegacyPlaces(now: now, defaults: defaults)
        return defaults.integer(forKey: usedKey(sku, now))
    }

    /// Soma do mês das SKUs de Places (o número que a linha "Google Places" mostra).
    static func placesUsedThisMonth(now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Int {
        GoogleSKU.places.reduce(0) { $0 + used($1, now: now, defaults: defaults) }
    }

    static func usedToday(now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: dayTotalKey(now))
    }

    static func dailyCap(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: dailyCapKey) as? Int ?? defaultDailyCap
    }

    static func setDailyCap(_ cap: Int, defaults: UserDefaults = .standard) {
        defaults.set(max(0, cap), forKey: dailyCapKey)
    }

    /// Indisponível até o dia seguinte (403 / REQUEST_DENIED: API desligada ou chave recusada).
    static func isUnavailable(_ sku: GoogleSKU, now: Date = AppClock.now, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: unavailableKey(sku)) == dayKey(now)
    }

    /// Diz se uma chamada pode sair agora. `units` = elementos (matriz) ou 1.
    static func check(_ sku: GoogleSKU, units: Int = 1, now: Date = AppClock.now, defaults: UserDefaults = .standard) -> ApiBlock? {
        migrateLegacyPlaces(now: now, defaults: defaults)
        let cap = dailyCap(defaults: defaults)
        if cap == 0 { return .dailyCapZero }
        if isUnavailable(sku, now: now, defaults: defaults) { return .unavailableToday(sku: sku) }
        if usedToday(now: now, defaults: defaults) + units > cap { return .dailyCapReached(cap: cap) }
        if let free = sku.freeMonthly {
            let cut = Int((Double(free) * cutFraction).rounded(.down))
            let used = defaults.integer(forKey: usedKey(sku, now))
            if used + units > cut { return .monthlyCut(sku: sku, used: used) }
        }
        return nil
    }

    /// Decide e, se não sair, registra no log o motivo (o app segue sem erro na UI).
    @discardableResult
    static func admit(_ sku: GoogleSKU, units: Int = 1, now: Date = AppClock.now, defaults: UserDefaults = .standard) -> ApiBlock? {
        let block = check(sku, units: units, now: now, defaults: defaults)
        if let block { Log.network.notice("google \(sku.rawValue, privacy: .public) bloqueado: \(block.message, privacy: .public)") }
        return block
    }

    // MARK: Escrita

    static func record(_ sku: GoogleSKU, units: Int = 1, now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: usedKey(sku, now)) + units, forKey: usedKey(sku, now))
        defaults.set(defaults.integer(forKey: dayTotalKey(now)) + units, forKey: dayTotalKey(now))
    }

    static func markUnavailable(_ sku: GoogleSKU, now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(dayKey(now), forKey: unavailableKey(sku))
        Log.network.notice("google \(sku.rawValue, privacy: .public) indisponível até amanhã")
    }

    /// Contador antigo do Places (`places.calls.AAAA-MM`) entra uma vez por mês como Essentials.
    static func migrateLegacyPlaces(now: Date, defaults: UserDefaults) {
        let month = monthKey(now)
        let flag = "api.migrated.\(month)"
        guard !defaults.bool(forKey: flag) else { return }
        let legacy = defaults.integer(forKey: "places.calls.\(month)")
        if legacy > 0 { defaults.set(defaults.integer(forKey: usedKey(.placesEssentials, now)) + legacy, forKey: usedKey(.placesEssentials, now)) }
        defaults.set(true, forKey: flag)
    }
}

/// Chamada Google com orçamento: `admit` → chamada → `record` (ou `markUnavailable` em 403/REQUEST_DENIED).
/// Todos os serviços do Google passam por aqui (Places, Nearby, Autocomplete, Routes, Street View, fotos).
enum GoogleAPI {
    static func run<T>(_ sku: GoogleSKU, units: Int = 1, now: Date = AppClock.now, defaults: UserDefaults = .standard,
                       _ body: () async throws -> T) async throws -> T {
        if let block = ApiBudget.admit(sku, units: units, now: now, defaults: defaults) {
            throw ServiceError.budget(block.message)
        }
        do {
            let value = try await body()
            ApiBudget.record(sku, units: units, now: now, defaults: defaults)
            return value
        } catch let ServiceError.http(code, body) where code == 403 || body.contains("REQUEST_DENIED") {
            ApiBudget.markUnavailable(sku, now: now, defaults: defaults)
            throw ServiceError.http(code, body)
        }
    }

    /// Chave e cabeçalho do bundle. `mask` vazio = sem FieldMask (Maps Static/Street View usam só a query).
    static func headers(key: String, mask: String? = nil) -> [String: String] {
        var h = ["X-Goog-Api-Key": key, "X-Ios-Bundle-Identifier": Bundle.main.bundleIdentifier ?? "dev.viniso.must"]
        if let mask { h["X-Goog-FieldMask"] = mask }
        return h
    }
}
