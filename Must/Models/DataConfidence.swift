import Foundation

// Confiança do dado (relatório do viajante, problema 3): o app só afirma o que sabe. "Aberto agora" e "não dá hoje" vêm de
// horário confirmado (Google); coordenada `approx` é chute. Tudo o mais é "estimado", e a tela diz.

/// O que um lugar sabe de si: o horário e a coordenada vêm do Google (confirmados) ou do seed (estimados).
struct PlaceTrust: Equatable, Sendable {
    var hoursConfirmed: Bool
    var coordConfirmed: Bool

    static let hoursEstimated = "horário estimado"
    static let coordApproximate = "local aproximado"
    /// O que "aberto agora" vira sem horário confirmado.
    static let hoursUnconfirmed = "horário não confirmado"

    var isConfirmed: Bool { hoursConfirmed && coordConfirmed }

    /// Micro-rótulo mono do índice e do Lugar: "horário estimado" / "local aproximado" / os dois / `nil` (tudo confirmado).
    var microLabel: String? {
        let parts = [hoursConfirmed ? nil : Self.hoursEstimated, coordConfirmed ? nil : Self.coordApproximate].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Place {
    /// Horário com períodos (cache do Google) e coordenada resolvida (`approx` falso).
    var trust: PlaceTrust { PlaceTrust(hoursConfirmed: hours?.hasPeriods == true, coordConfirmed: !approx) }
}

/// "105 lugares · 94 confirmados": quantos do board têm horário e coordenada de verdade.
struct BoardConfidence: Equatable, Sendable {
    var total: Int
    var confirmed: Int

    init(total: Int, confirmed: Int) {
        self.total = total
        self.confirmed = min(confirmed, total)
    }

    init(_ places: [Place]) {
        self.init(total: places.count, confirmed: places.filter { $0.trust.isConfirmed }.count)
    }

    var pending: Int { total - confirmed }
    var isComplete: Bool { pending == 0 }

    /// "105 lugares · 94 confirmados".
    var headline: String {
        "\(total) \(total == 1 ? "lugar" : "lugares") · \(confirmed) \(confirmed == 1 ? "confirmado" : "confirmados")"
    }

    /// Linha de baixo: o que falta e quando resolver (sem gastar o celular).
    func detail(onWiFi: Bool) -> String {
        if total == 0 { return "nada no board ainda" }
        if isComplete { return "tudo confirmado no Google" }
        return onWiFi ? "toque pra sincronizar os \(pending) que faltam" : "sincronizar no Wi-Fi · faltam \(pending)"
    }
}
