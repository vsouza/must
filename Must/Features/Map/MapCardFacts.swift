import CoreLocation
import Foundation

/// Foto do card do pino (prompt 27 §2.a): a de sempre do `PlacePhotoStore`, com crédito. **Nunca baixa foto nova só por
/// causa do card em dado móvel** (nem no Modo de Pouco Dados, nem offline): usa a que estiver no disco (inteira, senão a
/// miniatura) e, sem nada, o placeholder de cor. Só no Wi-Fi bom pede a `/media` (uma vez; depois fica no disco).
enum MapCardPhoto {
    enum Source: Equatable {
        /// Arquivo já no aparelho (0 KB).
        case disk(URL)
        /// Wi-Fi: pode buscar a foto principal; `placeholder` = a miniatura do disco enquanto isso.
        case fetch(placeholder: URL?)
        /// Nada no disco e rede que não deixa: placeholder de cor.
        case none
    }

    static func source(refs: [PlacePhotoRef], network: PrefetchPolicy.Network,
                       full: (PlacePhotoRef) -> URL? = PlacePhotoStore.existing,
                       thumb: (PlacePhotoRef) -> URL? = PlacePhotoStore.existingThumb) -> Source {
        guard let first = refs.first else { return .none }
        if let url = full(first) { return .disk(url) }
        let small = thumb(first)
        if PrefetchPolicy.allows(network) { return .fetch(placeholder: small) }
        return small.map(Source.disk) ?? .none
    }

    /// "GOOGLE · KENJI S." (o autor da foto do Places).
    static func credit(_ ref: PlacePhotoRef?) -> String? {
        guard let ref else { return nil }
        return ["Google", ref.author.map { String($0.prefix(22)) }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Textos do card do pino (puros, testados). A ficha vem do `PlaceFicha` (o mesmo do Lugar), cortada em 3 campos.
@MainActor
enum MapCardFacts {
    /// "Must eat · tsukemen · 4,4 ★ · 3,1 mil" (a nota só se já estiver no aparelho).
    static func meta(_ place: Place, rating: KnownRating?, locale: Locale) -> String {
        var parts: [String] = [place.list?.displayName ?? "Must"]
        if let sub = place.sub?.trimmingCharacters(in: .whitespaces), !sub.isEmpty { parts.append(sub.lowercased()) }
        if let rating {
            parts.append("\(rating.rating.formatted(.number.precision(.fractionLength(1)).locale(locale))) ★")
            if let count = rating.count, count > 0 { parts.append(compact(count, locale: locale)) }
        }
        return parts.joined(separator: " · ")
    }

    /// 3.100 → "3,1 mil"; 980 → "980".
    nonisolated static func compact(_ n: Int, locale: Locale) -> String {
        guard n >= 1000 else { return "\(n)" }
        let k = Double(n) / 1000
        return "\(k.formatted(.number.precision(.fractionLength(k < 10 ? 1 : 0)).locale(locale))) mil"
    }

    /// Fila, preço e distância (`MapaPino.png`); o que faltar vem do horário e do pagamento. Sempre 3.
    static func cells(_ place: Place, region: Region, now: Date, here: CLLocation?, walkMaxKm: Double) -> [PlaceFicha.Cell] {
        let all = PlaceFicha.cells(place, region: region, now: now, here: here, walkMaxKm: walkMaxKm, queueFirst: true)
        var picked: [PlaceFicha.Cell] = []
        for label in ["fila agora", "preço", "distância", "horário", "pagamento"] where picked.count < 3 {
            if let cell = all.first(where: { $0.label == label }) { picked.append(cell) }
        }
        // A distância fica sempre (é o que o card responde: dá pra ir a pé?).
        if !picked.contains(where: { $0.label == "distância" }), let d = all.first(where: { $0.label == "distância" }) {
            picked[picked.count - 1] = d
        }
        return picked
    }

    /// "Ana e Pedro foram · “tsukemen frio, com ovo”" — no máximo 2 nomes; `nil` sem amigos.
    nonisolated static func friendsLine(_ visits: [FriendVisit]) -> String? {
        let two = Array(visits.prefix(2))
        guard let first = two.first else { return nil }
        let names = two.count == 2 ? "\(first.name) e \(two[1].name)" : first.name
        let verb = two.count == 2 ? "foram" : "foi"
        guard let note = two.lazy.compactMap(\.note).first(where: { !$0.isEmpty }) else { return "\(names) \(verb) · \(first.when)" }
        return "\(names) \(verb) · “\(note)”"
    }

    /// "SHINJUKU · AGORA" / "PINO 2 DE 9 · HOJE" (canto de cima, com o card aberto).
    nonisolated static func spec(area: String, pin: (number: Int, total: Int, day: String)?, list: String?) -> [String] {
        var lines = ["\(area) · agora"]
        if let pin { lines.append("pino \(pin.number) de \(pin.total) · \(pin.day)") } else if let list { lines.append("\(list) · sem plano") }
        return lines
    }
}
