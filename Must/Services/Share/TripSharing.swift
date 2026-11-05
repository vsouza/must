import Foundation

/// Viajar junto (prompt 25 · B.4): board e dias compartilhados por CloudKit (`CKShare`), sem servidor próprio.
/// O time de assinatura é *Personal Team* (`BS5ZUHVH99`), que não tem iCloud/CloudKit: acrescentar o entitlement
/// quebraria a assinatura. Fica a interface, e a tela mostra a opção desabilitada.
/// TODO(p25:2): com conta de desenvolvedor paga, `CloudKitTripSharing` (zona compartilhada com board e dias; última
/// escrita vence por campo; feito/não feito por pessoa) e o entitlement `com.apple.developer.icloud-services`.
protocol TripSharing: Sendable {
    /// Dá pra compartilhar neste aparelho/assinatura?
    var isAvailable: Bool { get }
    /// Por que não (a linha da tela quando `isAvailable` é falso).
    var unavailableReason: String? { get }
    /// Cria (ou reabre) o compartilhamento e devolve o link de convite.
    func invite() async throws -> URL
}

/// O que existe hoje: nada de CloudKit.
struct UnavailableTripSharing: TripSharing {
    enum Failure: Error { case needsPaidAccount }

    var isAvailable: Bool { false }
    var unavailableReason: String? { "precisa de conta de desenvolvedor paga" }
    func invite() async throws -> URL { throw Failure.needsPaidAccount }
}
