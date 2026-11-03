import SwiftUI

/// Leva a direção do aparelho pro cone do "você" no MapLibre (prompt 18 · A.2).
///
/// A bússola muda várias vezes por segundo. Se o `body` do mapa lesse esse valor, o mapa inteiro (pinos, rotas,
/// `scene`) seria recalculado a cada giro. Por isso ela passa por um view minúsculo (`CompassBridge`) que é o único
/// a ser redesenhado, e que entrega o valor pra um `YouHeadingSink` que o coordenador do mapa ouve.
@MainActor
final class YouHeadingSink {
    /// Último heading recebido (graus, norte = 0).
    private(set) var heading: Double?
    /// Quem gira o cone. Ao ligar, recebe o último valor já conhecido.
    var onChange: ((Double?) -> Void)? {
        didSet { onChange?(heading) }
    }

    func update(_ value: Double?) {
        heading = value
        onChange?(value)
    }
}

/// View invisível que lê `compass.heading`. Só ela é invalidada pela bússola.
struct CompassBridge: View {
    let compass: Compass
    let sink: YouHeadingSink

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear { sink.update(compass.heading) }
            .onChange(of: compass.heading) { _, value in sink.update(value) }
            .accessibilityHidden(true)
    }
}
