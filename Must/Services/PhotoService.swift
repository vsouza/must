import CoreLocation
import Foundation

/// Foto com licença livre (CC BY/BY-SA, CC0, domínio público), sempre com crédito visível.
struct CCPhoto: Sendable, Hashable, Codable, Identifiable {
    var id: String
    var url: String
    var largeURL: String?
    var owner: String
    var licenseName: String
    var page: String
    /// Quem forneceu: nil = Wikimedia Commons; "Google" = Places Photos (prompt 17 · A).
    var source: String? = nil

    var pageURL: URL? { URL(string: page) }
    /// "foto · Wikimedia CC BY 2.0 · @autor" · "foto · Google · @autor"
    var credit: String {
        if let source { return "foto · \(source) · @\(owner)" }
        return "foto · Wikimedia \(licenseName) · @\(owner)"
    }

    /// `flickrId` é o nome antigo do campo persistido (guarda o id da foto, qualquer fonte).
    var listPhoto: ListPhoto {
        ListPhoto(flickrId: id, url: largeURL ?? url, credit: credit, license: licenseName, page: page)
    }
}

protocol PhotoProviding: Sendable {
    var isConfigured: Bool { get }
    func search(text: String) async throws -> [CCPhoto]
    func search(near: CLLocationCoordinate2D, radiusKm: Double) async throws -> [CCPhoto]
}

/// Wikimedia Commons (sem chave): busca por texto e por coordenada, só licenças livres. Cache 7 dias.
struct CommonsPhotoService: PhotoProviding {
    /// Largura pedida ao Commons. A API arredonda pra cima até um tamanho padrão do Wikimedia (…, 500, 960, 1280, …);
    /// 1024 virava 1280. 960 é o padrão logo acima dos 800 px que guardamos (`PhotoLoader.storedPixels`).
    static let requestWidth = 960

    var http = HTTP()
    var isConfigured: Bool { true }

    /// A política da Wikimedia pede User-Agent identificável.
    static let userAgent = "Must/1.0 (iOS; app pessoal de roteiro)"

    func search(text: String) async throws -> [CCPhoto] {
        try await run([
            "generator": "search", "gsrnamespace": "6", "gsrlimit": "12",
            "gsrsearch": "\(text) filetype:bitmap",
        ], cacheKey: "commons-t-\(text.lowercased())")
    }

    func search(near c: CLLocationCoordinate2D, radiusKm: Double) async throws -> [CCPhoto] {
        let radius = Int(min(10_000, max(10, radiusKm * 1000)))
        return try await run([
            "generator": "geosearch", "ggsnamespace": "6", "ggsprimary": "all", "ggslimit": "12",
            "ggscoord": String(format: "%.5f|%.5f", c.latitude, c.longitude), "ggsradius": "\(radius)",
        ], cacheKey: String(format: "commons-g-%.4f-%.4f-%d", c.latitude, c.longitude, radius))
    }

    private func run(_ params: [String: String], cacheKey: String) async throws -> [CCPhoto] {
        if let cached = await DiskCache.shared.data(for: cacheKey, maxAge: 7 * 86_400),
           let photos = try? JSONDecoder().decode([CCPhoto].self, from: cached) { return photos }
        var comps = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "imageinfo"), URLQueryItem(name: "iiprop", value: "url|extmetadata|mime"),
            URLQueryItem(name: "iiurlwidth", value: String(Self.requestWidth)),
        ] + params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = try await http.get(comps.url!, headers: ["User-Agent": Self.userAgent], service: "commons")
        let photos = try Self.parse(data)
        if let encoded = try? JSONEncoder().encode(photos) { await DiskCache.shared.store(encoded, for: cacheKey) }
        return photos
    }

    /// Lê `query.pages[].imageinfo[0]`; descarta o que não for foto ou não tiver licença livre.
    static func parse(_ data: Data) throws -> [CCPhoto] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("commons") }
        let pages = ((json["query"] as? [String: Any])?["pages"] as? [String: [String: Any]]) ?? [:]
        let ordered = pages.values.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return ordered.compactMap { page in
            guard let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  (info["mime"] as? String).map({ $0 == "image/jpeg" || $0 == "image/png" }) ?? true,
                  let thumb = info["thumburl"] as? String ?? info["url"] as? String,
                  let descriptionURL = info["descriptionurl"] as? String else { return nil }
            let meta = info["extmetadata"] as? [String: [String: Any]] ?? [:]
            func value(_ key: String) -> String? { meta[key]?["value"] as? String }
            guard let code = value("License")?.lowercased(), isFree(code) else { return nil }
            let artist = clean(value("Artist") ?? "").nonEmpty ?? "Wikimedia Commons"
            return CCPhoto(id: String(page["pageid"] as? Int ?? 0), url: thumb, largeURL: thumb,
                           owner: String(artist.prefix(28)), licenseName: value("LicenseShortName") ?? code.uppercased(),
                           page: descriptionURL)
        }
    }

    /// CC BY / BY-SA (qualquer versão), CC0, domínio público. Nunca NC/ND.
    static func isFree(_ code: String) -> Bool {
        if code.contains("-nc") || code.contains("-nd") { return false }
        return code.hasPrefix("cc-by") || code.hasPrefix("cc0") || code.hasPrefix("pd") || code.contains("public domain")
    }

    /// Tira HTML do campo `Artist` ("<a …>Maarten Heerlien</a> from Voorschoten" → "Maarten Heerlien").
    static func clean(_ html: String) -> String {
        let text = HTMLMeta.decodeEntities(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        let first = text.components(separatedBy: " from ").first ?? text
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Foto principal de um lugar no Commons: perto (300 m), senão do bairro. Usada pelo Lugar e pelo pré-download
/// do dia (prompt 18 · A.5), pra que os dois peçam a mesma foto (e a segunda vez vem do cache de 7 dias).
enum PlaceHero {
    static func commons(coordinate: CLLocationCoordinate2D, area: String?, cityName: String,
                        photos: any PhotoProviding) async throws -> CCPhoto? {
        var found = try await photos.search(near: coordinate, radiusKm: 0.3)
        if found.isEmpty, let area {
            found = try await photos.search(text: "\(area) \(cityName)")
        }
        return found.first
    }
}

struct FakePhotoService: PhotoProviding {
    var isConfigured = true
    var photos: [CCPhoto] = []
    func search(text: String) async throws -> [CCPhoto] { photos }
    func search(near: CLLocationCoordinate2D, radiusKm: Double) async throws -> [CCPhoto] { photos }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
