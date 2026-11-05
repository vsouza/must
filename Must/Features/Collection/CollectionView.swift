import SwiftUI

/// Coleção (`Colecao.png`). Stub do contrato; agente D.
struct CollectionView: View {
    var body: some View {
        Text("Coleção").font(V8Font.display(34)).foregroundStyle(V8.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(V8.paper.ignoresSafeArea())
    }
}
