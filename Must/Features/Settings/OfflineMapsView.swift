import CoreLocation
import SwiftUI

/// Ajustes › Mapas offline: baixar a cidade inteira pra usar o mapa sem internet, e apagar pra liberar espaço.
struct OfflineMapsView: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @State private var confirmDelete: MapPack?

    private var maps: OfflineMaps { services.maps }

    var body: some View {
        Form {
            storage
            ForEach(regionsInOrder) { region in
                section(region)
            }
            Section {} footer: { Text(footer) }
        }
        .navigationTitle("Mapas offline")
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .refreshable { await maps.refreshManifest() }
        .task { await maps.refreshManifest() }
        .confirmationDialog(confirmDelete.map { "Apagar o mapa de \($0.title)?" } ?? "",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { pack in
            Button("Apagar · libera \(size(maps.bytes(pack.id)))", role: .destructive) { maps.delete(pack.id) }
        } message: { _ in
            Text("Com internet, o mapa continua carregando pela rede.")
        }
    }

    private var regionsInOrder: [Region] {
        [store.region] + Region.allCases.filter { $0 != store.region }
    }

    private var here: CLLocationCoordinate2D? { services.location.current?.coordinate }

    // MARK: Espaço

    private var storage: some View {
        Section {
            LabeledContent {
                Text(maps.installedBytes == 0 ? "0 MB" : size(maps.installedBytes)).monospacedDigit()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No iPhone")
                    Text(storageSubtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !maps.isConfigured {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Servidor de mapas desligado").foregroundStyle(.red)
                    Text("falta MAP_TILES_URL no Secrets.plist").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var storageSubtitle: String {
        let count = maps.installedCount
        let cities = count == 0 ? "nenhuma cidade baixada" : count == 1 ? "1 cidade baixada" : "\(count) cidades baixadas"
        guard let free = MapPackFiles.freeSpace else { return cities }
        return "\(cities) · \(size(free)) livres"
    }

    private var footer: String {
        var line = "Sem baixar, o mapa carrega pela internet. Os arquivos ficam fora do backup do iCloud."
        if let build = MapPack.catalog.compactMap({ maps.build($0.id) }).max(), let date = Self.buildDate(build) {
            line += " Mapas de \(date) · © OpenStreetMap · Protomaps."
        } else {
            line += " © OpenStreetMap · Protomaps."
        }
        return line
    }

    // MARK: Cidades

    static func sectionTitle(_ region: Region) -> String {
        // BH: o pacote é do estado; as viagens, do país.
        region == .bh ? "Minas Gerais" : region.countryName
    }

    private func section(_ region: Region) -> some View {
        let packs = MapPack.catalog.filter { $0.region == region }
        let missing = packs.filter { !maps.isInstalled($0.id) && maps.phases[$0.id] == nil }
        let missingBytes = missing.compactMap { maps.bytes($0.id) }.reduce(0, +)
        return Section(Self.sectionTitle(region)) {
            ForEach(packs) { pack in row(pack) }
            if missing.count > 1, maps.isConfigured {
                Button(missingBytes > 0 ? "Baixar todas · \(size(missingBytes))" : "Baixar todas") {
                    missing.forEach(maps.download)
                }
            }
        }
    }

    private func row(_ pack: MapPack) -> some View {
        let installed = maps.isInstalled(pack.id)
        let phase = maps.phases[pack.id]
        let isHere = here.map { pack.contains($0) } ?? false
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(pack.title)
                    if isHere { Text("você está aqui").font(.caption.weight(.semibold)).foregroundStyle(V9.accent) }
                }
                Text(subtitle(pack, installed: installed, phase: phase))
                    .font(.footnote)
                    .foregroundStyle(phase.isFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing(pack, installed: installed, phase: phase)
        }
    }

    private func subtitle(_ pack: MapPack, installed: Bool, phase: OfflineMaps.Phase?) -> String {
        if case .failed(let message) = phase { return message }
        let bytes = maps.bytes(pack.id).map(size)
        var parts = [pack.subtitle]
        if let bytes { parts.append(bytes) }
        if installed { parts.append(maps.hasUpdate(pack.id) ? "versão nova" : "baixado") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailing(_ pack: MapPack, installed: Bool, phase: OfflineMaps.Phase?) -> some View {
        switch phase {
        case .downloading(let fraction):
            HStack(spacing: 10) {
                Text("\(Int(fraction * 100))%").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                Button { maps.cancel(pack.id) } label: {
                    Gauge(value: max(0.02, fraction)) { Text("Cancelar") } currentValueLabel: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .gaugeStyle(.accessoryCircularCapacity).tint(V9.accent).scaleEffect(0.6)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancelar download")
            }
        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("conferindo").font(.footnote).foregroundStyle(.secondary)
            }
        case .failed:
            Button("Tentar de novo") { maps.download(pack) }.buttonStyle(.bordered)
        case nil:
            if installed {
                HStack(spacing: 8) {
                    if maps.hasUpdate(pack.id) {
                        Button("Atualizar") { maps.download(pack) }.buttonStyle(.borderedProminent).tint(V9.accent)
                    } else {
                        Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityLabel("Baixado")
                    }
                    Button(role: .destructive) { confirmDelete = pack } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Apagar \(pack.title)")
                }
            } else if maps.isConfigured {
                Button("Baixar") { maps.download(pack) }.buttonStyle(.bordered)
            }
        }
    }

    private func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "pt_BR")))
    }

    /// "20261102" → "2 nov 2026" (a data do build, sem fuso).
    static func buildDate(_ build: String) -> String? {
        let months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        guard build.count == 8, let y = Int(build.prefix(4)), let m = Int(build.dropFirst(4).prefix(2)),
              let d = Int(build.suffix(2)), (1...12).contains(m), (1...31).contains(d) else { return nil }
        return "\(d) \(months[m - 1]) \(y)"
    }
}

private extension Optional where Wrapped == OfflineMaps.Phase {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

/// Linha de Ajustes que leva aos mapas offline.
struct OfflineMapsRow: View {
    @Environment(Services.self) private var services

    var body: some View {
        Section("Mapa") {
            NavigationLink(value: Route.offlineMaps) {
                LabeledContent {
                    Text(services.maps.installedCount == 0 ? "baixar" : "\(services.maps.installedCount)").monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mapas offline")
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let maps = services.maps
        guard maps.installedCount > 0 else { return "baixe a cidade pra usar o mapa sem internet" }
        let bytes = maps.installedBytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "pt_BR")))
        return maps.installedCount == 1 ? "1 cidade · \(bytes)" : "\(maps.installedCount) cidades · \(bytes)"
    }
}

/// No Mapa: "Baixar o mapa de Belo Horizonte · 11 MB" quando a cidade do GPS ainda não está no aparelho.
/// Some depois de baixado ou quando o usuário fecha (por cidade).
struct OfflineMapNudge: View {
    var here: CLLocationCoordinate2D?
    var region: Region
    @Environment(Services.self) private var services
    @AppStorage("maps.nudgeDismissed") private var dismissed = ""

    private var pack: MapPack? {
        guard let here, let pack = MapPack.containing(here, region: region) else { return nil }
        return pack
    }

    var body: some View {
        if let pack, services.maps.isConfigured, !services.maps.isInstalled(pack.id),
           !dismissed.split(separator: ",").contains(Substring(pack.id)) {
            card(pack)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func card(_ pack: MapPack) -> some View {
        let phase = services.maps.phases[pack.id]
        let bytes = services.maps.bytes(pack.id)
            .map { " · " + $0.formatted(.byteCount(style: .file).locale(Locale(identifier: "pt_BR"))) } ?? ""
        return HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(status(phase, bytes: bytes)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            switch phase {
            case .downloading, .verifying:
                ProgressView().controlSize(.small)
            default:
                Button("Baixar") { services.maps.download(pack) }.buttonStyle(.borderedProminent).tint(V9.accent).controlSize(.small)
                Button {
                    withAnimation { dismissed = (dismissed.split(separator: ",").map(String.init) + [pack.id]).joined(separator: ",") }
                } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Agora não")
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
        .task { if services.maps.manifest?[pack.id] == nil { await services.maps.refreshManifest() } }
    }

    private func status(_ phase: OfflineMaps.Phase?, bytes: String) -> String {
        switch phase {
        case .downloading(let f): "baixando · \(Int(f * 100))%"
        case .verifying: "conferindo o arquivo"
        case .failed(let message): message
        case nil: "mapa sem internet\(bytes)"
        }
    }
}
