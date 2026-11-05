import SwiftUI

/// Filmes gravados no lugar/bairro (`Filmes.png`, `FilmesVazio.png`). Stub do contrato; agente B.
struct FilmsView: View {
    var placeId: String
    var body: some View {
        Text("Filmes").font(V8Font.display(34)).foregroundStyle(V8.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(V8.paper.ignoresSafeArea())
    }
}
