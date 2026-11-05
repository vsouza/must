import SwiftUI

/// Em cartaz (`EmCartaz.png`). Stub do contrato; agente B.
struct EmCartazView: View {
    var body: some View {
        Text("Em cartaz").font(V8Font.display(34)).foregroundStyle(V8.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(V8.paper.ignoresSafeArea())
    }
}
