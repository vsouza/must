import SwiftUI

/// Bairros (rota `.bairros`, atalho `must://bairros`): na V9 é a mesma lista de bairros do Guia (`BairrosV9View`), com o bairro
/// pedido já aberto. O mapa de bolhas do v8 saiu: o mapa de verdade é o Explorar, e a lista tem controle visível pra tudo.
/// `BairrosModel` (geometria e bolhas) continua pros testes e pro Guia do dia.
struct BairrosView: View {
    /// Bairro que abre já escolhido (`-debugScreen bairros:<id>` e atalhos).
    var initialArea: String?

    var body: some View {
        BairrosV9View(initialArea: initialArea)
    }
}
