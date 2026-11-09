import SwiftData
import SwiftUI

extension TicketImportModel {
    /// Tudo lido com confiança alta: obrigatórios (título e quando; voo e Carteira só pedem o que o tipo pede) com leitura,
    /// nenhum campo em dúvida e dá pra salvar. Aí o "Salvar" fica em destaque, ainda depois da revisão.
    var isAllConfident: Bool {
        guard let draft, canSave, !draft.meta.isEmpty else { return false }
        let required: [TicketField] = (isFlight || isWalletKind) ? [] : [.title, .when]
        guard required.allSatisfy({ draft.meta[$0] != nil }) else { return false }
        return !draft.meta.values.contains { $0.needsReview }
    }
}

/// Conferir (V9): `Form` nativo. Cada campo mostra o valor editável e, embaixo, a confiança com ícone e texto
/// ("lido do texto", "lido da imagem", "conferir · …"). "Salvar" é o único que grava.
struct TicketRevisarView: View {
    @Bindable var model: TicketImportModel
    var close: () -> Void

    @Environment(RegionStore.self) private var store
    @State private var choosing = false
    @State private var saveError: String?

    private var region: Region { store.region }

    var body: some View {
        Form {
            Section {
                summary
            }

            Section("Dados do ingresso") { fieldRows }

            Section("Anexos") {
                HStack {
                    if let attachment = model.draft?.attachment { Label(attachmentLabel(attachment), systemImage: "paperclip") }
                    if model.draft?.qrPayload.isEmpty == false { Label("QR lido", systemImage: "qrcode") }
                    if model.draft?.attachment == nil && model.draft?.qrPayload.isEmpty != false {
                        Text("Nenhum anexo").foregroundStyle(.secondary)
                    }
                }
            }

            if model.isWalletKind {
                walletSection
            } else if model.isFlight {
                flightSection
            } else {
                matchSection
                optionsSection
            }

            Section {
                if let saveError { Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(V9.alert) }
                Button(action: save) {
                    Label(model.isAllConfident ? "Tudo certo · \(saveTitle)" : saveTitle, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .v9Primary()
                .disabled(!model.canSave)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Conferir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar", action: save).disabled(!model.canSave).fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $choosing) {
            TicketPlacePicker(model: model, close: { choosing = false })
        }
    }

    private var saveTitle: String {
        if model.isFlight { return "Salvar voo" }
        return model.isWalletKind ? "Salvar na Carteira" : "Salvar ingresso"
    }

    // MARK: Resumo

    private var summary: some View {
        let read = model.draft?.readCount ?? 0
        let doubtful = model.draft?.meta.values.filter(\.needsReview).count ?? 0
        let ok = model.isAllConfident
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(ok ? "Tudo certo" : (doubtful == 0 ? "Confira antes de salvar" : "\(doubtful) \(doubtful == 1 ? "campo" : "campos") pra conferir"))
                    .font(.headline)
                Text("\(read) \(read == 1 ? "campo lido" : "campos lidos") no aparelho. " + (ok ? "Pode salvar; é só mudar o que estiver errado." : "Os marcados com ⚠ pedem sua atenção."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? V9.accent : V9.alert)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Campos

    @ViewBuilder private var fieldRows: some View {
        let d = model.draft
        field(.supplier, "Fornecedor") {
            TextField("Fornecedor", text: text(\.supplier, .supplier), axis: .vertical).lineLimit(1...3)
        }
        field(.title, "Título") {
            TextField("Nome da experiência", text: text(\.title, .title), axis: .vertical).lineLimit(1...3)
        }
        field(.when, "Quando") {
            DatePicker("Quando", selection: date(\.at, .when), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .environment(\.timeZone, region.timeZone)
                .environment(\.locale, region.locale)
        }
        if !model.isWalletKind && !model.isFlight {
            field(.people, "Pessoas") {
                Stepper(value: integer(\.people, .people), in: 1...12) {
                    Text("\(d?.people ?? 1) \((d?.people ?? 1) == 1 ? "pessoa" : "pessoas")").monospacedDigit()
                }
            }
        }
        ForEach(extraRows, id: \.field) { row in
            field(row.field, row.label) {
                TextField(row.label, text: text(row.path, row.field), axis: .vertical).lineLimit(1...3)
            }
        }
        field(.price, "Pago (\(currencyMark))") {
            TextField("24.000", text: price()).keyboardType(.numberPad).monospacedDigit()
        }
        field(.confirmation, "Confirmação") {
            TextField("Código", text: text(\.confirmation, .confirmation))
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        if !model.isWalletKind && !model.isFlight {
            field(.meeting, "Encontro") {
                TextField("Ponto de encontro", text: text(\.meetingPoint, .meeting), axis: .vertical).lineLimit(1...3)
            }
            field(.cancel, "Cancelamento") { cancelControl }
        }
    }

    /// Local, assento, portão, titular: só aparecem quando o ingresso trouxe algum.
    private var extraRows: [(field: TicketField, label: String, path: WritableKeyPath<TicketDraft, String>)] {
        guard let d = model.draft, !model.isWalletKind else { return [] }
        let all: [(TicketField, String, String, WritableKeyPath<TicketDraft, String>)] = [
            (.venue, "Local", d.venue, \.venue), (.seat, "Assento", d.seat, \.seat),
            (.gate, "Portão", d.gate, \.gate), (.holder, "Titular", d.holder, \.holder),
        ]
        return all.filter { !$0.2.isEmpty }.map { (field: $0.0, label: $0.1, path: $0.3) }
    }

    /// Rótulo, controle editável e a linha de confiança (ícone + texto: nunca só cor).
    private func field<Control: View>(_ target: TicketField, _ label: String, @ViewBuilder control: () -> Control) -> some View {
        let meta = model.draft?.meta[target]
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            control()
            if let meta { confidence(meta) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func confidence(_ meta: FieldMeta) -> some View {
        if meta.needsReview {
            Label("Conferir · \(originText(meta))", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(V9.alert)
        } else {
            Label(originText(meta).sentenceCased, systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// "lido do texto" vira "lido da imagem" quando a fonte foi foto/print.
    private func originText(_ meta: FieldMeta) -> String {
        if meta.origin == "lido do texto", case .pending(_, let ext)? = model.draft?.attachment, ext != "pdf" {
            return "lido da imagem"
        }
        return meta.origin
    }

    /// "¥" quando a moeda do ingresso é a da região; senão o código ("USD").
    private var currencyMark: String {
        guard let currency = model.draft?.currency, currency != region.currency else { return region.currencySymbol }
        return currency
    }

    private func attachmentLabel(_ attachment: TicketDraft.Attachment) -> String {
        switch attachment {
        case .pending(_, let ext): ext == "pdf" ? "PDF" : "Foto"
        case .stored(let name): name.hasSuffix(".pdf") ? "PDF" : "Foto"
        }
    }

    @ViewBuilder private var cancelControl: some View {
        if let until = model.draft?.cancelUntil {
            DatePicker("Grátis até", selection: date(\.cancelUntil, .cancel, fallback: until), displayedComponents: [.date, .hourAndMinute])
                .environment(\.timeZone, region.timeZone)
                .environment(\.locale, region.locale)
            Button("Sem cancelamento grátis", role: .destructive) { model.edit(.cancel) { $0.cancelUntil = nil } }
                .font(.subheadline)
        } else {
            Text("Sem cancelamento grátis")
            Button("Tem cancelamento grátis") { model.edit(.cancel) { $0.cancelUntil = $0.at } }
                .font(.subheadline)
        }
    }

    // MARK: Bindings

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

    /// Valor inteiro: "24.000" → 24000 (separador de milhar não conta).
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

    // MARK: Destino

    /// Trechos lidos: número, rota e partida no fuso do aeroporto.
    private var flightSection: some View {
        let segments = FlightFromTicket.segments(from: model.draft ?? TicketDraft(at: AppClock.now), region: region)
        return Section {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let zone = FlightFormat.zone(segment.from, fallback: region.timeZone)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(segment.number) · \(segment.from) → \(segment.to)").font(.body.weight(.semibold))
                    Text("\(FlightFormat.day(segment.departs, zone: zone)) · \(FlightFormat.time(segment.departs, zone: zone))")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if segments.isEmpty {
                Text("Nenhum trecho lido. Confira o número do voo e os aeroportos antes de salvar.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Vai pra Voos")
        } footer: {
            Text("Chegada, portão e terminal vêm do status ao vivo.")
        }
    }

    private var matchSection: some View {
        let draft = model.draft
        let match = model.chosenMatch
        let title = match?.name ?? (draft?.title.isEmpty == false ? draft?.title ?? "" : "Lugar novo")
        let subtitle: String = match.map {
            "Já no board · \($0.percent)% · vira âncora de \(KindLines.weekdayDay(draft?.at ?? .now, region: region))"
        } ?? "Criar novo · vai pra Must do"
        return Section("Vincular a") {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: match == nil ? "plus.circle" : "mappin.circle.fill").foregroundStyle(V9.accent)
            }
            .accessibilityElement(children: .combine)
            Button("Outro lugar do board") { choosing = true }
            Button("Criar lugar novo") { model.target = .new }
        }
    }

    /// Exceção de orçamento e aviso "saia às" (lembrete local; sem Live Activity).
    private var optionsSection: some View {
        let budget = Binding(get: { model.draft?.budgetException ?? false },
                             set: { value in model.draft?.budgetException = value })
        let remind = Binding(get: { model.draft?.remindLeave ?? false },
                             set: { value in model.draft?.remindLeave = value })
        let price = model.draft?.price.map { region.money($0) } ?? "—"
        return Section("Opções") {
            Toggle(isOn: budget) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vale a exceção de orçamento")
                    Text("\(price) fica fora da meta do dia").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: remind) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avisar \"saia às\"")
                    Text(leaveText).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .tint(V9.accent)
    }

    /// Hora de sair: a visita menos 40 min de deslocamento (estimativa), no fuso da região.
    private var leaveAt: Date {
        RoutesService.leaveAt(model.draft?.at ?? AppClock.now, travelMinutes: 40)
    }

    private var leaveText: String {
        "Saia às \(FlightFormat.time(leaveAt, zone: region.timeZone)) · estimativa de 40 min"
    }

    /// Trem e QR de entrada: vão pra Carteira, não pra um lugar do board.
    private var walletSection: some View {
        let kind = WalletFromTicket.kind(for: model.draft?.kind ?? .other) ?? .other
        return Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vai pra Carteira").font(.body.weight(.semibold))
                    Text("\(kind.label) · não vira lugar do board").font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: kind == .entryQR ? "qrcode" : "tram.fill").foregroundStyle(V9.accent)
            }
            .accessibilityElement(children: .combine)
        }
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

private extension String {
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
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
        NavigationStack {
            List(filtered) { place in
                Button {
                    model.target = .place(place.id)
                    close()
                } label: {
                    V9Row(title: place.name, detail: [place.list?.displayName, place.area].compactMap { $0 }.joined(separator: " · "))
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Buscar no board")
            .navigationTitle("Outro lugar do board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: close) } }
        }
    }
}
