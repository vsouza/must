import QuickLook
import SwiftData
import SwiftUI

/// Um item da Carteira aberto: QR (grande ao toque), voucher/arquivo, saldo anotado à mão, instruções e editar/apagar.
struct WalletItemSheet: View {
    @Bindable var item: WalletItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(RegionStore.self) private var store

    @State private var preview: URL?
    @State private var bigQR = false
    @State private var editing = false
    @State private var annotating = false
    @State private var confirmDelete = false

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    var body: some View {
        NavigationStack {
            List {
                if !item.detail.isEmpty || item.nameLocal != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            if let local = item.nameLocal, !local.isEmpty { Text(local).font(.title3.weight(.semibold)) }
                            if !item.detail.isEmpty { Text(item.detail).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                qrBlock
                if let text = WalletRules.validity(from: item.validFrom, until: item.validUntil, now: now, region: region) {
                    Section("Validade") { Text(text) }
                }
                if item.kind == .transitCard { balanceBlock }
                if let coverage = item.coverage, !coverage.isEmpty {
                    Section("Cobre") { Text(coverage) }
                }
                actions
                if !item.notes.isEmpty {
                    Section("Instruções") { Text(item.notes).textSelection(.enabled) }
                }
                Section {
                    Button { editing = true } label: { Label("Editar", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Apagar", systemImage: "trash") }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen(grouped: true)
        }
        .quickLookPreview($preview)
        .fullScreenCover(isPresented: $bigQR) {
            BigQRView(payload: item.qrPayload ?? "", confirmation: nil)
        }
        .sheet(isPresented: $editing) { WalletEditor(item: item) }
        .sheet(isPresented: $annotating) { WalletBalanceSheet(item: item) }
        .confirmationDialog("Apagar \(item.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) { delete() }
        } message: {
            Text("O arquivo guardado no aparelho também sai.")
        }
    }

    // MARK: Blocos

    /// QR desenhado no aparelho (CoreImage): funciona sem rede e sem o arquivo original. Fundo branco fixo (leitor).
    @ViewBuilder private var qrBlock: some View {
        if let payload = item.qrPayload, let image = TicketQR.image(for: payload, points: 220) {
            Section {
                Button { bigQR = true } label: {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mostrar QR grande")
            } footer: {
                Text("Salvo no aparelho · funciona sem internet · toque pra mostrar grande").frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// Saldo: sempre anotado à mão. Não há API pública pra ler o saldo da Suica.
    private var balanceBlock: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(item.balance.map { region.money($0) } ?? "sem saldo anotado")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Spacer(minLength: 8)
                Button("Anotar saldo") { annotating = true }.buttonStyle(.bordered)
            }
        } header: {
            Text("Saldo anotado à mão")
        } footer: {
            Text(balanceNote)
        }
    }

    private var balanceNote: String {
        let honest = "Anotado à mão: não há API pública pra ler o saldo do cartão."
        guard let noted = item.balanceNotedAt else { return honest }
        return "\(honest) Anotado \(WalletRules.balanceNote(noted: noted, now: now, region: region))."
    }

    @ViewBuilder private var actions: some View {
        if item.opensWallet || attachmentURL != nil || item.link.flatMap({ URL(string: $0) }) != nil {
            Section {
                if item.opensWallet {
                    Button { openURL(WalletRules.walletURL) } label: { Label("Abrir no Wallet", systemImage: "wallet.pass") }
                }
                if let url = attachmentURL {
                    Button { preview = url } label: {
                        Label(item.attachmentIsPDF ? "Abrir PDF" : "Abrir foto", systemImage: item.attachmentIsPDF ? "doc.text" : "photo")
                    }
                }
                if let link = item.link, let url = URL(string: link) {
                    Button { openURL(url) } label: { Label("Abrir o site", systemImage: "safari") }
                }
            }
        }
    }

    // MARK: Ações

    /// PDF ou foto em `TicketFiles` (proteção completa: só com o aparelho destravado).
    private var attachmentURL: URL? {
        item.attachmentName.flatMap { try? TicketFiles.url(for: $0) }
    }

    private func delete() {
        TicketFiles.remove(item.attachmentName)
        context.delete(item)
        try? context.save()
        dismiss()
    }
}

/// Anotar o saldo que você viu (Suica, cartão de transporte): valor e quando foi anotado.
struct WalletBalanceSheet: View {
    @Bindable var item: WalletItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store

    @State private var amount = ""
    @State private var notedAt = AppClock.now

    private var region: Region { store.region }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("3240", text: $amount).font(.title3.weight(.semibold)).monospacedDigit().keyboardType(.numberPad)
                } header: { Text("Saldo que você viu (\(region.currencySymbol))") }
                Section {
                    DatePicker("Anotado em", selection: $notedAt, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                } footer: {
                    Text("Anotado à mão: não há API pública pra ler o saldo. O valor é o que você viu no app ou no Wallet, na hora que anotou.")
                }
            }
            .navigationTitle("Anotar saldo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(amount.isEmpty) }
            }
            .v9Screen(grouped: true)
        }
        .onAppear {
            amount = NumberInput.intText(item.balance)
            notedAt = item.balanceNotedAt ?? AppClock.now
        }
    }

    private func save() {
        guard let value = NumberInput.int(amount, max: 1_000_000_000).map(Double.init) else { return }
        item.balance = value
        item.balanceNotedAt = notedAt
        try? context.save()
        dismiss()
    }
}
