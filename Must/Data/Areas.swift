import CoreLocation
import Foundation

/// Bairro (prompt 18 · C.13): centroide, estação principal e vizinhos com o tempo de trem, ônibus ou a pé.
/// A tabela é curada (`Must/Data/areas/{tokyo,kyoto,bh}.json`, no bundle): sem rede, sem geocoder.
/// `heroPhotoRef` não vem do JSON: é a foto escolhida no aparelho, uma vez, e guardada (`AreaHeroes`).
struct Area: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    /// Nome local do bairro (kanji no Japão), só pra mostrar a alguém. Nunca vai pro selo. BH: `nil`.
    var nameLocal: String?
    /// Grupo de cidade: `tokyo` (Tóquio 1 e 2), `kyoto`, `bh`. Ver `AreaCatalog.cityGroup`.
    var cityId: String
    var centroid: Coordinate
    var polygon: [Coordinate]?
    /// Estações do bairro, no formato `linha-nome` (ex.: `jy-shinjuku`). A primeira é a principal.
    var stationIds: [String]
    /// Outros nomes que o board usa pro mesmo bairro ("Shibuya Stream" → Shibuya).
    var aliases: [String]
    var neighbors: [Neighbor]
    /// v7: texto do selo (sigla do BH). Substituído por `stampCode`; lido só como fallback.
    var stampText: String?
    /// Linha pequena do selo: o nome latino do bairro no Japão ("Shinjuku"), "BH · 1897" no Brasil.
    var stampSub: String?
    /// Foto principal escolhida uma vez no aparelho (URL do Commons). `nil` até escolher.
    var heroPhotoRef: String?
    /// Sigla latina do selo (chave `"stampCode"` no JSON): código de estação JR quando existe (Shinjuku SJK,
    /// Shibuya SBY), senão 3 letras do nome (Ginza GNZ). Nunca kanji.
    var stampCode: String? = nil

    /// Texto do selo: a sigla latina (tabela › v7 › 3 letras do nome). Nunca o kanji.
    var seal: String { stampCode ?? stampText ?? AreaCode.derive(name) ?? name }

    /// Linha pequena do selo: a da tabela, senão o nome latino.
    var sealSub: String { stampSub ?? name }

    var mainStation: String? { stationIds.first }

    /// Vizinho direto. `minutes` é o tempo de ida; o de volta vem na tabela do outro bairro.
    struct Neighbor: Codable, Hashable, Sendable {
        var areaId: String
        var minutes: Int
        var mode: TransitMode
        /// Linha do trecho (não existe pra caminhada).
        var line: LineRef?
    }

    struct Coordinate: Codable, Hashable, Sendable {
        var lat: Double
        var lng: Double

        var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }
}

enum TransitMode: String, Codable, Hashable, Sendable {
    case train, bus, walk

    var label: String {
        switch self {
        case .train: "trem"
        case .bus: "ônibus"
        case .walk: "a pé"
        }
    }
}

/// Linha de trem ou metrô com a cor oficial (`#RRGGBB`).
struct LineRef: Codable, Hashable, Sendable {
    var code: String
    var name: String
    var color: String

    /// Cor como `0xRRGGBB` (0 se o texto não for um `#RRGGBB` válido).
    var rgb: UInt32 {
        let hex = color.hasPrefix("#") ? String(color.dropFirst()) : color
        return UInt32(hex, radix: 16) ?? 0
    }
}

/// Arquivo `Must/Data/areas/<região>.json`.
struct AreaFile: Codable, Sendable {
    var version: Int
    var region: String
    var cityId: String
    var areas: [Area]
}

/// Carrega as tabelas de bairros do bundle, uma vez por processo (JSON pequeno, nunca no `body`).
enum AreaCatalog {
    private final class BundleAnchor {}

    /// Tabelas curadas por país (`curatedAreas` em `data/countries/<cc>.json`): JP tokyo+kyoto, BR bh, IT roma.
    static let curated: [String: [Area]] = CountryProfile.bundled.reduce(into: [:]) { out, entry in
        if let files = entry.value.curatedAreas, !files.isEmpty { out[entry.key] = load(files) }
    }
    static var jp: [Area] { curated["JP"] ?? [] }
    static var bh: [Area] { curated["BR"] ?? [] }
    /// Todas as tabelas curadas (o solver por área acha o bairro de um lugar e os vizinhos por aqui).
    static let all: [Area] = ["JP", "BR", "IT"].flatMap { curated[$0] ?? [] }

    /// Bairros da viagem: as de fábrica usam a tabela curada do país; as criadas no app, os gerados dos Musts
    /// (`GeneratedAreas`, prompt 28 §3.5).
    static func areas(for region: Region) -> [Area] {
        if region.trip.isBuiltIn { return curated[region.country] ?? [] }
        return GeneratedAreaStore.shared.areas(for: region.rawValue)
    }

    /// Só os gerados (vazio nas de fábrica): o solver soma com `all` pro foco por bairro.
    static func generated(for region: Region?) -> [Area] {
        guard let region, !region.trip.isBuiltIn else { return [] }
        return GeneratedAreaStore.shared.areas(for: region.rawValue)
    }

    /// Tóquio 1 e 2 são a mesma cidade pro bairro (o solver já trata assim).
    static func cityGroup(forCityId cityId: String) -> String {
        cityId.hasPrefix("tokyo") ? "tokyo" : cityId
    }

    /// Lê `<nome>.json` do bundle do app (ou do bundle de testes). Arquivo faltando: lista vazia e log.
    static func load(_ names: [String], bundle: Bundle? = nil) -> [Area] {
        names.flatMap { name -> [Area] in
            for candidate in [bundle ?? .main, Bundle(for: BundleAnchor.self)] {
                if let url = candidate.url(forResource: name, withExtension: "json"),
                   let data = try? Data(contentsOf: url),
                   let file = try? JSONDecoder().decode(AreaFile.self, from: data) {
                    return file.areas
                }
            }
            Log.app.error("areas/\(name, privacy: .public).json não está no bundle")
            return []
        }
    }
}

/// Nome de bairro sem acento, caixa ou pontuação: "Naka-Meguro" = "Nakameguro" = "naka meguro".
enum AreaName {
    static func key(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

/// Liga um lugar ao bairro: primeiro pelo nome (`Place.area`, com nomes e apelidos), senão pelo centroide mais
/// perto dentro de 1,2 km, na mesma cidade. Sem nenhum dos dois: `nil` ("outros").
struct AreaAssigner: Sendable {
    /// Distância máxima do centroide pra contar como bairro (sem nome).
    static let maxDistance: CLLocationDistance = 1200

    private let areas: [Area]
    /// `cidade|nome normalizado` → id do bairro.
    private let byName: [String: String]

    init(areas: [Area]) {
        self.areas = areas
        var table: [String: String] = [:]
        for area in areas {
            let city = AreaCatalog.cityGroup(forCityId: area.cityId)
            for name in [area.name] + area.aliases {
                table["\(city)|\(AreaName.key(name))"] = area.id
            }
        }
        byName = table
    }

    /// `cityId` é o do lugar (`tokyo1`, `kyoto`, `bh`), não o do bairro.
    func areaId(name: String?, cityId: String, lat: Double, lng: Double) -> String? {
        let city = AreaCatalog.cityGroup(forCityId: cityId)
        if let name, let id = byName["\(city)|\(AreaName.key(name))"] { return id }
        guard lat != 0 || lng != 0 else { return nil }
        let here = CLLocation(latitude: lat, longitude: lng)
        var best: (id: String, meters: CLLocationDistance)?
        for area in areas where AreaCatalog.cityGroup(forCityId: area.cityId) == city {
            let meters = CLLocation(latitude: area.centroid.lat, longitude: area.centroid.lng).distance(from: here)
            if meters <= Self.maxDistance, best == nil || meters < best!.meters { best = (area.id, meters) }
        }
        return best?.id
    }
}
