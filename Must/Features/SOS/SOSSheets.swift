import CoreLocation
import SwiftUI
import UIKit

/// As folhas do SOS (papel, como as do Bolso).
enum SOSSheet: String, Identifiable {
    case profile, hospitals, consulate, numbers, phrases
    var id: String { rawValue }
}

struct SOSSheetView: View {
    var which: SOSSheet
    var region: Region
    var kit: CountryKit?
    var cityId: String?
    var location: CLLocation?
    @Binding var profile: SOSProfile
    var address: LastAddress?
    var speaker: PhraseSpeaker
    var onSave: (SOSProfile) -> Void

    var body: some View {
        switch which {
        case .profile: SOSProfileSheet(region: region, profile: profile, onSave: onSave).presentationDetents([.large])
        case .hospitals: SOSHospitalsSheet(region: region, cityId: cityId, location: location).presentationDetents([.large])
        case .consulate:
            if let consulate = kit?.consulate(cityId: cityId) {
                SOSConsulateSheet(consulate: consulate, all: kit?.consulates ?? []).presentationDetents([.medium, .large])
            }
        case .numbers: SOSNumbersSheet(kit: kit).presentationDetents([.medium, .large])
        case .phrases: SOSPhrasesSheet(region: region, phrases: kit?.phrases ?? [], speaker: speaker).presentationDetents([.medium, .large])
        }
    }
}

/// Cabeçalho comum das folhas: micro-rótulos, fechar e o título.
private struct SOSSheetHeader: View {
    var lines: [String]
    var title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                V8SpecStack(lines: lines).padding(.top, 14)
                Spacer()
                V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
            }
            Text(title)
                .font(V8Font.display(38))
                .tracking(-1.1)
                .foregroundStyle(V8.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Uma linha de contato numa folha (nome, detalhe e os botões de ligar/rota).
private struct SOSContactRow: View {
    var title: String
    var detail: String
    var meta: String?
    var check = false
    var call: URL?
    var callLabel: String?
    var coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).fixedSize(horizontal: false, vertical: true)
                if check { V8Tag(text: "conferir", style: .orange) }
            }
            Text(detail).font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
            if let meta { Text(meta).font(V8Font.mono(11)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                if let call {
                    Link(destination: call) { V8Pill(callLabel ?? "ligar", active: true) }
                        .accessibilityHint("abre o discador")
                }
                if let coordinate {
                    Button { MapsLinks.openApple(to: coordinate, name: title, mode: .transit) } label: { V8Pill("rota") }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SOSSheetHeader(lines: ["SOS · \(isHome ? "plano de saúde" : "seguro viagem")", "só neste aparelho"],
                               title: isHome ? "Seu plano" : "Seu seguro")
                Text("Fica só no iPhone: não vai pro iCloud, pro backup nem pro export do board.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                VStack(spacing: 0) {
                    field(isHome ? "Operadora" : "Seguradora", text: $profile.insurer, prompt: isHome ? "Unimed BH" : "Assist Card")
                    field(isHome ? "Carteirinha" : "Apólice", text: $profile.policy, prompt: "nº")
                    field("Telefone 24 h", text: $profile.phone24h, prompt: "+55 …", keyboard: .phonePad)
                    field("Instruções", text: $profile.instructions, prompt: SOSProfile.defaultInstructions, axis: .vertical)
                    field("Tipo sanguíneo · opcional", text: $profile.bloodType, prompt: "O+")
                    field("Alergias · opcional", text: $profile.allergies, prompt: "dipirona, amendoim…", axis: .vertical)
                }
                .padding(.top, 18)
                BigButton(title: "Guardar", style: .ink, systemImage: "checkmark") {
                    onSave(trimmed)
                    dismiss()
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(V8.paper.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 6) {
            SpecLabel(label)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(V8.mute.opacity(0.7)), axis: axis)
                .font(V8Font.text(17, weight: .semibold))
                .foregroundStyle(V8.ink)
                .keyboardType(keyboard)
                .lineLimit(1...4)
                .accessibilityIdentifier("sos.\(label)")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }
    }
}

// MARK: - Hospitais

/// Hospitais da lista curada, do mais perto pro mais longe; com rede, "procurar mais perto" no Google (reserva).
struct SOSHospitalsSheet: View {
    var region: Region
    var cityId: String?
    var location: CLLocation?

    @Environment(Services.self) private var services
    @State private var extra: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        let list = HospitalCatalog.bundled.nearest(region: region, to: location, cityId: cityId)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SOSSheetHeader(lines: ["SOS · hospitais", location == nil ? "sem GPS · ordem da lista" : "do mais perto"], title: "Hospital perto")
                Text(region.country == "BR" ? "Pronto-socorro 24 h. Em risco de vida, ligue 192 antes."
                     : "Ligue pro seguro antes de ir: ele indica o hospital e paga direto. Em risco de vida, a ambulância primeiro.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(list, id: \.hospital.id) { item in
                        let h = item.hospital
                        SOSContactRow(title: h.name,
                                      detail: SOSText.hospitalLine(h, meters: item.meters, region: region),
                                      meta: [h.address, h.addressLocal, h.phone].compactMap { $0 }.joined(separator: "\n"),
                                      check: h.needsCheck, call: h.telURL, callLabel: h.phone.map { "ligar \($0)" },
                                      coordinate: CLLocationCoordinate2D(latitude: h.lat, longitude: h.lng))
                    }
                }
                .padding(.top, 18)
                google.padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(V8.paper.ignoresSafeArea())
    }

    /// Reserva: só com rede, chave e GPS, e só no toque (uma chamada do Text Search, que já existe no app).
    @ViewBuilder private var google: some View {
        let canSearch = services.connectivity.status != .offline && services.places.isConfigured && location != nil
        if canSearch {
            if !searched {
                BigButton(title: searching ? "Procurando…" : "Procurar mais perto no Google", style: .line, systemImage: "magnifyingglass") {
                    Task { await search() }
                }
                .disabled(searching)
            } else if extra.isEmpty {
                Text("O Google não achou outro hospital por perto.").font(V8Font.text(14)).foregroundStyle(V8.mute)
            } else {
                SpecLabel("Google · por perto")
                ForEach(extra) { c in
                    SOSContactRow(title: c.name, detail: c.address ?? "",
                                  meta: location.map { SOSText.distance($0.distance(from: CLLocation(latitude: c.lat, longitude: c.lng))) },
                                  coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng))
                }
            }
        } else {
            Text("Sem internet: a lista acima é do app e funciona offline.")
                .font(V8Font.text(13)).foregroundStyle(V8.mute)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SOSSheetHeader(lines: ["SOS · consulado do Brasil", "passaporte, documentos, presos"], title: "Consulado BR")
                Text("Perdeu o passaporte: boletim na polícia (110 no Japão, 112 na Itália) e depois o consulado, com foto e o BO.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach([consulate] + all.filter { $0.id != consulate.id }) { c in
                        SOSContactRow(title: c.name, detail: c.detail,
                                      meta: [c.address, c.addressLocal, c.phone, c.emergencyPhone.map { "plantão \($0)" }]
                                        .compactMap { $0 }.joined(separator: "\n"),
                                      check: c.needsCheck, call: c.emergencyTelURL ?? c.telURL,
                                      callLabel: c.emergencyTelURL != nil ? "plantão" : "ligar")
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(V8.paper.ignoresSafeArea())
    }
}

struct SOSNumbersSheet: View {
    var kit: CountryKit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SOSSheetHeader(lines: ["SOS · \(kit?.name ?? "")", "toque pra abrir o discador"], title: "Números")
                VStack(spacing: 0) {
                    ForEach((kit?.primary ?? []) + (kit?.more ?? [])) { n in
                        SOSContactRow(title: "\(n.number) · \(n.title)",
                                      detail: n.telURL == nil ? "\(n.detail) · disque no teclado" : n.detail,
                                      check: n.verificar, call: n.telURL, callLabel: "ligar \(n.number)")
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(V8.paper.ignoresSafeArea())
    }
}

struct SOSPhrasesSheet: View {
    var region: Region
    var phrases: [EmergencyPhrase]
    var speaker: PhraseSpeaker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SOSSheetHeader(lines: ["SOS · frases", "toque pra ouvir · offline"], title: "Frases")
                VStack(spacing: 0) {
                    ForEach(phrases) { phrase in
                        Button { speaker.speak(phrase.speech, language: PocketRules.country(region).speechLanguage) } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(phrase.latin).font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(phrase.meaning).font(V8Font.text(14)).foregroundStyle(V8.mute)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: speaker.speaking == phrase.speech ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(V8.ink)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(speaker.speaking == phrase.speech ? V8.orange : V8.white))
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(phrase.latin), \(phrase.meaning)")
                        .accessibilityHint("toca o áudio")
                        Rectangle().fill(V8.rule).frame(height: 1)
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(V8.paper.ignoresSafeArea())
    }
}

// MARK: - Onde estou em tela cheia

/// O endereço grande, pra mostrar ao taxista/atendente; "ouvir" lê no idioma local, "copiar" vai pra área de transferência.
struct SOSAddressFullScreen: View {
    var region: Region
    var address: LastAddress?
    var location: CLLocation?
    var speaker: PhraseSpeaker

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var shown: WhereAmI.Display? { WhereAmI.display(address, location: location, now: AppClock.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                V8SpecStack(lines: [region.profile.sos?.whereAmITitle ?? "Onde estou",
                                    shown?.isStale == true ? "último endereço conhecido" : "mostre esta tela"])
                    .padding(.top, 14)
                Spacer()
                V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
            }
            Spacer(minLength: 20)
            if let shown {
                Text(shown.main)
                    .font(V8Font.display(region.profile.sos?.whereAmIFontSize ?? 40))
                    .foregroundStyle(V8.ink)
                    .minimumScaleFactor(0.4)
                    .textSelection(.enabled)
                    .accessibilityLabel(shown.main)
                if !shown.sub.isEmpty {
                    Text(shown.sub).font(V8Font.text(18)).foregroundStyle(V8.mute).padding(.top, 14)
                }
                if let location {
                    Text(WhereAmI.coordinateText(location.coordinate)).font(V8Font.mono(13)).foregroundStyle(V8.mute).padding(.top, 10)
                }
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                BigButton(title: "Ouvir", style: .orange, systemImage: "speaker.wave.2.fill") {
                    if let main = shown?.main { speaker.speak(main, language: PocketRules.country(region).speechLanguage) }
                }
                BigButton(title: copied ? "Copiado" : "Copiar", style: .line, systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = shown?.main
                    copied = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(V8.white.ignoresSafeArea())
    }
}
