import SwiftUI

/// Ajustes › Região: Automático (pelo GPS) · BH · Japão · Itália. Cada região tem o próprio board; trocar não apaga
/// nada. A troca usa o mesmo fade de 0,4 s de `RegionStore.switchTo`.
struct RegionPicker: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    var body: some View {
        Section {
            Button { store.choose(nil, near: services.location.current?.coordinate) } label: { option("Automático", on: store.isAuto) }
            ForEach(Region.allCases) { r in
                Button { store.choose(r, near: nil) } label: { option(Self.label(r), on: !store.isAuto && store.region == r) }
            }
        } header: { Text("Região") } footer: { Text(subtitle) }
    }

    /// Rótulo curto do chip: "BH", "Japão", "Itália".
    static func label(_ region: Region) -> String {
        region.trip.kind == .home ? region.shortName : region.countryName
    }

    private var subtitle: String {
        if store.isAuto {
            let gps = services.location.current.flatMap { Region.detect($0.coordinate) }
            return gps == nil ? "pelo GPS · sem localização, fica em \(store.region.displayName)"
                : "pelo GPS · agora em \(store.region.displayName)"
        }
        return "fixo em \(store.region.displayName) · cada região guarda o próprio board"
    }

    private func option(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if on { Image(systemName: "checkmark").foregroundStyle(V9.accent).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
