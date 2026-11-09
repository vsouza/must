import CoreLocation
import SwiftUI
import UIKit

/// As folhas do SOS (V9): `NavigationStack` + lista nativa, botão "Fechar" visível na barra.
enum SOSSheet: String, Identifiable {
    case profile, hospitals, consulate, numbers, phrases
    var id: String { rawValue }
}

struct SOSSheetView: View {
    var which: SOSSheet
    var region: Region
    var kit: CountryKit?
    var cityId: String?
    var cityName: String?
    var location: CLLocation?
    @Binding var profile: SOSProfile
    var address: LastAddress?
    var speaker: PhraseSpeaker
    var onSave: (SOSProfile) -> Void

    var body: some View {
        switch which {
        case .profile: SOSProfileSheet(region: region, profile: profile, onSave: onSave).presentationDetents([.large])
        case .hospitals: SOSHospitalsSheet(region: region, cityId: cityId, cityName: cityName, location: location).presentationDetents([.large])
        case .consulate:
            if let kit, let consulate = kit.consulate(cityId: cityId, cityName: cityName) {
                SOSConsulateSheet(consulate: consulate, all: kit.consulates, passportText: kit.passportText).presentationDetents([.medium, .large])
            }
        case .numbers: SOSNumbersSheet(kit: kit).presentationDetents([.medium, .large])
        case .phrases: SOSPhrasesSheet(region: region, phrases: kit?.phrases ?? [], speaker: speaker).presentationDetents([.medium, .large])
        }
    }
}

/// Moldura comum das folhas: título, "Fechar" na barra, fundo agrupado do sistema.
private struct SOSSheetFrame<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
                .v9Screen(grouped: true)
        }
    }
}

/// Um contato numa folha (nome, detalhe e os botões de ligar/rota), sem texto cortado.
private struct SOSContactRow: View {
    var title: String
    var detail: String
    var meta: String?
    var check = false
    var call: URL?
    var callLabel: String?
    var coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.headline)
                if check { Text("conferir").font(.caption.weight(.semibold)).foregroundStyle(.red) }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let meta, !meta.isEmpty {
                Text(meta).font(.footnote).foregroundStyle(.secondary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let call {
                    Link(destination: call) { Label(callLabel ?? "Ligar", systemImage: "phone.fill").frame(minHeight: 32) }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .accessibilityHint("abre o discador")
                }
                if let coordinate {
                    Button { MapsLinks.openApple(to: coordinate, name: title, mode: .transit) } label: {
                        Label("Rota", systemImage: "map").frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Seguro

/// Seguro (no Brasil, plano de saúde) e saúde opcional. Grava só no aparelho (`SOSStore`).
struct SOSProfileSheet: View {
    var region: Region
    @State var profile: SOSProfile
    var onSave: (SOSProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    init(region: Region, profile: SOSProfile, onSave: @escaping (SOSProfile) -> Void) {
        self.region = region
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    private var isHome: Bool { region.country == "BR" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field(isHome ? "Operadora" : "Seguradora", text: $profile.insurer, prompt: isHome ? "Unimed BH" : "Assist Card")
                    field(isHome ? "Carteirinha" : "Apólice", text: $profile.policy, prompt: "nº")
                    field("Telefone 24 h", text: $profile.phone24h, prompt: "+55 …", keyboard: .phonePad)
                    field("Instruções", text: $profile.instructions, prompt: SOSProfile.defaultInstructions, axis: .vertical)
                } footer: {
                    Text("Fica só no iPhone: não vai pro iCloud, pro backup nem pro export do board.")
                }
                Section("Saúde · opcional") {
                    field("Tipo sanguíneo", text: $profile.bloodType, prompt: "O+")
                    field("Alergias", text: $profile.allergies, prompt: "dipirona, amendoim…", axis: .vertical)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isHome ? "Seu plano" : "Seu seguro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { onSave(trimmed); dismiss() }.fontWeight(.semibold) }
            }
            .v9Screen(grouped: true)
        }
    }

    private var trimmed: SOSProfile {
        var p = profile
        for kp in [\SOSProfile.insurer, \.policy, \.phone24h, \.instructions, \.bloodType, \.allergies] {
            p[keyPath: kp] = p[keyPath: kp].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return p
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default,
                       axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            TextField(label, text: text, prompt: Text(prompt), axis: axis)
                .keyboardType(keyboard)
                .lineLimit(1...4)
                .accessibilityIdentifier("sos.\(label)")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Hospitais

/// Hospitais da lista curada, do mais perto pro mais longe; com rede, "procurar mais perto" no Google (reserva).
struct SOSHospitalsSheet: View {
    var region: Region
    var cityId: String?
    var cityName: String?
    var location: CLLocation?

    @Environment(Services.self) private var services
    @State private var extra: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        let list = HospitalCatalog.bundled.nearest(region: region, to: location, cityId: cityId, cityName: cityName)
        SOSSheetFrame(title: "Hospital perto") {
            List {
                Section {
                    ForEach(list, id: \.hospital.id) { item in
                        let h = item.hospital
                        SOSContactRow(title: h.name,
                                      detail: SOSText.hospitalLine(h, meters: item.meters, region: region),
                                      meta: [h.address, h.addressLocal, h.phone].compactMap { $0 }.joined(separator: "\n"),
                                      check: h.needsCheck, call: h.telURL, callLabel: h.phone.map { "Ligar \($0)" },
                                      coordinate: CLLocationCoordinate2D(latitude: h.lat, longitude: h.lng))
                    }
                } header: {
                    Text(location == nil ? "Sem GPS · ordem da lista" : "Do mais perto")
                } footer: {
                    Text(region.country == "BR" ? "Pronto-socorro 24 h. Em risco de vida, ligue 192 antes."
                         : "Ligue pro seguro antes de ir: ele indica o hospital e paga direto. Em risco de vida, a ambulância primeiro.")
                }
                google
            }
        }
    }

    /// Reserva: só com rede, chave e GPS, e só no toque (uma chamada do Text Search, que já existe no app).
    @ViewBuilder private var google: some View {
        let canSearch = services.connectivity.status != .offline && services.places.isConfigured && location != nil
        if canSearch {
            if !searched {
                Section {
                    Button { Task { await search() } } label: {
                        Label(searching ? "Procurando…" : "Procurar mais perto no Google", systemImage: "magnifyingglass")
                    }
                    .disabled(searching)
                }
            } else if extra.isEmpty {
                Section { Text("O Google não achou outro hospital por perto.").foregroundStyle(.secondary) }
            } else {
                Section("Google · por perto") {
                    ForEach(extra) { c in
                        SOSContactRow(title: c.name, detail: c.address ?? "",
                                      meta: location.map { SOSText.distance($0.distance(from: CLLocation(latitude: c.lat, longitude: c.lng))) },
                                      coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng))
                    }
                }
            }
        } else {
            Section { Text("Sem internet: a lista acima é do app e funciona offline.").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func search() async {
        guard let location, !searching else { return }
        searching = true
        defer { searching = false; searched = true }
        let query = region.country == "BR" ? "pronto-socorro hospital" : "hospital emergency"
        let found = (try? await services.places.searchText(query, near: location.coordinate, radius: 5_000, languageCode: "pt-BR")) ?? []
        let curated = Set(HospitalCatalog.bundled.hospitals(for: region).map { $0.name.lowercased() })
        extra = found.filter { !curated.contains($0.name.lowercased()) }.prefix(5).map { $0 }
    }
}

// MARK: - Consulado, números, frases

struct SOSConsulateSheet: View {
    var consulate: Consulate
    var all: [Consulate]
    var passportText: String

    var body: some View {
        SOSSheetFrame(title: "Consulado do Brasil") {
            List {
                Section {
                    ForEach([consulate] + all.filter { $0.id != consulate.id }) { c in
                        SOSContactRow(title: c.name, detail: c.detail,
                                      meta: [c.address, c.addressLocal, c.phone, c.emergencyPhone.map { "plantão \($0)" }]
                                        .compactMap { $0 }.joined(separator: "\n"),
                                      check: c.needsCheck, call: c.emergencyTelURL ?? c.telURL,
                                      callLabel: c.emergencyTelURL != nil ? "Plantão" : "Ligar")
                    }
                } footer: { Text(passportText) }
            }
        }
    }
}

struct SOSNumbersSheet: View {
    var kit: CountryKit?

    var body: some View {
        SOSSheetFrame(title: "Números") {
            List {
                Section {
                    ForEach((kit?.primary ?? []) + (kit?.more ?? [])) { n in SOSNumberRow(number: n) }
                } footer: { Text("Toque pra abrir o discador. Funciona sem internet.") }
            }
        }
    }
}

struct SOSPhrasesSheet: View {
    var region: Region
    var phrases: [EmergencyPhrase]
    var speaker: PhraseSpeaker

    var body: some View {
        SOSSheetFrame(title: "Frases") {
            List {
                Section {
                    ForEach(phrases) { phrase in
                        Button { speaker.speak(phrase.speech, language: PocketRules.country(region).speechLanguage) } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(phrase.latin).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                    Text(phrase.meaning).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: speaker.speaking == phrase.speech ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .font(.title3).foregroundStyle(speaker.speaking == phrase.speech ? V9.accent : .secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(phrase.latin), \(phrase.meaning)")
                        .accessibilityHint("toca o áudio")
                    }
                } footer: { Text("Toque pra ouvir. Funciona sem internet.") }
            }
        }
    }
}

// MARK: - Onde estou em tela cheia

/// O endereço grande, pra mostrar ao taxista/atendente; "ouvir" lê no idioma local, "copiar" vai pra área de transferência.
/// É o único lugar com escrita local grande (o endereço no idioma do país).
struct SOSAddressFullScreen: View {
    var region: Region
    var address: LastAddress?
    var location: CLLocation?
    var speaker: PhraseSpeaker

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var shown: WhereAmI.Display? { WhereAmI.display(address, location: location, now: AppClock.now) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(shown?.isStale == true ? "Último endereço conhecido" : "Mostre esta tela")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let shown {
                            Text(shown.main)
                                .font(.system(size: region.profile.sos?.whereAmIFontSize ?? 40, weight: .bold))
                                .textSelection(.enabled)
                                .accessibilityLabel(shown.main)
                            if !shown.sub.isEmpty { Text(shown.sub).font(.title3).foregroundStyle(.secondary) }
                            if let location {
                                Text(WhereAmI.coordinateText(location.coordinate)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(V9.gutter)
                }
                HStack(spacing: 10) {
                    Button {
                        if let main = shown?.main { speaker.speak(main, language: PocketRules.country(region).speechLanguage) }
                    } label: { Label("Ouvir", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity) }
                        .v9Primary()
                    Button { UIPasteboard.general.string = shown?.main; copied = true } label: {
                        Label(copied ? "Copiado" : "Copiar", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .v9Secondary()
                }
                .padding(V9.gutter)
            }
            .navigationTitle(region.profile.sos?.whereAmITitle ?? "Onde estou")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen()
        }
    }
}
