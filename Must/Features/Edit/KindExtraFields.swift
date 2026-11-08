import SwiftUI

/// Editar › campos do tipo da lista (photo / art / sport) — o caminho "manual" do prompt 13.
struct KindExtraFields: View {
    var kind: ListKind
    @Binding var extra: PlaceExtra
    var region: Region

    var body: some View {
        switch kind {
        case .photo: photo
        case .art: art
        case .sport: sport
        case .experience: experience
        case .place: EmptyView()
        }
    }

    // MARK: photo

    private var photoSpot: Binding<PhotoSpot> {
        Binding { extra.photo ?? PhotoSpot() } set: { extra.photo = $0 }
    }

    private var photo: some View {
        VStack(alignment: .leading, spacing: 22) {
            field("eixo · pra onde a câmera aponta (graus, 0 = norte)") {
                HStack {
                    TextField("248", text: number(photoSpot.facing)).font(V8Font.mono(17)).keyboardType(.numberPad)
                    if let f = photoSpot.wrappedValue.facing { Text(SunService.cardinal(f)).font(V8Font.mono(14)).foregroundStyle(Color.must.secondary) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("melhor luz", color: V8.mute)
                FlowLayout(spacing: 8) {
                    ForEach(LightKind.allCases) { l in
                        let on = photoSpot.wrappedValue.bestLight.contains(l)
                        Button {
                            var spot = photoSpot.wrappedValue
                            if on { spot.bestLight.removeAll { $0 == l } } else { spot.bestLight.append(l) }
                            photoSpot.wrappedValue = spot
                        } label: { Pill(l.label, isOn: on) }
                        .buttonStyle(MustPressStyle())
                    }
                }
            }
            field("equipamento") { TextField("35 mm · Portra 400", text: text(photoSpot.gear)).font(V8Font.text(17)) }
            field("lotação") { TextField("lotado 16h+ sáb", text: text(photoSpot.crowdNote)).font(V8Font.text(17)) }
            toggle("Tripé permitido", isOn: Binding { photoSpot.wrappedValue.tripodAllowed ?? false } set: { photoSpot.wrappedValue.tripodAllowed = $0 })
        }
    }

    // MARK: art

    private var artEvent: Binding<ArtEvent> {
        Binding { extra.art ?? ArtEvent() } set: { extra.art = $0 }
    }

    private var art: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                field("inteira (\(region.currencySymbol))") { TextField("0", text: number(artEvent.priceAdult)).font(V8Font.mono(17)).keyboardType(.numberPad) }
                field("estudante") { TextField("—", text: number(artEvent.priceStudent)).font(V8Font.mono(17)).keyboardType(.numberPad) }
            }
            field("grátis quando") { TextField("1ª quinta do mês", text: text(artEvent.freeNote)).font(V8Font.text(17)) }
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("temporada até", color: V8.mute)
                HStack {
                    if let until = artEvent.wrappedValue.runsUntil {
                        DatePicker("", selection: Binding { ArtEvent.localDay(until, calendar: region.calendar) } set: { artEvent.wrappedValue.runsUntil = $0 },
                                   displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.timeZone, region.timeZone)
                            .environment(\.locale, region.locale)
                        Spacer()
                        Button { artEvent.wrappedValue.runsUntil = nil } label: { Pill("sem data") }.buttonStyle(MustPressStyle())
                    } else {
                        Button { artEvent.wrappedValue.runsUntil = region.calendar.startOfDay(for: AppClock.now).addingTimeInterval(30 * 86_400) } label: {
                            Pill("marcar o fim da temporada", icon: .calendario)
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
            }
            HStack(spacing: 12) {
                field("última entrada (min antes)") { TextField("30", text: int(artEvent.lastEntryMinutes)).font(V8Font.mono(17)).keyboardType(.numberPad) }
                field("duração (min)") { TextField("90", text: int(artEvent.durationMinutes)).font(V8Font.mono(17)).keyboardType(.numberPad) }
            }
            field("estilo (separado por vírgula)") {
                TextField("fotografia, pb, rua", text: Binding { artEvent.wrappedValue.style.joined(separator: ", ") } set: {
                    artEvent.wrappedValue.style = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                })
                .font(V8Font.text(17))
            }
            field("link do ingresso") {
                TextField("https://…", text: Binding { artEvent.wrappedValue.ticketURL?.absoluteString ?? "" } set: {
                    artEvent.wrappedValue.ticketURL = URL(string: $0.trimmingCharacters(in: .whitespaces)).flatMap { $0.scheme == nil ? nil : $0 }
                })
                .font(V8Font.text(15)).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            toggle("Precisa reservar", isOn: Binding { artEvent.wrappedValue.needsBooking } set: { artEvent.wrappedValue.needsBooking = $0 })
            toggle("Pode fotografar", isOn: Binding { artEvent.wrappedValue.photographyAllowed ?? false } set: { artEvent.wrappedValue.photographyAllowed = $0 })
        }
    }

    // MARK: sport

    private var sportSpot: Binding<SportSpot> {
        Binding { extra.sport ?? SportSpot() } set: { extra.sport = $0 }
    }

    private var sport: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("atividade", color: V8.mute)
                FlowLayout(spacing: 8) {
                    ForEach(SportActivity.allCases) { a in
                        Button { sportSpot.wrappedValue.activity = a } label: { Pill(a.label, isOn: sportSpot.wrappedValue.activity == a) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }
            HStack(spacing: 12) {
                field("distância (km)") { TextField("7", text: number(sportSpot.distanceKm, decimal: true)).font(V8Font.mono(17)).keyboardType(.decimalPad) }
                field("subida (m)") { TextField("34", text: int(sportSpot.elevationM)).font(V8Font.mono(17)).keyboardType(.numberPad) }
            }
            field("piso") { TextField("asfalto e ciclovia", text: text(sportSpot.surface)).font(V8Font.text(17)) }
            field("percurso") { TextField("começa na Igreja, água no km 3…", text: text(sportSpot.routeNote)).font(V8Font.text(15)) }
            HStack(spacing: 12) {
                field("temp. máx (padrão 28°)") { TextField("28", text: int(sportSpot.preferredTempMax)).font(V8Font.mono(17)).keyboardType(.numberPad) }
                field("UV máx (padrão 6)") { TextField("6", text: int(sportSpot.preferredUVMax)).font(V8Font.mono(17)).keyboardType(.numberPad) }
            }
            toggle("Circuito (volta fechada)", isOn: Binding { sportSpot.wrappedValue.loop } set: { sportSpot.wrappedValue.loop = $0 })
        }
    }

    // MARK: experience

    private var experienceInfo: Binding<ExperienceInfo> {
        Binding { extra.experience ?? ExperienceInfo() } set: { extra.experience = $0 }
    }

    /// Fornecedor, link, duração, preço, ponto de encontro. Sessões entram pelo ingresso (ou pelo board).
    private var experience: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("fornecedor", color: V8.mute)
                FlowLayout(spacing: 8) {
                    ForEach(ExperienceSupplier.allCases) { s in
                        Button { experienceInfo.wrappedValue.supplier = s } label: { Pill(s.label, isOn: experienceInfo.wrappedValue.supplier == s) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }
            field("link do produto (colar)") {
                TextField("https://www.viator.com/…", text: urlText(experienceInfo.url)).font(V8Font.text(15))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            HStack(spacing: 12) {
                field("duração (min)") { TextField("180", text: int(experienceInfo.durationMinutes)).font(V8Font.mono(17)).keyboardType(.numberPad) }
                field("grupo até") { TextField("8", text: int(experienceInfo.groupMax)).font(V8Font.mono(17)).keyboardType(.numberPad) }
            }
            HStack(spacing: 12) {
                field("a partir de (\(region.currencySymbol))") { TextField("0", text: number(experienceInfo.priceFrom)).font(V8Font.mono(17)).keyboardType(.numberPad) }
                field("cancela grátis (h antes)") { TextField("24", text: int(experienceInfo.freeCancellationHours)).font(V8Font.mono(17)).keyboardType(.numberPad) }
            }
            field("ponto de encontro") { TextField("Portão 1 do mercado externo", text: text(experienceInfo.meetingPoint)).font(V8Font.text(17)) }
            field("idiomas") {
                TextField("inglês, japonês", text: Binding { experienceInfo.wrappedValue.languages.joined(separator: ", ") } set: {
                    experienceInfo.wrappedValue.languages = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                })
                .font(V8Font.text(17))
            }
        }
    }

    // MARK: Peças

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        CutBox(label: label) { content() }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn).font(V8Font.text(16)).tint(V8.orange)
    }

    private func text(_ b: Binding<String?>) -> Binding<String> {
        Binding { b.wrappedValue ?? "" } set: { b.wrappedValue = $0.isEmpty ? nil : $0 }
    }

    /// Preço: "1.400" é milhar. Distância (`decimal`): "7,5" e "7.5" são sete e meio.
    private func number(_ b: Binding<Double?>, decimal: Bool = false) -> Binding<String> {
        Binding {
            // `Int(_:)` de 1e19 ou de NaN derruba o app: o campo relê o valor a cada tecla (rodada 23 · G).
            guard let value = NumberInput.finite(b.wrappedValue) else { return "" }
            return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
        } set: {
            let s = decimal ? $0.replacingOccurrences(of: ",", with: ".")
                : $0.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            b.wrappedValue = NumberInput.double(s)
        }
    }

    private func urlText(_ b: Binding<URL?>) -> Binding<String> {
        Binding { b.wrappedValue?.absoluteString ?? "" } set: { b.wrappedValue = $0.isEmpty ? nil : URL(string: $0.trimmingCharacters(in: .whitespaces)) }
    }

    private func int(_ b: Binding<Int?>) -> Binding<String> {
        Binding { b.wrappedValue.map(String.init) ?? "" } set: { b.wrappedValue = NumberInput.int($0) }
    }
}
