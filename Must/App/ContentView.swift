import SwiftUI

/// Tela provisória: valida as fontes. Em DEBUG, toque longo no 済 abre a Gallery.
struct ContentView: View {
    var lastOpenedURL: URL?
    @State private var showGallery = false

    var body: some View {
        ZStack {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .home)

            VStack(spacing: 20) {
                KanjiSeal(done: true, size: 72)
                    .onLongPressGesture(minimumDuration: 0.6) { openGallery() }

                Text("Must").mustTitle()

                Text("o board vira o dia")
                    .mustSerif(19)
                    .foregroundStyle(Color.must.secondary)

                Text("09:30 · R$ 200 · ¥ 15.000").mustMono(13)

                fontStatus
            }
            .padding(.horizontal, 22)
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showGallery) { Gallery() }
        .onAppear {
            // `-gallery` como argumento de lançamento abre direto (útil no simulador).
            if ProcessInfo.processInfo.arguments.contains("-gallery") { showGallery = true }
        }
        #endif
    }

    private func openGallery() {
        #if DEBUG
        showGallery = true
        #endif
    }

    @ViewBuilder private var fontStatus: some View {
        let missing = MustFontFamily.missing
        Micro(missing.isEmpty ? "fontes ok" : "faltando: \(missing.joined(separator: ", "))",
              color: missing.isEmpty ? Color.must.secondary : .red)
            .padding(.top, 24)

        if let lastOpenedURL {
            Text(lastOpenedURL.absoluteString)
                .mustMono(13)
                .foregroundStyle(Color.must.secondary)
                .lineLimit(2)
        }
    }
}

#Preview {
    ContentView()
}
