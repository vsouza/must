import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Adicionar ou editar um item da Carteira à mão. Os campos seguem o tipo. Só grava no "Salvar": um arquivo copiado
/// nesta edição sai do aparelho se você cancelar (como no `TicketEditor`).
struct WalletEditor: View {
    /// Item existente (nil = novo).
    var item: WalletItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store

    @State private var kind: WalletKind = .other
    @State private var name = ""
    @State private var nameLocal = ""
    @State private var detail = ""
    @State private var coverage = ""
    @State private var balanceText = ""
    @State private var lowText = ""
    @State private var hasFrom = false
    @State private var from = AppClock.now
    @State private var hasUntil = false
    @State private var until = AppClock.now
    @State private var qrText = ""
    @State private var attachmentName: String?
    /// Arquivo copiado nesta edição: se você cancelar, ele é apagado.
    @State private var fresh: String?
    @State private var opensWallet = false
    @State private var link = ""
    @State private var notes = ""
    @State private var picking = false
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    @State private var saved = false
    @State private var loaded = false

    private var region: Region { store.region }
    private var symbol: String { region.currencySymbol }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(WalletKind.allCases) { option in Text(option.label).tag(option) }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    field("Nome") { TextField("Suica", text: $name) }
                    field("Nome local (opcional)") { TextField("como está escrito no cartão", text: $nameLocal) }
                    field("Linha de apoio (opcional)") { TextField("onde vale, de onde vem", text: $detail) }
                    if kind == .railPass {
                        field("Cobre") { TextField("Tóquio → Kyoto → Tóquio", text: $coverage) }
                    }
                }
                if kind == .transitCard {
                    Section {
                        field("Saldo que você anota (\(symbol))") { TextField("3240", text: $balanceText).keyboardType(.numberPad) }
                        field("Avisar pra recarregar abaixo de (\(symbol))") { TextField("1000", text: $lowText).keyboardType(.numberPad) }
                    }
                }
                if kind == .transitCard || kind == .creditCard {
                    Section {
                        Toggle(isOn: $opensWallet) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Abrir no Wallet")
                                Text("abre o app Wallet; não escolhe um passe").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if kind != .transitCard && kind != .creditCard && kind != .entryQR {
                    validitySection
                }
                if kind == .entryQR || kind == .railPass {
                    Section {
                        field("Texto do QR (colar, ou ler da foto)") { TextField("texto que o leitor lê", text: $qrText) }
                    }
                }
                attachmentSection
                Section {
                    if kind == .esim {
                        field("Instruções do eSIM") { TextField("como instalar e ativar", text: $notes, axis: .vertical).lineLimit(2...8) }
                    } else {
                        field("Observação (opcional)") { TextField("", text: $notes, axis: .vertical).lineLimit(1...4) }
                    }
                    field("Link (opcional)") {
                        TextField("https://", text: $link).keyboardType(.URL).textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("Passaporte, seguro e QR ficam só neste aparelho: nada vai pro export do board.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(item == nil ? "Novo item" : "Editar item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save).fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .v9Screen(grouped: true)
        }
        .onAppear(perform: load)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image]) { result in
            attach(result)
        }
        .onChange(of: photo) { _, pick in
            guard let pick else { return }
            Task {
                if let data = try? await pick.loadTransferable(type: Data.self) {
                    keep(data, ext: TicketReader.imageExtension(for: data))
                } else {
                    error = "Não consegui ler essa foto."
                }
                photo = nil
            }
        }
        .onDisappear {
            // Cancelou depois de anexar: o arquivo novo não fica órfão.
            if !saved, let fresh { TicketFiles.remove(fresh) }
        }
    }

    // MARK: Campos

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 2)
    }

    /// Validade: "a partir de" só no passe de trem; "válido até" nos documentos com prazo.
    private var validitySection: some View {
        Section {
            if kind == .railPass {
                Toggle("Vale a partir de", isOn: $hasFrom)
                if hasFrom { datePicker($from) }
            }
            Toggle("Tem validade (passaporte, seguro, passe)", isOn: $hasUntil)
            if hasUntil { datePicker($until) }
        }
    }

    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker("Data", selection: date, displayedComponents: .date)
            .environment(\.timeZone, region.timeZone)
            .environment(\.locale, region.locale)
    }

    private var attachmentSection: some View {
        Section {
            PhotosPicker(selection: $photo, matching: .images) { Label("Foto", systemImage: "photo") }
            Button { picking = true } label: { Label(attachmentName == nil ? "Arquivo (PDF ou imagem)" : "Trocar arquivo", systemImage: "doc") }
            if attachmentName != nil {
                Button(role: .destructive, action: removeAttachment) { Label("Remover arquivo", systemImage: "trash") }
            }
        } header: {
            Text(kind == .entryQR ? "Print ou foto do QR" : "PDF ou foto")
        } footer: {
            if attachmentName != nil { Text("Arquivo guardado · fica só neste aparelho") }
        }
    }

    // MARK: Carga e gravação

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else {
            lowText = region.profile.money?.lowBalance ?? ""
            return
        }
        kind = item.kind
        name = item.name
        nameLocal = item.nameLocal ?? ""
        detail = item.detail
        coverage = item.coverage ?? ""
        balanceText = NumberInput.intText(item.balance)
        lowText = NumberInput.intText(item.lowBalance)
        hasFrom = item.validFrom != nil
        from = item.validFrom ?? AppClock.now
        hasUntil = item.validUntil != nil
        until = item.validUntil ?? AppClock.now
        qrText = item.qrPayload ?? ""
        attachmentName = item.attachmentName
        opensWallet = item.opensWallet
        link = item.link ?? ""
        notes = item.notes
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let target: WalletItem
        if let item {
            target = item
        } else {
            let order = (try? context.fetchCount(FetchDescriptor<WalletItem>())) ?? 0
            target = WalletItem(kind: kind, name: trimmedName, order: order)
            context.insert(target)
        }
        let newBalance = kind == .transitCard ? amount(balanceText) : nil
        target.kind = kind
        target.name = trimmedName
        target.nameLocal = nonEmpty(nameLocal)
        target.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        target.coverage = kind == .railPass ? nonEmpty(coverage) : nil
        if kind == .transitCard {
            // Anotar de novo (valor diferente) põe a data de agora; o mesmo valor mantém a data antiga.
            if newBalance != target.balance || target.balanceNotedAt == nil { target.balanceNotedAt = newBalance == nil ? nil : AppClock.now }
            target.balance = newBalance
            target.lowBalance = amount(lowText)
        } else {
            target.balance = nil
            target.balanceNotedAt = nil
            target.lowBalance = nil
        }
        target.validFrom = kind == .railPass && hasFrom ? minute(from) : nil
        target.validUntil = kind != .transitCard && kind != .creditCard && kind != .entryQR && hasUntil ? minute(until) : nil
        target.qrPayload = kind == .entryQR || kind == .railPass ? nonEmpty(qrText) : nil
        if let old = item?.attachmentName, old != attachmentName { TicketFiles.remove(old) }
        target.attachmentName = attachmentName
        target.opensWallet = (kind == .transitCard || kind == .creditCard) && opensWallet
        target.link = nonEmpty(link)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try context.save()
        } catch {
            context.rollback()
            if item == nil { context.delete(target) }
            self.error = "Não consegui gravar: \(error.localizedDescription)"
            return
        }
        saved = true
        dismiss()
    }

    // MARK: Arquivo

    private func attach(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                keep(data, ext: url.pathExtension.isEmpty ? "pdf" : url.pathExtension)
            } catch {
                self.error = "Não consegui abrir o arquivo: \(error.localizedDescription)"
            }
        case .failure(let failure):
            error = "Não consegui abrir o arquivo: \(failure.localizedDescription)"
        }
    }

    /// Guarda o arquivo (proteção completa) e, no QR de entrada, tenta ler o código sem rede.
    private func keep(_ data: Data, ext: String) {
        do {
            let name = try TicketFiles.save(data, ext: ext)
            if let fresh { TicketFiles.remove(fresh) }
            fresh = name
            attachmentName = name
            error = nil
        } catch {
            self.error = "Não consegui guardar o arquivo: \(error.localizedDescription)"
            return
        }
        guard kind == .entryQR, qrText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            let reading = try? await TicketReader.read(TicketSource.file(data, name: "entrada.\(ext)"))
            if let code = reading?.codes.first, qrText.trimmingCharacters(in: .whitespaces).isEmpty { qrText = code }
        }
    }

    private func removeAttachment() {
        if let fresh, fresh == attachmentName {
            TicketFiles.remove(fresh)
            self.fresh = nil
        }
        attachmentName = nil
    }

    // MARK: Auxiliares

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "3.240" → 3240. Vazio ou zero = sem valor.
    private func amount(_ text: String) -> Double? {
        guard let value = nonEmpty(text).map(TicketMoney.parse), value > 0 else { return nil }
        return value
    }

    /// Minuto inteiro: o banco guarda sem fração de segundo.
    private func minute(_ date: Date) -> Date {
        let c = region.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return region.calendar.date(from: c) ?? date
    }
}
