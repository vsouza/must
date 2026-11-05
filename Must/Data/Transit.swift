import CoreLocation
import Foundation
import SwiftUI

/// Uma linha de metrô/trem (GeoJSON em `Data/transit/`).
struct TransitLine: Identifiable, Sendable {
    var id: String
    var name: String
    var nameLatin: String
    var color: Color
    /// Trechos contínuos.
    var paths: [[CLLocationCoordinate2D]]
    var approx: Bool
    var lastTrain: String?
}

struct TransitStation: Identifiable, Sendable {
    var name: String
    var coordinate: CLLocationCoordinate2D
    var lines: [String]
    var id: String { "\(name)-\(coordinate.latitude)-\(coordinate.longitude)" }
}

struct TransitMap: Sendable {
    var lines: [TransitLine]
    var stations: [TransitStation]
    var attribution: String?

    static let empty = TransitMap(lines: [], stations: [], attribution: nil)

    func line(_ id: String) -> TransitLine? { lines.first { $0.id == id } }
}

/// Lê `tokyo-lines.geojson` / `bh-lines.geojson` / `roma-lines.geojson` do bundle (uma vez por região).
/// Roma ainda não tem o GeoJSON: o mapa fica sem as linhas (nunca as de BH).
enum TransitLoader {
    @MainActor private static var cache: [Region: TransitMap] = [:]

    static func fileName(for region: Region) -> String {
        switch region {
        case .jp: "tokyo-lines"
        case .bh: "bh-lines"
        case .it: "roma-lines" // TODO(v8:E): gerar roma-lines.geojson (Metro A/B/C + tram 8) com scripts/gen-transit.py
        }
    }

    @MainActor
    static func load(_ region: Region, bundle: Bundle = .main) -> TransitMap {
        if let cached = cache[region] { return cached }
        let map = bundle.url(forResource: fileName(for: region), withExtension: "geojson")
            .flatMap { try? Data(contentsOf: $0) }
            .map(parse) ?? .empty
        if map.lines.isEmpty { Log.data.error("transit \(region.rawValue, privacy: .public): GeoJSON vazio ou ausente") }
        cache[region] = map
        return map
    }

    static func parse(_ data: Data) -> TransitMap {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else { return .empty }
        var lines: [TransitLine] = []
        var stations: [TransitStation] = []
        for feature in features {
            let props = feature["properties"] as? [String: Any] ?? [:]
            let geometry = feature["geometry"] as? [String: Any] ?? [:]
            switch props["kind"] as? String {
            case "line":
                var parts: [[[Double]]] = []
                if geometry["type"] as? String == "MultiLineString" { parts = geometry["coordinates"] as? [[[Double]]] ?? [] }
                if geometry["type"] as? String == "LineString", let one = geometry["coordinates"] as? [[Double]] { parts = [one] }
                let paths = chain(parts.map { $0.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil } })
                lines.append(TransitLine(id: props["id"] as? String ?? UUID().uuidString, name: props["name"] as? String ?? "",
                                         nameLatin: props["nameLatin"] as? String ?? "", color: Color(hexString: props["color"] as? String ?? "#888888"),
                                         paths: paths, approx: props["approx"] as? Bool ?? false, lastTrain: props["lastTrain"] as? String))
            case "station":
                guard let c = geometry["coordinates"] as? [Double], c.count >= 2 else { continue }
                stations.append(TransitStation(name: props["name"] as? String ?? "", coordinate: CLLocationCoordinate2D(latitude: c[1], longitude: c[0]),
                                               lines: props["lines"] as? [String] ?? []))
            default: continue
            }
        }
        return TransitMap(lines: lines, stations: stations, attribution: json["attribution"] as? String)
    }

    /// Junta trechos que se encostam (fim de um = começo de outro) pra desenhar menos polilinhas.
    static func chain(_ parts: [[CLLocationCoordinate2D]]) -> [[CLLocationCoordinate2D]] {
        func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            abs(a.latitude - b.latitude) < 0.00002 && abs(a.longitude - b.longitude) < 0.00002
        }
        var remaining = parts.filter { $0.count >= 2 }
        var result: [[CLLocationCoordinate2D]] = []
        while var current = remaining.popLast() {
            var grew = true
            while grew {
                grew = false
                for (i, part) in remaining.enumerated() {
                    if same(current.last!, part.first!) { current += part.dropFirst() }
                    else if same(current.last!, part.last!) { current += part.reversed().dropFirst() }
                    else if same(current.first!, part.last!) { current = part + current.dropFirst() }
                    else if same(current.first!, part.first!) { current = part.reversed() + current.dropFirst() }
                    else { continue }
                    remaining.remove(at: i)
                    grew = true
                    break
                }
            }
            result.append(current)
        }
        return result
    }
}

extension Color {
    /// "#0C6DB2"
    init(hexString: String) {
        let hex = UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(hex: hex)
    }
}
