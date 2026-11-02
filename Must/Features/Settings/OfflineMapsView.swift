import CoreLocation
import SwiftUI

/// Ajustes › Mapas offline: baixar a cidade inteira pra usar o mapa sem internet, e apagar pra liberar espaço.
struct OfflineMapsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @State private var confirmDelete: MapPack?

    private var maps: OfflineMaps { services.maps }

    var body: some View {
        ZStack(alignment: .top) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 340, cy: 120, rx: 96, ry: 54, rotation: -12, fill: .blue),
                Blob(cx: 46, cy: 790, rx: 70, ry: 60, rotation: 8, fill: .green),
            ]))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        IconButton(.voltar, label: "Voltar") { dismiss() }
                        Spacer()
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mapas offline").mustTitle()
                        Text("baixe a cidade e o mapa funciona sem internet").mustSerif(18).foregroundStyle(Color.must.secondary)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                    storage
                    ForEach(regionsInOrder) { region in
                        section(region)
                    }
                    Text(footer)
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 120)
            }
            .refreshable { await maps.refreshManifest() }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        FormSection {
            FormRow("No iPhone", subtitle: storageSubtitle) {
                MonoValue(maps.installedBytes == 0 ? "0 MB" : size(maps.installedBytes))
            }
            if !maps.isConfigured {
                RowDivider()
                FormRow("Servidor de mapas desligado", subtitle: "falta MAP_TILES_URL no Secrets.plist",
                        titleColor: Color(hex: 0xC2261D))
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

    private func section(_ region: Region) -> some View {
        let packs = MapPack.catalog.filter { $0.region == region }
        let missing = packs.filter { !maps.isInstalled($0.id) && maps.phases[$0.id] == nil }
        let missingBytes = missing.compactMap { maps.bytes($0.id) }.reduce(0, +)
        return FormSection(region == .bh ? "Minas Gerais" : "Japão") {
            ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                if index > 0 { RowDivider() }
                row(pack)
            }
            if missing.count > 1, maps.isConfigured {
                RowDivider()
                Button {
                    missing.forEach(maps.download)
                } label: {
                    HStack {
                        Pill(missingBytes > 0 ? "Baixar todas · \(size(missingBytes))" : "Baixar todas", style: .green)
                        Spacer()
                    }
                }
                .buttonStyle(MustPressStyle())
                .padding(.vertical, 14)
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
                    Text(pack.title).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
                    if isHere { Tag("você está aqui", dot: Color.must.green) }
                }
                Text(subtitle(pack, installed: installed, phase: phase))
                    .font(.must.meta)
                    .foregroundStyle(phase.isFailure ? Color(hex: 0xC2261D) : Color.must.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing(pack, installed: installed, phase: phase)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("\(Int(fraction * 100))%").font(.must.mono(13)).foregroundStyle(Color.must.secondary)
                    .monospacedDigit()
                Button { maps.cancel(pack.id) } label: {
                    ZStack {
                        Circle().stroke(Color.must.line, lineWidth: 3)
                        Circle().trim(from: 0, to: max(0.02, fraction))
                            .stroke(Color.must.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        MustIconView(.fechar, size: 12).foregroundStyle(Color.must.ink)
                    }
                    .frame(width: 32, height: 32)
                    .animation(.linear(duration: 0.2), value: fraction)
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Cancelar download")
            }
        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("conferindo").font(.must.mono(13)).foregroundStyle(Color.must.secondary)
            }
        case .failed:
            Button { maps.download(pack) } label: { Pill("Tentar de novo") }
                .buttonStyle(MustPressStyle())
        case nil:
            if installed {
                HStack(spacing: 8) {
                    if maps.hasUpdate(pack.id) {
                        Button { maps.download(pack) } label: { Pill("Atualizar", style: .green) }
                            .buttonStyle(MustPressStyle())
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.must.green)
                            .accessibilityLabel("Baixado")
                    }
                    IconButton(.remover, size: 34, label: "Apagar \(pack.title)") { confirmDelete = pack }
                }
            } else if maps.isConfigured {
                Button { maps.download(pack) } label: { Pill("Baixar") }
                    .buttonStyle(MustPressStyle())
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
        FormSection("Mapa") {
            NavigationLink(value: Route.offlineMaps) {
                FormRow("Mapas offline", subtitle: subtitle) {
                    MonoValue(services.maps.installedCount == 0 ? "baixar" : "\(services.maps.installedCount)", chevron: true)
                }
            }
            .buttonStyle(.plain)
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.must.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.must.surface))
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                Text(status(phase, bytes: bytes)).font(.must.meta).foregroundStyle(Color.must.secondary)
            }
            Spacer(minLength: 0)
            switch phase {
            case .downloading, .verifying:
                ProgressView().controlSize(.small)
            default:
                Button { services.maps.download(pack) } label: { Pill("Baixar", style: .green) }
                    .buttonStyle(MustPressStyle())
                Button {
                    withAnimation { dismissed = (dismissed.split(separator: ",").map(String.init) + [pack.id]).joined(separator: ",") }
                } label: {
                    MustIconView(.fechar, size: 12).foregroundStyle(Color.must.secondary).frame(width: 28, height: 28)
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Agora não")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(cornerRadius: 26)
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
