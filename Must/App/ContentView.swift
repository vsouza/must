import SwiftData
import SwiftUI

/// Tela provisória (até o prompt 04 trazer a RootView com a tab bar):
/// mostra a região, as listas carregadas e dá acesso a Ajustes.
/// Em DEBUG, toque longo no 済 abre a Gallery.
struct ContentView: View {
    var lastOpenedURL: URL?

    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]

    @State private var showGallery = false
    @State private var path: [Route] = []

    private enum Route: Hashable { case settings }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.must.bg.ignoresSafeArea()
                BlobBackground(style: .home)

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        KanjiSeal(done: true, size: 36)
                            .onLongPressGesture(minimumDuration: 0.6) { openGallery() }
                        Spacer()
                        IconButton(.ajustes, label: "Ajustes") { path.append(.settings) }
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Olá, Vinicius!").mustTitle()
                        Text("\(store.region.displayName) · \(places.count) lugares em \(lists.count) listas")
                            .mustSerif(18)
                            .foregroundStyle(Color.must.secondary)
                    }

                    VStack(spacing: 8) {
                        ForEach(lists) { list in
                            HStack(spacing: 12) {
                                MustIconView(list.icon, size: 18)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.white.opacity(0.55)))
                                Text(list.displayName).font(.must.archivo(17, .semibold))
                                Spacer()
                                if let kanji = list.kanji { Text(kanji).font(.must.kanji(20)).opacity(0.35) }
                                MonoNumber("\(list.places.count)", size: 22)
                            }
                            .foregroundStyle(list.color.text)
                            .padding(.horizontal, 14)
                            .frame(height: 56)
                            .background(list.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(.top, 8)

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        Micro(statusLine)
                        if let lastOpenedURL {
                            Text(lastOpenedURL.absoluteString).mustMono(12).foregroundStyle(Color.must.secondary).lineLimit(2)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 22)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings: SettingsView()
                }
            }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showGallery) { Gallery() }
        .onAppear(perform: applyDebugLaunch)
        #endif
    }

    private var statusLine: String {
        let missing = MustFontFamily.missing
        let fonts = missing.isEmpty ? "fontes ok" : "faltando: \(missing.joined(separator: ", "))"
        let gps: String
        if let c = services.location.current?.coordinate {
            gps = String(format: "%@%.4f, %.4f", services.location.isSimulating ? "sim " : "", c.latitude, c.longitude)
        } else {
            gps = "sem gps"
        }
        return "\(fonts) · \(gps) · \(store.region.timeString(AppClock.now))"
    }

    private func openGallery() {
        #if DEBUG
        showGallery = true
        #endif
    }

    #if DEBUG
    /// `-gallery` abre a Gallery; `-debugScreen ajustes|regiao` abre Ajustes direto (simulador).
    private func applyDebugLaunch() {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-gallery") { showGallery = true }
        if let screen = defaults.string(forKey: "debugScreen"), ["ajustes", "regiao"].contains(screen), path.isEmpty {
            path = [.settings]
        }
    }
    #endif
}
