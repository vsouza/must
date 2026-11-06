import SwiftData
import SwiftUI
import UIKit

/// Cor do card "da viagem": a cor do lugar da região (capa); sem viagem, laranja.
enum CollectibleTint {
    static func color(_ region: Region) -> Color {
        let theme = TripTheme.forRegion(region)
        return theme.hasTrip ? theme.cover : V8.orange
    }
}

/// Estado do momento "novo colecionável" e do card grande: renderiza o PNG uma vez por formato e entrega ao ShareLink.
@MainActor @Observable
final class CollectibleShareModel {
    var format: CollectibleFormat = .stories
    private(set) var url: URL?
    private var rendered: URL?

    func render(_ item: Collectible, tint: Color) async {
        CollectibleRenderer.cleanup(rendered)
        url = nil
        await Task.yield()
        let made = CollectibleRenderer.write(item, format: format, tint: tint)
        rendered = made
        url = made
    }

    func cleanup() { CollectibleRenderer.cleanup(rendered); rendered = nil; url = nil }
}

/// "Mandar": o share sheet do sistema (Instagram, Facebook, WhatsApp, Mensagens, Fotos) com o PNG. Sem SDK.
struct CollectibleSendButton: View {
    var model: CollectibleShareModel
    var item: Collectible

    var body: some View {
        if let url = model.url {
            ShareLink(item: url, preview: SharePreview(CollectibleRenderer.fileName(item, format: model.format), image: Image(uiImage: UIImage(contentsOfFile: url.path) ?? UIImage()))) {
                V8ButtonFace("Mandar", .orange, icon: .compartilhar)
            }
            .buttonStyle(MustPressStyle())
        } else {
            V8ButtonFace("Mandar", .orange, icon: .compartilhar).opacity(0.5)
        }
    }
}

// MARK: - O momento (`ColecionavelNovo.png`)

/// Tela cheia em tinta ao marcar "Feito": o card gira −4° e sobe com mola (1,8 s) + haptic. Reduzir movimento: só fade.
struct CollectibleMomentView: View {
    var item: Collectible
    var regionName: String
    var money: String?
    var tint: Color
    var onSeeCollection: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var model = CollectibleShareModel()

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.56, 300)
            ZStack(alignment: .topLeading) {
                V8.ink
                Rings(color: V8.white, count: 1, diameter: 560, opacity: 0.2, offset: CGSize(width: -40, height: -190))
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            SpecLabel("Feito · \(CollectibleText.dateLabel(item.doneAt, timeZoneId: item.timeZoneId, withYear: false))\n\(item.area.map(CollectibleText.latinOnly) ?? item.cityName)", color: V8.muteDark)
                            Spacer(minLength: 12)
                            SpecLabel("\(CollectibleText.latinOnly(item.title))\(money.map { "\n\($0) registrado" } ?? "")", color: V8.muteDark)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.top, 14)
                        Text("Novo na coleção".uppercased())
                            .font(V8Font.mono(13, weight: .semibold)).tracking(1.6)
                            .foregroundStyle(V8.orange).padding(.top, 34)
                        Text("Mais um feito.")
                            .font(V8Font.display(52)).tracking(-1.6)
                            .foregroundStyle(V8.white)
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                        Text("nº \(item.order) de \(item.total) · \(item.cityName) · \(item.doneCount) \(regionName)")
                            .font(V8Font.text(17)).foregroundStyle(V8.muteDark).padding(.top, 8)
                        ScaledCollectibleCard(item: item, tint: tint, width: cardWidth, corner: 40)
                            .rotationEffect(.degrees(shown || reduceMotion ? -4 : 0))
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                            .offset(y: shown || reduceMotion ? 0 : 160)
                            .opacity(shown || !reduceMotion ? 1 : 0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                        CollectibleSendButton(model: model, item: item)
                        HStack(spacing: 10) {
                            V8Button("Ver coleção", .line, compact: true, action: onSeeCollection).foregroundStyle(V8.white)
                            V8Button("Depois", .line, compact: true, action: onDismiss).foregroundStyle(V8.muteDark)
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .ignoresSafeArea()
        .task(id: item.id) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if reduceMotion { withAnimation(.easeOut(duration: 0.3)) { shown = true } } else {
                withAnimation(.interpolatingSpring(stiffness: 40, damping: 9).speed(0.75)) { shown = true }
            }
            await model.render(item, tint: tint)
        }
        .onDisappear { model.cleanup() }
        .transition(.opacity)
    }
}

// MARK: - Card grande + Mandar (da página Coleção)

struct CollectibleDetailView: View {
    var item: Collectible
    var tint: Color

    @Environment(\.dismiss) private var dismiss
    @State private var model = CollectibleShareModel()

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 40, model.format == .stories ? 260 : 340)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        SpecLabel("Colecionável · nº \(item.order) de \(item.total)\n\(item.isRare ? "raro · âncora" : "feito")", color: V8.muteDark)
                        Spacer()
                        Button { dismiss() } label: { Text("Fechar").font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.white) }
                            .frame(minHeight: 44)
                    }
                    HStack(spacing: 8) {
                        ForEach(CollectibleFormat.allCases) { f in
                            Button { model.format = f } label: { V8Pill(f.label, active: model.format == f, onInk: true) }.buttonStyle(.plain)
                        }
                    }
                    ScaledCollectibleCard(item: item, format: model.format, tint: tint, width: width, corner: 32)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    CollectibleSendButton(model: model, item: item)
                    Text("Gerado no aparelho, sem foto. Vai pelo share sheet: Instagram, Facebook, WhatsApp, Mensagens ou Fotos.")
                        .font(V8Font.text(13)).foregroundStyle(V8.muteDark).fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.ink.ignoresSafeArea())
        .task(id: model.format) { await model.render(item, tint: tint) }
        .onDisappear { model.cleanup() }
        .presentationDetents([.large])
    }
}

// MARK: - Host da celebração (RootView)

/// Escuta `must.collectible.new` e mostra o momento por cima do app. Marcar vários feitos seguidos: só o último
/// celebra (espera 0,6 s; os anteriores entram quietos). Não celebra duas vezes o mesmo lugar.
struct CollectibleCelebrationHost: ViewModifier {
    @Environment(RegionStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @State private var current: Collectible?
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item = current {
                    CollectibleMomentView(item: item, regionName: store.region.profile.inName,
                                          money: item.spent.map { store.region.money($0) },
                                          tint: CollectibleTint.color(store.region),
                                          onSeeCollection: { dismiss(); router.select(.viagem); router.push(.colecao, on: .viagem) },
                                          onDismiss: dismiss)
                        .zIndex(10)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CollectibleCelebration.notification)) { note in
                guard let id = note.userInfo?["placeId"] as? String else { return }
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    present(placeId: id)
                }
            }
    }

    private func dismiss() { withAnimation(.easeOut(duration: 0.25)) { current = nil } }

    private func present(placeId: String) {
        #if DEBUG
        CollectionDemo.ensure(context: context, region: store.region, make: placeId)
        #endif
        let prefs = CollectionPrefs(regionId: store.region.rawValue)
        let all = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        guard let place = all.first(where: { $0.id == placeId }),
              let item = Collectible.make(from: place, in: all, region: store.region) else { return }
        #if DEBUG
        let force = DebugFlags.string("debugScreen")?.hasPrefix("colecionavel-novo") == true
        #else
        let force = false
        #endif
        guard force || !prefs.celebrated.contains(placeId) else { return }
        prefs.celebrated = prefs.celebrated.union([placeId])
        withAnimation(.easeOut(duration: 0.25)) { current = item }
    }
}

extension View {
    /// Monta o momento "novo colecionável" por cima do app (uma vez, na raiz).
    func collectibleCelebration() -> some View { modifier(CollectibleCelebrationHost()) }
}
