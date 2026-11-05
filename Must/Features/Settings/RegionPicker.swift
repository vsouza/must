import SwiftUI

/// Ajustes › Região: Automático (pelo GPS) · BH · Japão · Itália. Cada região tem o próprio board; trocar não apaga
/// nada. A troca usa o mesmo fade de 0,4 s de `RegionStore.switchTo`.
struct RegionPicker: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    var body: some View {
        FormSection("Região") {
            VStack(alignment: .leading, spacing: 12) {
                // Quatro chips: rolam na horizontal se não couberem (tela estreita, Dynamic Type grande).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        option("Automático", on: store.isAuto) { store.choose(nil, near: services.location.current?.coordinate) }
                        ForEach(Region.allCases) { r in
                            option(Self.label(r), on: !store.isAuto && store.region == r) {
                                store.choose(r, near: nil)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                Text(subtitle).font(.must.meta).foregroundStyle(Color.must.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
        }
    }

    /// Rótulo curto do chip: "BH", "Japão", "Itália".
    static func label(_ region: Region) -> String {
        switch region {
        case .bh: "BH"
        case .jp: "Japão"
        case .it: "Itália"
        }
    }

    private var subtitle: String {
        if store.isAuto {
            let gps = services.location.current.flatMap { Region.detect($0.coordinate) }
            return gps == nil ? "pelo GPS · sem localização, fica em \(store.region.displayName)"
                : "pelo GPS · agora em \(store.region.displayName)"
        }
        return "fixo em \(store.region.displayName) · cada região guarda o próprio board"
    }

    private func option(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Pill(title, isOn: on) }.buttonStyle(MustPressStyle())
    }
}
