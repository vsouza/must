import CoreLocation
import Foundation

/// O que o usuário guarda pro SOS (prompt 25 · C.1): seguro e, opcionais, tipo sanguíneo e alergias.
/// **Só no aparelho**: um arquivo em Application Support com `isExcludedFromBackup` e proteção completa —
/// nunca no App Group (widgets), no iCloud, no backup do iPhone nem no export `.json` do board.
struct SOSProfile: Codable, Hashable, Sendable {
    /// Seguradora ("Assist Card"); no Brasil, o plano de saúde.
    var insurer: String = ""
    var policy: String = ""
    /// Telefone 24 h da assistência, como o usuário escreveu ("+55 11 3003-…").
    var phone24h: String = ""
    var instructions: String = ""
    var bloodType: String = ""
    var allergies: String = ""

    static let defaultInstructions = "ligue antes do hospital · peça recibo e diagnóstico em inglês"

    var isEmpty: Bool { insurer.isEmpty && policy.isEmpty && phone24h.isEmpty }
    var hasHealth: Bool { !bloodType.isEmpty || !allergies.isEmpty }
    var phoneURL: URL? { EmergencyKit.telURL(phone24h) }
}

/// Último endereço conhecido (pro "Onde estou" sem rede): no idioma local e em letras latinas.
struct LastAddress: Codable, Hashable, Sendable {
    /// "東京都新宿区歌舞伎町1-3-9" (Japão), "Via della Lungara 10, Roma" (Itália), o mesmo do latino no Brasil.
    var local: String
    /// "Kabukichō 1-3-9, Shinjuku".
    var latin: String
    var lat: Double
    var lng: Double
    var at: Date
    /// País (ISO) de onde foi lido: endereço do Japão não aparece no SOS da Itália.
    var country: String

    var location: CLLocation { CLLocation(latitude: lat, longitude: lng) }
}

/// Os dois arquivos do SOS em `Application Support/sos/`, fora do backup. Leitura síncrona e pequena (< 2 KB).
struct SOSStore: Sendable {
    var directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "sos", directoryHint: .isDirectory)
    }

    private var profileURL: URL { directory.appending(path: "profile.json") }
    private var addressURL: URL { directory.appending(path: "last-address.json") }

    func profile() -> SOSProfile {
        guard let data = try? Data(contentsOf: profileURL) else { return SOSProfile() }
        return (try? JSONDecoder().decode(SOSProfile.self, from: data)) ?? SOSProfile()
    }

    func save(_ profile: SOSProfile) throws {
        try write(JSONEncoder().encode(profile), to: profileURL)
    }

    func lastAddress(country: String) -> LastAddress? {
        guard let data = try? Data(contentsOf: addressURL),
              let address = try? JSONDecoder().decode(LastAddress.self, from: data), address.country == country
        else { return nil }
        return address
    }

    func save(_ address: LastAddress) throws {
        try write(JSONEncoder().encode(address), to: addressURL)
    }

    /// Grava com proteção completa e marca a pasta e o arquivo como fora do backup.
    private func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.excludeFromBackup(directory)
        try Self.excludeFromBackup(url)
    }

    static func excludeFromBackup(_ url: URL) throws {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try u.setResourceValues(values)
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }

    var profileFile: URL { profileURL }
}
