import Foundation

/// Campos úteis de um `.pkpass` (`pass.json`), lidos sem checar assinatura: só a leitura importa (prompt 15 · A).
struct PassInfo: Equatable, Sendable {
    var organization: String?
    var description: String?
    var relevantDate: Date?
    /// `relevantText` das localizações (ponto de encontro, estação).
    var locationTexts: [String]
    /// Payload do QR/código de barras do passe.
    var barcode: String?
    /// "PKBarcodeFormatQR", "PKBarcodeFormatPDF417"…
    var barcodeFormat: String?
    /// Campos (primary, secondary, auxiliary) como "rótulo: valor".
    var fields: [String]
}

enum PKPassReader {
    /// `pass.json` de um `.pkpass` (zip). Nil se o zip não tem `pass.json`.
    static func read(_ pkpass: Data) throws -> PassInfo? {
        guard let json = try ZipReader.file(named: "pass.json", in: pkpass) else { return nil }
        return try parse(passJSON: json)
    }

    static func parse(passJSON: Data) throws -> PassInfo {
        guard let root = try JSONSerialization.jsonObject(with: passJSON) as? [String: Any] else {
            throw TicketReaderError.unreadablePass
        }
        let barcodes = (root["barcodes"] as? [[String: Any]]) ?? (root["barcode"] as? [String: Any]).map { [$0] } ?? []
        let first = barcodes.first
        let locations = (root["locations"] as? [[String: Any]] ?? []).compactMap { $0["relevantText"] as? String }
        let structure = root["eventTicket"] as? [String: Any] ?? root["boardingPass"] as? [String: Any]
            ?? root["generic"] as? [String: Any] ?? root["coupon"] as? [String: Any] ?? root["storeCard"] as? [String: Any] ?? [:]
        let fieldKeys = ["headerFields", "primaryFields", "secondaryFields", "auxiliaryFields"]
        let fields: [String] = fieldKeys.flatMap { key in
            (structure[key] as? [[String: Any]] ?? []).compactMap { field -> String? in
                guard let value = field["value"] as? String ?? (field["value"] as? NSNumber)?.stringValue, !value.isEmpty else { return nil }
                let label = field["label"] as? String
                return [label, value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ")
            }
        }
        return PassInfo(
            organization: root["organizationName"] as? String,
            description: root["description"] as? String,
            relevantDate: (root["relevantDate"] as? String).flatMap(isoDate),
            locationTexts: locations,
            barcode: first?["message"] as? String,
            barcodeFormat: first?["format"] as? String,
            fields: fields
        )
    }

    /// Passe usa ISO 8601 com ou sem fração de segundo.
    private static func isoDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
