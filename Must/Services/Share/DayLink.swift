import Compression
import Foundation

// Link do dia (prompt 25 · B.2): o dia inteiro vai **dentro** do link, comprimido, pra abrir sem servidor.
// `must://d/<payload>` no app; `web/d/index.html#<payload>` renderiza o mesmo cartaz numa página estática.
// Só paradas, horários e ids/nomes (e a coordenada arredondada pro mini-mapa) — nada de foto, preço ou nota.
// O domínio `must.app` ainda não existe: sem Universal Link nem associated domains por enquanto.

/// O dia como vai no link. Chaves de uma letra: cada byte conta (o WhatsApp corta link longo na prévia).
struct SharedDay: Codable, Hashable, Sendable {
    struct Stop: Codable, Hashable, Sendable {
        /// `Place.id` (o board de quem recebe pode ter o mesmo seed: o toque abre o Lugar).
        var i: String?
        /// Título da parada ("Fuunji · tsukemen").
        var l: String
        /// Tipo: "a" âncora, "m" Must, "u" micro-parada.
        var k: String
        /// Início e fim em minutos desde a meia-noite do dia (no fuso da região). Passa de 1440 depois da meia-noite.
        var b: Int
        var e: Int
        /// Selo curto ("QR", "RES", "SOL", "café").
        var g: String?
        /// Coordenada com 4 casas (~11 m): só pro mini-mapa.
        var y: Double?
        var x: Double?
    }

    /// Versão do formato.
    var v: Int = 1
    /// Região (`Region.rawValue`): o fuso e a cor do cartaz vêm daqui.
    var r: String
    /// Dia ("2026-11-15").
    var d: String
    /// Título do dia ("Shinjuku + Tsukiji").
    var t: String
    /// Número do dia na viagem.
    var n: Int?
    /// Nome do bairro principal ("Shinjuku").
    var a: String?
    /// Cidade ("Tóquio").
    var c: String?
    var s: [Stop]

    var region: Region? { Region(rawValue: r) }
}

extension SharedDay {
    /// Monta o payload a partir do dia. `coordinates`: `placeId` → (lat, lng) do board, pra paradas sem coordenada.
    init(plan: DayPlan, region: Region, areaName: String?, cityName: String?,
         coordinates: [String: (Double, Double)] = [:]) {
        let cal = region.calendar
        let midnight = cal.startOfDay(for: plan.date)
        func minutes(_ date: Date) -> Int { Int((date.timeIntervalSince(midnight) / 60).rounded()) }
        func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        self.init(
            r: region.rawValue,
            d: BoardDates(timeZone: region.timeZone).dayString(plan.date),
            t: plan.title,
            n: plan.dayNumber,
            a: areaName,
            c: cityName,
            s: plan.stops.map { stop in
                let coord: (Double, Double)? = if let lat = stop.lat, let lng = stop.lng { (lat, lng) }
                    else { stop.placeId.flatMap { coordinates[$0] } }
                return Stop(i: stop.placeId, l: stop.label, k: Self.code(stop.kind), b: minutes(stop.start), e: minutes(stop.end),
                            g: stop.tag, y: coord.map { round4($0.0) }, x: coord.map { round4($0.1) })
            }
        )
    }

    static func code(_ kind: StopKind) -> String {
        switch kind {
        case .anchor: "a"
        case .must: "m"
        case .micro: "u"
        }
    }

    static func kind(_ code: String) -> StopKind {
        switch code {
        case "a": .anchor
        case "u": .micro
        default: .must
        }
    }

    /// O dia de volta no formato v8 (só leitura: sem legs, sem custo, sem notas).
    func plan() -> DayPlan? {
        guard let region, let day = BoardDates(timeZone: region.timeZone).day(from: d) else { return nil }
        let stops = s.enumerated().map { index, stop in
            DayStop(id: "d\(index + 1)", placeId: stop.i, kind: Self.kind(stop.k),
                    start: day.addingTimeInterval(Double(stop.b) * 60), end: day.addingTimeInterval(Double(max(stop.e, stop.b)) * 60),
                    label: stop.l, note: "", tag: stop.g, lat: stop.y, lng: stop.x)
        }
        return DayPlan(date: day, title: t, dayNumber: n, area: nil, stops: stops, legs: [], lastTrain: nil,
                       pace: .normal, budget: 0)
    }
}

/// Codifica e decodifica o payload: JSON → zlib → base64url (sem `=`).
enum DayLink {
    static let scheme = "must"
    static let host = "d"
    /// Teto do payload no link (o dia de 12 paradas fica em ~600 caracteres).
    static let maxPayload = 6_000
    /// Teto do JSON descomprimido: nada maior que isso é um dia.
    static let maxJSON = 64 * 1024

    enum Failure: Error, Equatable { case tooLong, notBase64, corrupt, notADay }

    static func payload(_ day: SharedDay) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(day)
        guard let packed = compress(json) else { throw Failure.corrupt }
        return base64url(packed)
    }

    static func url(_ day: SharedDay) throws -> URL {
        URL(string: "\(scheme)://\(host)/\(try payload(day))")!
    }

    /// Página estática (prompt 25 · B.2) que desenha o cartaz a partir do mesmo payload. O domínio ainda não existe.
    /// TODO(p25:2): quando houver domínio (`must.app`), Universal Link `https://must.app/d/<payload>` e a página no R2.
    static func webURL(_ day: SharedDay, base: String = "https://must.app/d/") throws -> URL {
        URL(string: base + "#" + (try payload(day)))!
    }

    static func decode(_ payload: String) throws -> SharedDay {
        guard payload.count <= maxPayload else { throw Failure.tooLong }
        guard let packed = unbase64url(payload) else { throw Failure.notBase64 }
        guard let json = decompress(packed) else { throw Failure.corrupt }
        guard let day = try? JSONDecoder().decode(SharedDay.self, from: json), day.region != nil, !day.s.isEmpty else {
            throw Failure.notADay
        }
        return day
    }

    /// O payload de um `must://d/<payload>`; `nil` se não é um link do dia.
    static func payload(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == host else { return nil }
        let raw = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }

    // MARK: base64url

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func unbase64url(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" }) else { return nil }
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    // MARK: zlib (deflate cru, o mesmo que o `DecompressionStream("deflate-raw")` da página web lê)

    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 512
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return out.prefix(written)
    }

    /// Descomprime num buffer de tamanho fixo (`maxJSON`): um payload malicioso não estoura a memória.
    static func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var out = Data(count: maxJSON)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, maxJSON,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < maxJSON else { return nil }
        return out.prefix(written)
    }
}
