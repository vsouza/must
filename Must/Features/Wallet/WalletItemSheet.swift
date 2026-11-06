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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHandle().frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Micro(item.kind.label)
                    Text(item.name).mustTitle()
                    if let local = item.nameLocal {
                        Text(local).mustSerif(18).foregroundStyle(Color.must.secondary)
                    }
                    if !item.detail.isEmpty { Text(item.detail).mustMeta() }
                }

                qrBlock
                validityRow
                if item.kind == .transitCard { balanceBlock }
                if let coverage = item.coverage, !coverage.isEmpty {
                    FormSection { FormRow("Cobre", subtitle: coverage) }
                }
                actions
                if !item.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Micro("instruções")
                        Text(item.notes).font(.must.archivo(15)).foregroundStyle(Color.must.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                HStack(spacing: 10) {
                    GhostButton("Editar", icon: .editar) { editing = true }
                    GhostButton("Apagar", icon: .remover) { confirmDelete = true }
                }
                .padding(.top, 4)
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
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

    /// QR desenhado no aparelho (CoreImage): funciona sem rede e sem o arquivo original.
    @ViewBuilder private var qrBlock: some View {
        if let payload = item.qrPayload, let image = TicketQR.image(for: payload, points: 220) {
            VStack(alignment: .leading, spacing: 10) {
                Button { bigQR = true } label: {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Mostrar QR grande")
                Text("salvo no aparelho · funciona sem internet · toque pra mostrar grande").mustMeta()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private var validityRow: some View {
        if let text = WalletRules.validity(from: item.validFrom, until: item.validUntil, now: now, region: region) {
            FormSection { FormRow("Validade", subtitle: text) }
        }
    }

    /// Saldo: sempre anotado à mão. Não há API pública pra ler o saldo da Suica.
    private var balanceBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("saldo anotado à mão")
            HStack(alignment: .firstTextBaseline) {
                Text(item.balance.map { region.money($0) } ?? "sem saldo anotado")
                    .font(.must.mono(26, .semibold)).foregroundStyle(Color.must.ink)
                Spacer(minLength: 8)
                Button { annotating = true } label: { Pill("anotar saldo", icon: .editar) }
                    .buttonStyle(MustPressStyle())
            }
            Text(balanceNote).mustMeta()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var balanceNote: String {
        let honest = "Anotado à mão: não há API pública pra ler o saldo do cartão."
        guard let noted = item.balanceNotedAt else { return honest }
        return "\(honest) Anotado \(WalletRules.balanceNote(noted: noted, now: now, region: region))."
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if item.opensWallet {
                PrimaryButton("Abrir no Wallet ↗", style: .dark) { openURL(WalletRules.walletURL) }
            }
            if let url = attachmentURL {
                PrimaryButton(item.attachmentIsPDF ? "Abrir PDF" : "Abrir foto", style: .dark) { preview = url }
            }
            if let link = item.link, let url = URL(string: link) {
                GhostButton("Abrir o site ↗") { openURL(url) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHandle().frame(maxWidth: .infinity)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anotar saldo").mustTitle()
                        Text(item.name).mustMeta()
                    }
                    Spacer()
                    Button(action: save) {
                        Text("Salvar").font(.must.archivo(15, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(Capsule().fill(amount.isEmpty ? Color.must.secondary : Color.must.ink))
                    }
                    .buttonStyle(MustPressStyle())
                    .disabled(amount.isEmpty)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Micro("saldo que você viu (\(region.currencySymbol))")
                    TextField("3240", text: $amount)
                        .font(.must.mono(20, .semibold))
                        .keyboardType(.numberPad)
                        .foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                DatePicker("Anotado em", selection: $notedAt, displayedComponents: [.date, .hourAndMinute])
                    .font(.must.body).tint(Color.must.ink)
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)

                Text("Anotado à mão: não há API pública pra ler o saldo. O valor é o que você viu no app ou no Wallet, na hora que anotou.")
                    .mustMeta()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
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
