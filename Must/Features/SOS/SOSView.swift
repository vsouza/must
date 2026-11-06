import CoreLocation
import SwiftData
import SwiftUI
import UIKit

/// SOS (prompt 25 · C, `SOS.png`): tinta, três botões grandes com os números do país da região (o `tel:` só abre o
/// discador — o app nunca liga sozinho), o seguro com ligar, o hospital perto (lista curada; o Google só como reserva
/// e só com rede), **onde estou** no idioma local (mostrar em tela cheia, ouvir, copiar), o consulado do Brasil (fora
/// do Brasil), mais números e frases com áudio. Tudo offline: o kit vem no app e o endereço é o último conhecido.
struct SOSView: View {
    @Environment(\.dismiss) private var dismiss
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
        ZStack(alignment: .bottom) {
            V8.ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preciso de ajuda")
                            .font(V8Font.display(44))
                            .tracking(-1.3)
                            .foregroundStyle(V8.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                        Text("Toque pra ligar. O número local já está certo pro país onde você está.")
                            .font(V8Font.text(14))
                            .foregroundStyle(V8.muteDark)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 22)
                    if let kit {
                        bigButtons(kit).padding(.top, 22)
                        lines(kit).padding(.top, 30)
                    } else {
                        Text("O kit de emergência deste país não está no app.")
                            .font(V8Font.text(15))
                            .foregroundStyle(V8.muteDark)
                            .padding(.top, 30)
                    }
                    footnote.padding(.top, 22)
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            BottomFade(color: V8.ink, height: 60)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
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

    // MARK: Topo

    private var header: some View {
        HStack(alignment: .top) {
            V8CornerButton(systemName: "xmark", label: "Fechar", onInk: true) { dismiss() }
            Spacer(minLength: 12)
            V8SpecStack(lines: ["SOS · \(region.countryName)", "funciona sem internet"], color: V8.muteDark, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .padding(.top, 6)
        }
    }

    // MARK: Botões grandes

    private func bigButtons(_ kit: CountryKit) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(kit.primary.prefix(3).enumerated()), id: \.element.id) { index, number in
                SOSBigButton(number: number, tone: index == 0 ? .orange : index == 1 ? .white : .graphite)
            }
        }
    }

    // MARK: Linhas

    @ViewBuilder
    private func lines(_ kit: CountryKit) -> some View {
        let hospitals = HospitalCatalog.bundled.nearest(region: region, to: location, cityId: cityId, cityName: cityName)
        VStack(spacing: 0) {
            insuranceLine
            if let first = hospitals.first {
                SOSLine(key: "Hospital perto", value: first.hospital.name,
                        detail: SOSText.hospitalLine(first.hospital, meters: first.meters, region: region),
                        check: first.hospital.needsCheck) { sheet = .hospitals }
            }
            whereLine
            if !isHome, let consulate = kit.consulate(cityId: cityId, cityName: cityName) {
                SOSLine(key: "Consulado BR", value: consulate.name,
                        detail: [consulate.phone, consulate.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                        check: consulate.needsCheck) { sheet = .consulate }
            }
            if !kit.more.isEmpty {
                SOSLine(key: "Mais números", value: kit.more.prefix(3).map { "\($0.number) \(SOSText.short($0.title))" }.joined(separator: " · "),
                        detail: "toque pra ver todos e ligar", check: kit.more.contains { $0.verificar }) { sheet = .numbers }
            }
            if !kit.phrases.isEmpty {
                SOSLine(key: "Frases", value: kit.phrases.prefix(2).map(\.latin).joined(separator: " · "),
                        detail: kit.phrases.prefix(2).map(\.meaning).joined(separator: " · ") + " · com áudio") { sheet = .phrases }
            }
            if profile.hasHealth {
                SOSLine(key: "Saúde", value: [profile.bloodType, profile.allergies.isEmpty ? "" : "alergia: \(profile.allergies)"]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        detail: "só neste aparelho · toque pra editar") { sheet = .profile }
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
        var detail = [shown?.sub ?? "", shown == nil ? "ligue a localização" : (copied ? "copiado" : "toque pra copiar ou mostrar")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        if shown?.isStale == true { detail = "último conhecido · " + detail }
        return SOSLine(key: "Onde estou", value: value, detail: detail) {
            guard shown != nil else { return }
            showAddress = true
        }
        .contextMenu {
            if let shown {
                Button("Mostrar em tela cheia", systemImage: "arrow.up.left.and.arrow.down.right") { showAddress = true }
                Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = shown.main; copied = true }
            }
        }
    }

    private var footnote: some View {
        Text("Números conferidos em fonte oficial em \(EmergencyKit.bundled.checked.map(SOSText.checkedDate) ?? "—"). Seguro e saúde ficam só neste aparelho: não vão pro iCloud, pro backup nem pro export.")
            .font(V8Font.text(12))
            .foregroundStyle(V8.muteDark)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Peças

/// Botão grande (`.big` do design): número gigante à esquerda, o que é e uma linha de ajuda.
struct SOSBigButton: View {
    enum Tone { case orange, white, graphite }
    var number: EmergencyNumber
    var tone: Tone

    private var fill: Color { tone == .orange ? V8.orange : tone == .white ? V8.white : V8.graphite }
    private var ink: Color { tone == .graphite ? V8.white : V8.ink }

    var body: some View {
        let content = HStack(spacing: 14) {
            numeral.frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(number.badge != nil ? "\(number.title) · \(number.number)" : number.title)
                        .font(V8Font.text(15, weight: .bold))
                        .lineLimit(2)
                    if number.verificar { V8Tag(text: "conferir", style: tone == .graphite ? .orange : .ink) }
                }
                Text(number.telURL == nil ? "\(number.detail) · disque no teclado" : number.detail)
                    .font(V8Font.text(11.5))
                    .opacity(tone == .graphite ? 0.8 : 0.75)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

        if let url = number.telURL {
            Link(destination: url) { content }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("\(number.title), ligar \(number.number)")
                .accessibilityHint("abre o discador")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var numeral: some View {
        if let badge = number.badge {
            Text(badge)
                .font(V8Font.numeral(22))
                .tracking(-0.8)
                .lineSpacing(-2)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        } else {
            Text(number.number)
                .font(V8Font.numeral(number.number.count > 4 ? 26 : 40))
                .tracking(number.number.count > 4 ? -0.6 : -1.6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// Linha (`.ln`): micro-rótulo à esquerda, valor em negrito e detalhe; à direita, o botão laranja de ligar.
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
                HStack(spacing: 12) {
                    Text(key.uppercased())
                        .font(V8Font.mono(9, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(V8.muteDark)
                        .lineLimit(2)
                        .frame(width: 84, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(value).font(V8Font.text(14, weight: .bold)).foregroundStyle(V8.white).lineLimit(1)
                            if check { V8Tag(text: "conferir", style: .orange) }
                        }
                        Text(detail).font(V8Font.text(12)).foregroundStyle(V8.muteDark).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let callURL {
                Link(destination: callURL) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V8.ink)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(V8.orange))
                }
                .accessibilityLabel("Ligar pro seguro")
                .accessibilityHint("abre o discador")
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { Rectangle().fill(V8.white.opacity(0.14)).frame(height: 1) }
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
