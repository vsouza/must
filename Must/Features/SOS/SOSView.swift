import CoreLocation
import SwiftData
import SwiftUI
import UIKit

/// SOS (V9, prompt 32 Fase 2): lista nativa com os números do país da região em linhas grandes e tocáveis (o `tel:` só
/// abre o discador — o app nunca liga sozinho), o seguro com ligar, o hospital perto (lista curada; o Google só como
/// reserva e só com rede), **onde estou** no idioma local (mostrar em tela cheia, ouvir, copiar), o consulado do Brasil
/// (fora do Brasil), mais números e frases com áudio. Tudo offline: o kit vem no app e o endereço é o último conhecido.
/// Nenhum texto é truncado: as linhas quebram e crescem com o Dynamic Type.
struct SOSView: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var trips: [TripInfo]

    @State private var profile = SOSProfile()
    @State private var address: LastAddress?
    @State private var sheet: SOSSheet?
    @State private var showAddress = false
    @State private var copied = false
    @State private var speaker = PhraseSpeaker()

    private let sos = SOSStore()
    private var region: Region { store.region }
    private var kit: CountryKit? { EmergencyKit.bundled.kit(for: region) }
    private var todayCity: City? { trips.first?.city(on: AppClock.now, calendar: region.calendar) }
    private var cityId: String? { todayCity?.id }
    private var cityName: String? { todayCity?.name }
    private var location: CLLocation? { services.location.current }
    private var isHome: Bool { region.country == "BR" }

    var body: some View {
        List {
            if let kit {
                Section {
                    ForEach(kit.primary.prefix(3)) { number in SOSNumberRow(number: number) }
                } header: {
                    Text("Ligar agora").foregroundStyle(.red)
                } footer: {
                    Text("Toque pra abrir o discador. Funciona sem internet; o app nunca liga sozinho.")
                }
                lines(kit)
            } else {
                Section { Text("O kit de emergência deste país não está no app.").foregroundStyle(.secondary) }
            }
            Section {
                Text("Números conferidos em fonte oficial em \(EmergencyKit.bundled.checked.map(SOSText.checkedDate) ?? "—"). Seguro e saúde ficam só neste aparelho: não vão pro iCloud, pro backup nem pro export.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SOS · \(region.countryName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { V9OfflineChip() } }
        .v9Screen(grouped: true)
        .onAppear {
            profile = sos.profile()
            address = sos.lastAddress(country: region.country)
        }
        .task(id: LocationKey(location)) { await refreshAddress() }
        .sheet(item: $sheet) { which in
            SOSSheetView(which: which, region: region, kit: kit, cityId: cityId, cityName: cityName, location: location,
                         profile: $profile, address: address, speaker: speaker) { new in
                profile = new
                try? sos.save(new)
            }
        }
        .fullScreenCover(isPresented: $showAddress) {
            SOSAddressFullScreen(region: region, address: address, location: location, speaker: speaker)
        }
    }

    /// Posição arredondada (~100 m): o geocoder só roda de novo quando a pessoa andou.
    private struct LocationKey: Hashable {
        var lat: Int
        var lng: Int
        init(_ l: CLLocation?) {
            lat = Int(((l?.coordinate.latitude ?? 0) * 1000).rounded())
            lng = Int(((l?.coordinate.longitude ?? 0) * 1000).rounded())
        }
    }

    /// Com rede e GPS, atualiza o endereço (no máximo um a cada ~150 m / 10 min). Sem rede: fica o último conhecido.
    private func refreshAddress() async {
        guard let location, services.connectivity.status != .offline,
              WhereAmI.needsRefresh(address, location: location, now: AppClock.now) else { return }
        guard let fresh = await WhereAmI.lookup(location, region: region), !Task.isCancelled else { return }
        address = fresh
        try? sos.save(fresh)
    }

    // MARK: Linhas

    @ViewBuilder
    private func lines(_ kit: CountryKit) -> some View {
        let hospitals = HospitalCatalog.bundled.nearest(region: region, to: location, cityId: cityId, cityName: cityName)
        Section("Seu caso") {
            insuranceLine
            if let first = hospitals.first {
                SOSLine(key: "Hospital perto", value: first.hospital.name,
                        detail: SOSText.hospitalLine(first.hospital, meters: first.meters, region: region),
                        check: first.hospital.needsCheck) { sheet = .hospitals }
            }
            whereLine
            if !isHome, let consulate = kit.consulate(cityId: cityId, cityName: cityName) {
                SOSLine(key: "Consulado do Brasil", value: consulate.name,
                        detail: [consulate.phone, consulate.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                        check: consulate.needsCheck) { sheet = .consulate }
            }
            if profile.hasHealth {
                SOSLine(key: "Saúde", value: [profile.bloodType, profile.allergies.isEmpty ? "" : "alergia: \(profile.allergies)"]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        detail: "só neste aparelho · toque pra editar") { sheet = .profile }
            }
        }
        if !kit.more.isEmpty || !kit.phrases.isEmpty {
            Section("Mais") {
                if !kit.more.isEmpty {
                    SOSLine(key: "Mais números", value: kit.more.prefix(3).map { "\($0.number) \(SOSText.short($0.title))" }.joined(separator: " · "),
                            detail: "toque pra ver todos e ligar", check: kit.more.contains { $0.verificar }) { sheet = .numbers }
                }
                if !kit.phrases.isEmpty {
                    SOSLine(key: "Frases", value: kit.phrases.prefix(2).map(\.latin).joined(separator: " · "),
                            detail: kit.phrases.prefix(2).map(\.meaning).joined(separator: " · ") + " · com áudio") { sheet = .phrases }
                }
            }
        }
    }

    private var insuranceLine: some View {
        let key = isHome ? "Seu plano" : "Seu seguro"
        let value = profile.isEmpty ? (isHome ? "Cadastrar o plano de saúde" : "Cadastrar o seguro viagem")
            : [profile.insurer, profile.policy.isEmpty ? "" : "apólice \(profile.policy)"].filter { !$0.isEmpty }.joined(separator: " · ")
        let instructions = profile.instructions.isEmpty ? SOSProfile.defaultInstructions : profile.instructions
        let detail = profile.isEmpty ? "seguradora, apólice e o telefone 24 h · fica só neste aparelho"
            : [instructions, profile.phone24h].filter { !$0.isEmpty }.joined(separator: " · ")
        return SOSLine(key: key, value: value, detail: detail, callURL: profile.phoneURL) { sheet = .profile }
    }

    private var whereLine: some View {
        let shown = WhereAmI.display(address, location: location, now: AppClock.now)
        let value = shown?.main ?? "Sem GPS ainda"
        var detail = [shown?.sub ?? "", shown == nil ? "ligue a localização" : (copied ? "copiado" : "toque pra mostrar em tela cheia")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        if shown?.isStale == true { detail = "último conhecido · " + detail }
        return SOSLine(key: "Onde estou", value: value, detail: detail) {
            guard shown != nil else { return }
            showAddress = true
        }
        .swipeActions {
            if let shown {
                Button("Copiar") { UIPasteboard.general.string = shown.main; copied = true }
            }
        }
        .contextMenu {
            if let shown {
                Button("Mostrar em tela cheia", systemImage: "arrow.up.left.and.arrow.down.right") { showAddress = true }
                Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = shown.main; copied = true }
            }
        }
    }
}

// MARK: - Peças

/// Número de emergência: o número grande em vermelho, o que é e a ajuda; a linha inteira abre o discador.
struct SOSNumberRow: View {
    var number: EmergencyNumber

    var body: some View {
        let content = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(number.number)
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.red)
                    .minimumScaleFactor(0.6).lineLimit(1)
                HStack(spacing: 6) {
                    Text(number.badge != nil ? "\(number.title) · \(number.number)" : number.title)
                        .font(.headline).foregroundStyle(.primary)
                    if number.verificar { Text("conferir").font(.caption.weight(.semibold)).foregroundStyle(.red) }
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(number.telURL == nil ? "\(number.detail) · disque no teclado" : number.detail)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if number.telURL != nil {
                Image(systemName: "phone.fill").font(.title3).foregroundStyle(.red).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        if let url = number.telURL {
            Link(destination: url) { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(number.title), ligar \(number.number)")
                .accessibilityHint("abre o discador")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// Linha de lista: rótulo pequeno em cima, valor em negrito e detalhe, tudo quebrando; à direita, ligar (quando há).
struct SOSLine: View {
    var key: String
    var value: String
    var detail: String
    var check = false
    var callURL: URL?
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(key).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        if check { Text("conferir").font(.caption.weight(.semibold)).foregroundStyle(.red) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let callURL {
                Link(destination: callURL) {
                    Image(systemName: "phone.fill").font(.title3).foregroundStyle(.red)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Ligar pro seguro")
                .accessibilityHint("abre o discador")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }
}

/// Textos do SOS (puros, pros testes).
enum SOSText {
    /// "pronto-socorro 24 h · atende em inglês · 1,1 km".
    static func hospitalLine(_ h: Hospital, meters: CLLocationDistance?, region: Region) -> String {
        var parts: [String] = []
        // Nota que já diz que é pronto-socorro ("pronto-socorro de trauma do SUS") vai no lugar do selo genérico.
        let note = h.note.flatMap { $0.components(separatedBy: " · ").first }?.trimmingCharacters(in: .whitespaces) ?? ""
        let noteSaysER = note.localizedCaseInsensitiveContains("pronto") || note.hasPrefix("PS ")
        if noteSaysER { parts.append(note) } else if h.er24h { parts.append("pronto-socorro 24 h") }
        if h.english && region.country != "BR" { parts.append("atende em inglês") }
        if let meters { parts.append(distance(meters)) }
        if !noteSaysER, parts.count < 3, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))) + " km"
    }

    /// "Defesa Civil · desastres" → "Defesa Civil".
    static func short(_ title: String) -> String {
        (title.components(separatedBy: " · ").first ?? title).trimmingCharacters(in: .whitespaces)
    }

    /// "2026-11-05" → "05/11/2026".
    static func checkedDate(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3 else { return iso }
        return "\(p[2])/\(p[1])/\(p[0])"
    }
}
