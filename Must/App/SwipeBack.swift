import UIKit

/// Voltar deslizando (pedido do Vinicius, 05/11/2026): as telas escondem a barra de navegação (design v8), e com
/// ela escondida o UIKit desliga o gesto de voltar. Aqui ele volta: da borda (o clássico) e, no iOS 26, puxando a
/// tela de qualquer ponto. Só quando há pra onde voltar — na raiz de cada aba o gesto não começa (a capa usa os
/// próprios deslizes).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactiveContentPopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && transitionCoordinator == nil
    }
}
