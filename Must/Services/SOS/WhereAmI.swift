import CoreLocation
import Foundation

/// "Onde estou" do SOS (prompt 25 · C.2): o endereço atual no idioma local (japonês, italiano, português) pra mostrar
/// ao taxista ou ler em voz alta. Com rede, o geocoder reverso da Apple (uma vez por ~150 m / 10 min, só com o SOS
/// aberto); sem rede, o último endereço conhecido — e, sempre, a coordenada do GPS (que funciona offline).
enum WhereAmI {
    /// Distância e idade a partir das quais o endereço guardado deixa de valer.
    static let refreshMeters: CLLocationDistance = 150
    static let refreshAge: TimeInterval = 10 * 60

    /// Locale do endereço local de cada país.
    static func localLocale(_ region: Region) -> Locale {
        switch region {
        case .jp: Locale(identifier: "ja_JP")
        case .it: Locale(identifier: "it_IT")
        case .bh: Locale(identifier: "pt_BR")
        }
    }

    /// Precisa pedir de novo? (sem endereço, longe ou velho).
    static func needsRefresh(_ last: LastAddress?, location: CLLocation, now: Date) -> Bool {
        guard let last else { return true }
        return last.location.distance(from: location) > refreshMeters || now.timeIntervalSince(last.at) > refreshAge
    }

    /// O que a tela mostra: endereço quando há (marcado "último conhecido" se longe/velho), senão a coordenada.
    struct Display: Equatable {
        var main: String
        var sub: String
        var isStale: Bool
    }

    static func display(_ last: LastAddress?, location: CLLocation?, now: Date) -> Display? {
        if let last {
            let stale = location.map { needsRefresh(last, location: $0, now: now) } ?? (now.timeIntervalSince(last.at) > refreshAge)
            return Display(main: last.local, sub: last.latin == last.local ? "" : last.latin, isStale: stale)
        }
        guard let location else { return nil }
        return Display(main: coordinateText(location.coordinate), sub: "coordenada do GPS · sem endereço ainda", isStale: false)
    }

    static func coordinateText(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    /// Junta partes repetidas: "歌舞伎町" seguido de "歌舞伎町1丁目" vira só o segundo; parte já contida na anterior sai.
    private static func merge(_ acc: inout [String], _ part: String) {
        guard let last = acc.last else { acc.append(part); return }
        if part.contains(last) { acc[acc.count - 1] = part } else if !last.contains(part) { acc.append(part) }
    }

    /// Endereço numa linha a partir das partes. Japão: do maior pro menor, sem espaço (都道府県 → 番地); resto: rua e
    /// número, bairro, cidade.
    static func line(_ parts: AddressParts, japaneseOrder: Bool) -> String {
        if japaneseOrder {
            return [parts.administrativeArea, parts.locality, parts.subLocality, parts.thoroughfare, parts.subThoroughfare]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .reduce(into: [String](), merge)
                .joined()
        }
        let street = [parts.thoroughfare, parts.subThoroughfare].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return [street.isEmpty ? parts.name : street, parts.subLocality, parts.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { acc, p in if !acc.contains(p) { acc.append(p) } }
            .joined(separator: " · ")
    }
}

/// Partes do endereço (do `CLPlacemark`, trocável nos testes).
struct AddressParts: Sendable, Equatable {
    var name: String?
    var thoroughfare: String?
    var subThoroughfare: String?
    var subLocality: String?
    var locality: String?
    var administrativeArea: String?

    init(name: String? = nil, thoroughfare: String? = nil, subThoroughfare: String? = nil, subLocality: String? = nil,
         locality: String? = nil, administrativeArea: String? = nil) {
        self.name = name
        self.thoroughfare = thoroughfare
        self.subThoroughfare = subThoroughfare
        self.subLocality = subLocality
        self.locality = locality
        self.administrativeArea = administrativeArea
    }

    init(_ p: CLPlacemark) {
        self.init(name: p.name, thoroughfare: p.thoroughfare, subThoroughfare: p.subThoroughfare, subLocality: p.subLocality,
                  locality: p.locality, administrativeArea: p.administrativeArea)
    }
}

/// Geocoder reverso (no real, o `CLGeocoder` da Apple — rede, mas não é API nova nem tem chave).
protocol AddressGeocoding: Sendable {
    func parts(at location: CLLocation, locale: Locale) async throws -> AddressParts?
}

struct CLAddressGeocoder: AddressGeocoding {
    func parts(at location: CLLocation, locale: Locale) async throws -> AddressParts? {
        try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: locale).first.map(AddressParts.init)
    }
}

extension WhereAmI {
    /// Pede o endereço local e o latino (duas chamadas em sequência, nunca em paralelo) e grava. Erro/sem resultado: `nil`.
    static func lookup(_ location: CLLocation, region: Region, geocoder: any AddressGeocoding = CLAddressGeocoder(),
                       now: Date = AppClock.now) async -> LastAddress? {
        do {
            guard let local = try await geocoder.parts(at: location, locale: localLocale(region)) else { return nil }
            let localLine = line(local, japaneseOrder: region == .jp)
            var latinLine = localLine
            if region != .bh, let latin = try? await geocoder.parts(at: location, locale: Locale(identifier: "pt_BR")) {
                latinLine = line(latin, japaneseOrder: false)
            }
            guard !localLine.isEmpty else { return nil }
            return LastAddress(local: localLine, latin: latinLine.isEmpty ? localLine : latinLine,
                               lat: location.coordinate.latitude, lng: location.coordinate.longitude, at: now, country: region.country)
        } catch {
            Log.app.info("onde estou: geocoder falhou (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }
}
