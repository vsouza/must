import SwiftData
import SwiftUI

/// TicketRevisar (`design/screens/TicketRevisar.png`): linhas compactas "rótulo · ● valor · origem"; tocar numa linha
/// abre o controle logo abaixo (um de cada vez). "Vincular a" com o lugar do board; exceção de orçamento e
/// "Avisar saia às" (lembrete local). "Salvar ingresso" é o único que grava.
struct TicketRevisarView: View {
    @Bindable var model: TicketImportModel
    var close: () -> Void

    @Environment(RegionStore.self) private var store
    @State private var choosing = false
    @State private var saveError: String?
    /// Campo com o controle aberto (nil = todos fechados).
    @State private var openField: TicketField?

    private var region: Region { store.region }
    private var amber: Color { Color(hex: 0xFFB020) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconButton(.voltar, style: .gray, label: "Voltar pra entrada") { model.step = .entrada }
                    Spacer()
                    Micro("ingresso · 3 de 3")
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, 8)

                Text("Conferir").mustTitle().padding(.top, 22)
                legend.padding(.top, 6)

                fieldsCard.padding(.top, 20)

                if model.isWalletKind {
                    walletCard.padding(.top, 26)
                } else if model.isFlight {
                    Micro("voo · vai pra Voos").padding(.top, 26)
                    flightCard.padding(.top, 10)
                } else {
                    Micro("vincular a").padding(.top, 26)
                    matchCard.padding(.top, 10)
                    HStack(spacing: 10) {
                        GhostButton("Outro lugar do board") { choosing = true }
                        GhostButton("Criar novo") { model.target = .new }
                    }
                    .padding(.top, 12)

                    optionsCard.padding(.top, 18)
                }

                if let saveError { Text(saveError).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D)).padding(.top, 12) }

                PrimaryButton(saveTitle, icon: .ok, iconTrailing: true) { save() }
                    .disabled(!model.canSave)
                    .padding(.top, 18)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
        .sheet(isPresented: $choosing) {
            TicketPlacePicker(model: model, close: { choosing = false })
        }
    }

    private var saveTitle: String {
        if model.isFlight { return "Salvar voo" }
        return model.isWalletKind ? "Salvar na Carteira" : "Salvar ingresso"
    }

    /// Trechos lidos: número, rota e partida no fuso do aeroporto. Chegada, portão e terminal vêm do status ao vivo.
    private var flightCard: some View {
        let segments = FlightFromTicket.segments(from: model.draft ?? TicketDraft(at: AppClock.now), region: region)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 { RowDivider() }
                HStack(alignment: .firstTextBaseline) {
                    Text(segment.number).font(.must.mono(15, .semibold))
                    Text("\(segment.from) → \(segment.to)").font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
                    Spacer(minLength: 8)
                    Text("\(FlightFormat.day(segment.departs, zone: FlightFormat.zone(segment.from, fallback: region.timeZone))) · \(FlightFormat.time(segment.departs, zone: FlightFormat.zone(segment.from, fallback: region.timeZone)))")
                        .font(.must.mono(13)).foregroundStyle(Color.must.secondary)
                }
            }
            if segments.isEmpty {
                Text("Nenhum trecho lido. Confira o número do voo e os aeroportos antes de salvar.").font(.must.meta).foregroundStyle(Color.must.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Legenda que quebra linha (um HStack não quebra e empurra a tela pra fora).
    private var legend: some View {
        let muted = Color.must.secondary
        return (Text("toque em qualquer campo pra corrigir · ").foregroundStyle(muted)
            + Text("●").foregroundStyle(Color.must.green)
            + Text(" certo · ").foregroundStyle(muted)
            + Text("●").foregroundStyle(amber)
            + Text(" conferir").foregroundStyle(muted))
            .mustSerif(17)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Campos

    private var fieldsCard: some View {
        let d = model.draft
        return VStack(spacing: 0) {
            field(.supplier, "Fornecedor", value: nonEmpty(d?.supplier)) {
                editorBox { TextField("—", text: text(\.supplier, .supplier), axis: .vertical).lineLimit(1...3) }
            }
            RowDivider()
            field(.title, "Título", value: nonEmpty(d?.title, "—")) {
                editorBox { TextField("nome da experiência", text: text(\.title, .title), axis: .vertical).lineLimit(1...3) }
            }
            RowDivider()
            field(.when, "Quando", value: whenText, mono: true) {
                editorBox {
                    DatePicker("Quando", selection: date(\.at, .when), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !model.isWalletKind && !model.isFlight {
                RowDivider()
                field(.people, "Pessoas", value: "\(d?.people ?? 1)", mono: true) {
                    editorBox {
                        Stepper(value: integer(\.people, .people), in: 1...12) {
                            Text("\(d?.people ?? 1) \((d?.people ?? 1) == 1 ? "pessoa" : "pessoas")").font(.must.archivo(16))
                        }
                    }
                }
            }
            RowDivider()
            field(.price, "Pago", value: d?.price.map { region.money($0) } ?? "—", mono: true) {
                editorBox {
                    TextField("24.000 (\(currencyMark))", text: price()).keyboardType(.numberPad).font(.must.mono(16, .semibold))
                }
            }
            RowDivider()
            field(.confirmation, "Confirmação", value: nonEmpty(d?.confirmation), mono: true) {
                editorBox {
                    TextField("código", text: text(\.confirmation, .confirmation))
                        .font(.must.mono(16, .semibold))
                        .textInputAutocapitalization(.characters)
                }
            }
            if !model.isWalletKind && !model.isFlight {
                RowDivider()
                field(.meeting, "Encontro", value: nonEmpty(d?.meetingPoint)) {
                    editorBox { TextField("ponto de encontro", text: text(\.meetingPoint, .meeting), axis: .vertical).lineLimit(1...3) }
                }
                RowDivider()
                field(.cancel, "Cancelamento", value: cancelText) {
                    editorBox { cancelControl }
                }
            }
            RowDivider()
            HStack(spacing: 12) {
                Text("Anexos").font(.must.archivo(14)).foregroundStyle(Color.must.secondary).frame(width: 96, alignment: .leading)
                Spacer(minLength: 0)
                if let attachment = d?.attachment {
                    Pill(attachmentLabel(attachment))
                }
                if d?.qrPayload.isEmpty == false { Pill("QR") }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Linha compacta: rótulo · ● valor · origem. Tocar abre (ou fecha) o controle logo abaixo; abrir outro fecha este.
    private func field<Editor: View>(_ target: TicketField, _ label: String, value: String, mono: Bool = false,
                                     @ViewBuilder editor: () -> Editor) -> some View {
        let meta = model.draft?.meta[target]
        let isOpen = openField == target
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { openField = isOpen ? nil : target }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                        .frame(width: 96, alignment: .leading)
                    Spacer(minLength: 0)
                    Circle().fill(dot(meta)).frame(width: 8, height: 8)
                    Text(value)
                        .font(mono ? .must.mono(15, .semibold) : .must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                    if let origin = meta?.origin {
                        Text(origin).font(.must.mono(11)).foregroundStyle(Color.must.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                editor()
                    .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }

    /// Caixa do controle aberto (texto, data, passo, preço).
    private func editorBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.must.archivo(16))
            .foregroundStyle(Color.must.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.must.line))
    }

    private func nonEmpty(_ value: String?, _ placeholder: String = "—") -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return placeholder }
        return value
    }

    private var whenText: String {
        let at = model.draft?.at ?? AppClock.now
        return "\(FlightFormat.day(at, zone: region.timeZone)) · \(FlightFormat.time(at, zone: region.timeZone))"
    }

    private var cancelText: String {
        guard let until = model.draft?.cancelUntil else { return "sem cancelamento grátis" }
        return "grátis até \(FlightFormat.day(until, zone: region.timeZone)) · \(FlightFormat.time(until, zone: region.timeZone))"
    }

    /// "¥" quando a moeda do ingresso é a da região; senão o código ("USD").
    private var currencyMark: String {
        guard let currency = model.draft?.currency, currency != region.currency else { return region.currencySymbol }
        return currency
    }

    private func dot(_ meta: FieldMeta?) -> Color {
        guard let meta else { return .clear }
        return meta.needsReview ? amber : Color.must.green
    }

    private func attachmentLabel(_ attachment: TicketDraft.Attachment) -> String {
        switch attachment {
        case .pending(_, let ext): ext == "pdf" ? "PDF" : "foto"
        case .stored(let name): name.hasSuffix(".pdf") ? "PDF" : "foto"
        }
    }

    @ViewBuilder private var cancelControl: some View {
        if let until = model.draft?.cancelUntil {
            HStack(spacing: 10) {
                DatePicker("Até", selection: date(\.cancelUntil, .cancel, fallback: until), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.timeZone, region.timeZone)
                Button { model.edit(.cancel) { $0.cancelUntil = nil } } label: { Pill("sem", icon: .remover) }
                    .buttonStyle(MustPressStyle())
            }
        } else {
            Button { model.edit(.cancel) { $0.cancelUntil = $0.at } } label: { Pill("sem cancelamento grátis") }
                .buttonStyle(MustPressStyle())
        }
    }

    /// Binding de texto que marca o campo como "à mão" (100%) ao ser editado.
    private func text(_ path: WritableKeyPath<TicketDraft, String>, _ field: TicketField) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: path] ?? "" },
                set: { value in model.edit(field) { $0[keyPath: path] = value } })
    }

    private func integer(_ path: WritableKeyPath<TicketDraft, Int>, _ field: TicketField) -> Binding<Int> {
        Binding(get: { model.draft?[keyPath: path] ?? 1 },
                set: { value in model.edit(field) { $0[keyPath: path] = value } })
    }

    private func date(_ path: WritableKeyPath<TicketDraft, Date>, _ field: TicketField) -> Binding<Date> {
        Binding(get: { model.draft?[keyPath: path] ?? AppClock.now },
                set: { value in model.edit(field) { $0[keyPath: path] = Self.minute(value, region: region) } })
    }

    private func date(_ path: WritableKeyPath<TicketDraft, Date?>, _ field: TicketField, fallback: Date) -> Binding<Date> {
        Binding(get: { model.draft?[keyPath: path] ?? fallback },
                set: { value in model.edit(field) { $0[keyPath: path] = Self.minute(value, region: region) } })
    }

    /// Valor em reais/ienes inteiro: "24.000" → 24000 (separador de milhar não conta).
    private func price() -> Binding<String> {
        Binding(get: { NumberInput.intText(model.draft?.price) },
                set: { value in
                    let amount = TicketMoney.parse(value)
                    model.edit(.price) { $0.price = value.isEmpty ? nil : amount }
                })
    }

    /// Minuto inteiro: o board guarda ISO sem fração de segundo.
    private static func minute(_ date: Date, region: Region) -> Date {
        let c = region.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return region.calendar.date(from: c) ?? date
    }

    // MARK: Vincular

    private var matchCard: some View {
        let draft = model.draft
        let match = model.chosenMatch
        let title = match?.name ?? (draft?.title.isEmpty == false ? draft?.title ?? "" : "Lugar novo")
        let subtitle: String = {
            if let match {
                return "já no board · \(match.percent)% · vira âncora de \(KindLines.weekdayDay(draft?.at ?? .now, region: region))"
            }
            return "criar novo · vai pra Must do"
        }()
        return HStack(spacing: 14) {
            MustIconView(.ok, size: 16)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.must.ink, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.blueText).lineLimit(2)
                Text(subtitle).font(.must.archivo(13)).foregroundStyle(Color.must.blueText.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0xD6E8FF), Color(hex: 0x9FD6FF)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Exceção de orçamento e aviso "saia às" (lembrete local; sem Live Activity).
    private var optionsCard: some View {
        let budget = Binding(get: { model.draft?.budgetException ?? false },
                             set: { value in model.draft?.budgetException = value })
        let remind = Binding(get: { model.draft?.remindLeave ?? false },
                             set: { value in model.draft?.remindLeave = value })
        let price = model.draft?.price.map { region.money($0) } ?? "—"
        return VStack(spacing: 0) {
            Toggle(isOn: budget) {
                FormRow("Vale a exceção de orçamento", subtitle: "\(price) fica fora da meta do dia")
            }
            .toggleStyle(.must)
            .padding(16)
            RowDivider()
            Toggle(isOn: remind) {
                FormRow("Avisar \"saia às\"", subtitle: leaveText)
            }
            .toggleStyle(.must)
            .padding(16)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.must.line))
    }

    /// Hora de sair: a visita menos 40 min de deslocamento (estimativa), no fuso da região.
    private var leaveAt: Date {
        RoutesService.leaveAt(model.draft?.at ?? AppClock.now, travelMinutes: 40)
    }

    private var leaveText: String {
        "saia às \(FlightFormat.time(leaveAt, zone: region.timeZone)) · estimativa de 40 min"
    }

    /// Trem e QR de entrada: vão pra Carteira, não pra um lugar do board.
    private var walletCard: some View {
        let kind = WalletFromTicket.kind(for: model.draft?.kind ?? .other) ?? .other
        return HStack(spacing: 14) {
            MustIconView(kind == .entryQR ? .colarLink : .shinkansenTrem, size: 16)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.must.ink, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("vai pra Carteira").font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
                Text("\(kind.label) · não vira lugar do board").font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.must.line))
    }

    private func save() {
        let remind = model.draft?.remindLeave == true && !model.isFlight && !model.isWalletKind
        let title = model.draft?.title ?? ""
        let leave = leaveAt
        do {
            try model.save()
            if remind {
                Task { _ = await TicketLeaveReminder.schedule(title: title, leaveAt: leave) }
            }
            close()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// "Outro lugar do board": lista do board com busca. Escolher põe o ingresso nesse lugar.
private struct TicketPlacePicker: View {
    @Bindable var model: TicketImportModel
    var close: () -> Void

    @Query(sort: \Place.name) private var places: [Place]
    @State private var query = ""

    private var filtered: [Place] {
        let key = query.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return places }
        return places.filter { PlaceMatcher.similar($0.name, key) || $0.name.localizedCaseInsensitiveContains(key) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHandle().frame(maxWidth: .infinity)
                Text("Outro lugar do board").mustTitle()
                TextField("buscar no board", text: $query)
                    .font(.must.archivo(16))
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Color.must.surface, in: Capsule())
                VStack(spacing: 0) {
                    ForEach(filtered) { place in
                        RowDivider()
                        Button {
                            model.target = .place(place.id)
                            close()
                        } label: {
                            FormRow(place.name, subtitle: [place.list?.displayName, place.area].compactMap { $0 }.joined(separator: " · ")) {
                                EmptyView()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
    }
}
