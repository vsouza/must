import CoreLocation
import Foundation
import SwiftUI

// Atalhos (prompt 25 · D, `Atalhos.png`): o que se usa dez vezes por dia, a um deslize da capa. Tudo daqui é do aparelho
// (Carteira anotada, dia aceito, mapas baixados, tabela de estações, último "Por perto" no cache): nada chama rede.

/// Um card da grade 2×2.
struct AtalhoCard: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case wallet, today, map, sos }
    enum Tone: Sendable { case ink, orange, white, alert }

    var kind: Kind
    var label: String
    var title: String
    var detail: String
    var tone: Tone

    var id: String { kind.rawValue }
}

/// Uma linha de trem/metrô perto (chip com o código na cor da linha).
struct AtalhoLine: Identifiable, Hashable, Sendable {
    var code: String
    var name: String
    var rgb: UInt32
    var id: String { code }
}

/// "Linhas perto": a estação mais próxima, a pé, e as linhas dela; embaixo o último trem e a próxima saída do dia.
struct AtalhoLines: Hashable, Sendable {
    var station: String
    var walkMinutes: Int
    var lines: [AtalhoLine]
    /// "último Yamanote 00:40 · saia às 14:27 pro Gyoen".
    var note: String?
}

/// Um indicado por perto (fora do board).
struct AtalhoPick: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var reason: String
}

enum AtalhosRules {
    // MARK: Grade

    /// Suica no Japão (saldo anotado, abre o Wallet); fora do Japão não há Suica: o cartão de transporte anotado, ou a Carteira.
    static func walletCard(region: Region, transitName: String?, balance: Double?, notedNote: String?, walletCount: Int) -> AtalhoCard {
        if region == .jp {
            let value = balance.map { region.money($0) } ?? "anotar saldo"
            return AtalhoCard(kind: .wallet, label: "Wallet", title: "\(transitName ?? "Suica")\n\(value)",
                              detail: balance == nil ? "abre a Carteira · anotar" : "abre o Wallet · \(notedNote ?? "recarregar")", tone: .ink)
        }
        if let transitName {
            let value = balance.map { region.money($0) } ?? "saldo"
            return AtalhoCard(kind: .wallet, label: "Carteira", title: "\(transitName)\n\(value)",
                              detail: notedNote ?? "cartão de transporte · anotado", tone: .ink)
        }
        let items = walletCount == 1 ? "1 item" : "\(walletCount) itens"
        return AtalhoCard(kind: .wallet, label: "Carteira", title: "Carteira", detail: walletCount == 0 ? "cartões, passes e documentos" : items,
                          tone: .ink)
    }

    /// "Hoje · 2" · "aula 10:00 · Udatsu 19:00". `items` = (nome curto, hora) já ordenados.
    static func todayCard(_ items: [(name: String, at: String)]) -> AtalhoCard {
        let detail = items.isEmpty ? "nada marcado hoje · ver próximos" : items.map { "\($0.name) \($0.at)" }.joined(separator: " · ")
        return AtalhoCard(kind: .today, label: "Hoje · \(items.count)", title: "Ingressos\ne reservas", detail: detail, tone: .orange)
    }

    /// "Offline · baixado" · "Tóquio 23 bairros · 184 MB". Sem pacote baixado: "Offline · não baixado".
    static func mapCard(title: String?, bytes: Int64?, installed: Bool) -> AtalhoCard {
        guard let title else { return AtalhoCard(kind: .map, label: "Mapa", title: "Mapa", detail: "sem mapa offline aqui", tone: .white) }
        let size = bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return AtalhoCard(kind: .map, label: installed ? "Offline · baixado" : "Offline · não baixado", title: "Mapa",
                          detail: installed ? [title, size].compactMap { $0 }.joined(separator: " · ") : "baixar \(title)\(size.map { " · \($0)" } ?? "")",
                          tone: .white)
    }

    /// Os números do país (o kit completo é do SOS).
    static func sosCard(region: Region) -> AtalhoCard {
        let numbers = switch region {
        case .jp: "119 · 110 · seguro · hospital"
        case .bh: "192 · 190 · 193 · seguro"
        case .it: "112 · seguro · hospital"
        }
        return AtalhoCard(kind: .sos, label: "Emergência", title: "SOS", detail: numbers, tone: .alert)
    }

    /// Dynamic Type grande (a partir de xxxLarge): uma coluna.
    static func columns(for size: DynamicTypeSize) -> Int { size >= .xxxLarge ? 1 : 2 }

    // MARK: Linhas perto

    /// Até onde uma estação conta como "perto" (a pé).
    static let stationMeters: CLLocationDistance = 1_500

    /// Estação mais perto de `here` (na tabela de linhas da região) e as linhas que param nela (mesmo nome, até 400 m).
    /// O nome vai sempre em letras latinas: o bairro da tabela (Shinjuku), senão o nome da estação quando já é latino.
    static func lines(near here: CLLocationCoordinate2D, transit: TransitMap, areas: [Area], region: Region) -> AtalhoLines? {
        let spot = CLLocation(latitude: here.latitude, longitude: here.longitude)
        func meters(_ c: CLLocationCoordinate2D) -> CLLocationDistance { CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: spot) }
        guard let nearest = transit.stations.min(by: { meters($0.coordinate) < meters($1.coordinate) }) else { return nil }
        let distance = meters(nearest.coordinate)
        guard distance <= stationMeters else { return nil }
        let base = CLLocation(latitude: nearest.coordinate.latitude, longitude: nearest.coordinate.longitude)
        let cluster = transit.stations.filter {
            $0.name == nearest.name && CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: base) < 400
        }
        var ids: [String] = []
        for id in cluster.flatMap(\.lines) where !ids.contains(id) { ids.append(id) }
        // O bairro da tabela sabe as outras linhas da mesma estação ("jc-shinjuku", "f-shinjuku"): entram também.
        if let area = nearestArea(to: nearest.coordinate, areas: areas) {
            for prefix in area.stationIds.compactMap({ $0.split(separator: "-").first.map(String.init) }) {
                if let line = transit.lines.first(where: { $0.id.lowercased() == prefix.lowercased() }), !ids.contains(line.id) { ids.append(line.id) }
            }
        }
        let lines = ids.compactMap { id -> AtalhoLine? in
            guard let line = transit.line(id) else { return nil }
            return AtalhoLine(code: chipCode(line.id), name: shortName(line, region: region), rgb: rgb(line.color))
        }
        guard !lines.isEmpty else { return nil }
        return AtalhoLines(station: latinName(nearest, areas: areas) ?? "Estação", walkMinutes: Walk.minutes(distance * 1.25),
                           lines: lines, note: nil)
    }

    /// "JR Yamanote" → "Yamanote"; "Metrô BH · Linha 1" → "Linha 1"; "Metro A · Battistini → Anagnina" → "Metro A".
    static func shortName(_ line: TransitLine, region: Region) -> String {
        var name = line.nameLatin.isEmpty ? line.name : line.nameLatin
        if name.hasPrefix("JR ") { name.removeFirst(3) }
        if let dot = name.range(of: " · ") {
            let head = String(name[..<dot.lowerBound]), tail = String(name[dot.upperBound...])
            name = region == .bh ? tail : head
        }
        return name
    }

    /// Código do chip: "JY", "M", "E"; ids compridos ("T-Kyoto") ficam com o começo.
    static func chipCode(_ id: String) -> String {
        let head = id.split(separator: "-").first.map(String.init) ?? id
        return String(head.prefix(3)).uppercased()
    }

    static func rgb(_ color: Color) -> UInt32 {
        let c = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    }

    /// Bairro da tabela a até 1 km da estação (o nome latino), senão o nome da estação se já for latino; kanji nunca.
    static func nearestArea(to c: CLLocationCoordinate2D, areas: [Area]) -> Area? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return areas.map { ($0, CLLocation(latitude: $0.centroid.lat, longitude: $0.centroid.lng).distance(from: here)) }
            .filter { $0.1 <= 1_000 }
            .min { $0.1 < $1.1 }?.0
    }

    static func latinName(_ station: TransitStation, areas: [Area]) -> String? {
        if let area = nearestArea(to: station.coordinate, areas: areas) { return area.name }
        let latin = station.name.unicodeScalars.allSatisfy { $0.isASCII || CharacterSet.letters.contains($0) && $0.value < 0x0250 }
        return latin && !station.name.isEmpty ? station.name : nil
    }

    /// "último Yamanote 00:40 · saia às 14:27 pro Gyoen".
    static func note(lastTrain: LastTrain?, leaveAt: String?, next: String?) -> String? {
        var parts: [String] = []
        if let lastTrain {
            let label = lastTrain.label.replacingOccurrences(of: "Último ", with: "último ")
                .replacingOccurrences(of: "Metrô até", with: "último metrô")
            parts.append("\(label.components(separatedBy: " → ").first ?? label) \(lastTrain.time)")
        }
        if let leaveAt, let next { parts.append("saia às \(leaveAt) pro \(next)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Indicados por perto

    /// Os 3 melhores de fora do board no cache do "Por perto" (sem Wikipedia sozinha, que é contexto), com o motivo.
    static func picks(_ ranked: [NearbyScored], limit: Int = 3) -> [AtalhoPick] {
        ranked.filter { !$0.candidate.isOnBoard && !$0.candidate.isContextOnly }
            .prefix(limit)
            .map { item in
                let c = item.candidate
                return AtalhoPick(id: c.id, name: c.place.name, reason: reason(c))
            }
    }

    /// "ramen · 4,4 · 620 m · em alta agora".
    static func reason(_ c: NearbyCandidate) -> String {
        var parts: [String] = []
        if let label = NearbyRanker.categoryLabel(c.place) { parts.append(label) }
        if let rating = c.place.rating { parts.append(rating.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(1)))) }
        parts.append(Walk.distanceText(c.distance))
        if (c.place.popularity ?? 0) > 0.9 { parts.append("em alta agora") }
        else if let summary = c.place.summary, !summary.isEmpty { parts.append(summary) }
        else if c.place.openNow == true { parts.append("aberto agora") }
        return parts.joined(separator: " · ")
    }

    /// O último "Por perto" do aparelho pra esta célula (ou uma vizinha), mesmo passado dos 30 min do Descobrir — até 12 h.
    /// Lê o arquivo direto (o `NearbyCache` só devolve o fresco); nunca chama fonte nenhuma.
    static let pickMaxAge: TimeInterval = 12 * 3600

    static func cachedBatch(lat: Double, lng: Double, region: Region, now: Date,
                            directory: URL = URL.cachesDirectory.appending(path: "must-nearby", directoryHint: .isDirectory)) -> NearbyBatch? {
        let step = 0.0045
        var best: NearbyBatch?
        for dLat in [0.0, step, -step] {
            for dLng in [0.0, step, -step] {
                let cell = NearbyCell.key(lat: lat + dLat, lng: lng + dLng, region: region)
                guard let data = try? Data(contentsOf: directory.appending(path: "\(cell).json")),
                      let batch = try? JSONDecoder.tips.decode(NearbyBatch.self, from: data) else { continue }
                let age = now.timeIntervalSince(batch.fetchedAt)
                guard age >= -60, age < pickMaxAge else { continue }
                if dLat == 0, dLng == 0 { return batch }
                if best == nil || batch.fetchedAt > best!.fetchedAt { best = batch }
            }
        }
        return best
    }
}
