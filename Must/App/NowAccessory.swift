import SwiftData
import SwiftUI

/// Faixa "agora" da barra nativa (`tabViewBottomAccessory`): a próxima parada do dia lida do `DayClock` ("Agora: Gyoen ·
/// saia às 15:10"); sem dia montado, "Montar o dia de hoje". Uma linha. Toque: Linha do dia (ou Montar).
struct NowAccessory: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context
    /// Dia aceito/refeito/feito grava no SwiftData: a faixa relê na hora, igual a Hoje (sem esperar o próximo minuto,
    /// senão Hoje diz "Próxima: X" e a faixa ainda diz "Montar o dia de hoje").
    @State private var saves = 0

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let _ = saves
            let region = store.region
            let now = AppClock.now
            let today = region.calendar.startOfDay(for: now)
            let clock = DayClock.read(engine: engine, region: region, context: context, at: now,
                                      position: services.location.current?.coordinate)
            let line = NowAccessoryLine.make(clock: clock, region: region)
            Button {
                if clock.phase == .noPlan {
                    router.push(.montar(date: today), on: .hoje)
                } else {
                    router.push(.linha(date: today), on: .hoje)
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(V9.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(line)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .font(.body)
                .fontDesign(.default)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(clock.phase == .noPlan ? "monta o dia de hoje" : "abre a linha do dia")
        }
        // Atrás da faixa, o mapa (estilo papel, sempre claro) e as telas V8 (Musts) continuam claros: no modo escuro o
        // vidro fica claro e o texto branco sumia. Nessas abas a faixa segue o claro.
        .modifier(LightBehind(enabled: !router.queroSelected && (router.tab == .explorar || router.tab == .musts)))
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in saves &+= 1 }
    }
}

/// O texto da faixa, puro (testável).
enum NowAccessoryLine {
    static func make(clock: DayClock, region: Region) -> String {
        switch clock.phase {
        case .noPlan: return "Montar o dia de hoje"
        case .running:
            guard let now = clock.now else { return "Montar o dia de hoje" }
            let name = now.current.label
            if let at = clock.actionTime { return "Agora: \(name) · \(clock.actionVerb) às \(region.timeString(at))" }
            return "Agora: \(name)"
        case .before:
            guard let up = clock.upcoming else { return "Seu dia" }
            return "Próxima: \(up.stop.label) · \(clock.actionVerb) às \(region.timeString(up.leaveAt))"
        case .finished: return "Dia concluído · ver a Linha"
        }
    }
}

/// Liga a faixa à barra nativa. Desde o iOS 26.1 dá pra desligar de verdade (telas sem barra); no 26.0 sobra a cápsula vazia,
/// então ali o conteúdo some e a faixa fica só como espaço.
struct NowAccessoryModifier: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { NowAccessory() }
        } else {
            content.tabViewBottomAccessory { if enabled { NowAccessory() } }
        }
    }
}

private struct LightBehind: ViewModifier {
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.environment(\.colorScheme, .light) } else { content }
    }
}
