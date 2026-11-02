import SwiftData
import SwiftUI

/// TicketRevisar (`design/screens/TicketRevisar.png`): cada campo com a confiança e a origem, editável ali mesmo;
/// "Vincular a" com o lugar do board; exceção de orçamento; "Salvar ingresso" (só aí grava).
struct TicketRevisarView: View {
    @Bindable var model: TicketImportModel
    var close: () -> Void

    @Environment(RegionStore.self) private var store
    @State private var choosing = false
    @State private var saveError: String?

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
                } else {
                    Micro("vincular a").padding(.top, 26)
                    matchCard.padding(.top, 10)
                    HStack(spacing: 10) {
                        GhostButton("Outro lugar do board") { choosing = true }
                        GhostButton("Criar novo") { model.target = .new }
                    }
                    .padding(.top, 12)

                    budgetCard.padding(.top, 18)
                }

                if let note = model.notYetMessage {
                    Text(note).font(.must.archivo(14, .semibold)).foregroundStyle(Color(hex: 0x8A5A00))
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFFF3D6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 16)
                }
                if let saveError { Text(saveError).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D)).padding(.top, 12) }

                PrimaryButton(model.isWalletKind ? "Salvar na Carteira" : "Salvar ingresso", icon: .ok, iconTrailing: true) { save() }
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
            row("Fornecedor", .supplier) {
                TextField("—", text: text(\.supplier, .supplier), axis: .vertical).lineLimit(1...3).multilineTextAlignment(.trailing)
            }
            RowDivider()
            row("Título", .title) {
                TextField("nome da experiência", text: text(\.title, .title), axis: .vertical).lineLimit(1...3).multilineTextAlignment(.trailing)
            }
            RowDivider()
            row("Quando", .when, stacked: true) {
                DatePicker("Quando", selection: date(\.at, .when), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)
            }
            if !model.isWalletKind {
                RowDivider()
                row("Pessoas", .people) {
                    Stepper(value: integer(\.people, .people), in: 1...12) {
                        Text("\(d?.people ?? 1)").font(.must.mono(15))
                    }
                    .fixedSize()
                }
            }
            RowDivider()
            row("Pago (\(currencyMark))", .price) {
                TextField("24.000", text: price()).keyboardType(.numberPad).font(.must.mono(15, .semibold))
                    .multilineTextAlignment(.trailing)
            }
            RowDivider()
            row("Confirmação", .confirmation) {
                TextField("código", text: text(\.confirmation, .confirmation)).font(.must.mono(15, .semibold)).lineLimit(1)
                    .textInputAutocapitalization(.characters).multilineTextAlignment(.trailing)
            }
            if !model.isWalletKind {
                RowDivider()
                row("Encontro", .meeting) {
                    TextField("ponto de encontro", text: text(\.meetingPoint, .meeting), axis: .vertical).lineLimit(1...3).multilineTextAlignment(.trailing)
                }
                RowDivider()
                row("Cancelamento", .cancel, stacked: true) {
                    cancelControl
                }
            }
            RowDivider()
            HStack(spacing: 12) {
                Text("Anexos").font(.must.archivo(14)).foregroundStyle(Color.must.secondary).frame(width: 104, alignment: .leading)
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

    /// "¥" quando a moeda do ingresso é a da região; senão o código ("USD").
    private var currencyMark: String {
        guard let currency = model.draft?.currency, currency != region.currency else { return region.currencySymbol }
        return currency
    }

    /// Uma linha da conferência: rótulo e origem à esquerda, controle à direita. `stacked` põe o controle embaixo
    /// (datas e cancelamento são largos demais pra dividir a linha).
    private func row<Control: View>(_ label: String, _ field: TicketField, stacked: Bool = false,
                                    @ViewBuilder control: () -> Control) -> some View {
        let meta = model.draft?.meta[field]
        let labelColumn = VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
            if let origin = meta?.origin {
                Text(origin).font(.must.mono(11)).foregroundStyle(Color.must.secondary)
            }
        }
        let indicator = Circle().fill(dot(meta)).frame(width: 8, height: 8)
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        labelColumn
                        Spacer(minLength: 0)
                        indicator
                    }
                    control()
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    labelColumn.frame(width: 96, alignment: .leading)
                    control()
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(1)
                    indicator
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
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
        Binding(get: { model.draft?.price.map { String(Int($0.rounded())) } ?? "" },
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

    private var budgetCard: some View {
        let on = Binding(get: { model.draft?.budgetException ?? false },
                         set: { value in model.draft?.budgetException = value })
        let price = model.draft?.price.map { region.money($0) } ?? "—"
        return Toggle(isOn: on) {
            FormRow("Vale a exceção de orçamento", subtitle: "\(price) fica fora da meta do dia")
        }
        .toggleStyle(.must)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.must.line))
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
        do {
            try model.save()
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
