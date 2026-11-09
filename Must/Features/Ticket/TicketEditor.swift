import SwiftUI

/// Ingresso à mão (prompt 14 · C · 12): confirmação, quando, sessão, código do QR, PDF ou foto, pessoas, pago e cancelamento.
/// Quem chama grava o resultado (`onSave`) no lugar; o arquivo anexado fica em `TicketFiles`.
struct TicketEditor: View {
    /// Ingresso existente (nil = novo).
    var ticket: Ticket?
    /// Sessões do lugar (art, jogo, experiência): escolher uma põe a hora e marca como comprada.
    var sessions: [EventSession]
    var region: Region
    var placeName: String
    var onSave: (Ticket) -> Void
    var onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var at = AppClock.now
    @State private var sessionId: String?
    @State private var confirmation = ""
    @State private var qrText = ""
    @State private var pdfName: String?
    /// Arquivo copiado nesta edição: se a edição for cancelada, ele é apagado.
    @State private var fresh: String?
    @State private var people = 1
    @State private var paidText = ""
    @State private var hasCancel = false
    @State private var cancelUntil = AppClock.now
    @State private var picking = false
    @State private var error: String?
    @State private var saved = false

    private var sortedSessions: [EventSession] { sessions.sorted { $0.at < $1.at } }

    var body: some View {
        NavigationStack {
            Form {
                if !sortedSessions.isEmpty {
                    Section("Sessão") {
                        Picker("Sessão", selection: Binding(get: { sessionId }, set: { id in
                            sessionId = id
                            if let id, let s = sortedSessions.first(where: { $0.id == id }) { at = s.at }
                        })) {
                            Text("Sem sessão").tag(String?.none)
                            ForEach(sortedSessions) { s in
                                Text("\(region.shortDay(s.at)) \(region.timeString(s.at))").tag(Optional(s.id))
                            }
                        }
                    }
                }
                Section {
                    DatePicker("Quando", selection: $at, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                    field("Código de confirmação") { TextField("BR-7K2M-9931", text: $confirmation).textInputAutocapitalization(.characters) }
                    field("Código do QR (colar)") { TextField("texto que o leitor lê", text: $qrText) }
                }
                Section {
                    Button { picking = true } label: { Label(pdfName == nil ? "Anexar PDF ou foto" : "Trocar arquivo", systemImage: "paperclip") }
                    if pdfName != nil {
                        Button(role: .destructive) { pdfName = nil } label: { Label("Remover arquivo", systemImage: "trash") }
                    }
                } footer: {
                    if pdfName != nil { Text("Arquivo anexado · fica só neste aparelho") }
                }
                Section {
                    Stepper(value: $people, in: 1...12) {
                        HStack { Text("Pessoas"); Spacer(); Text("\(people)").monospacedDigit().foregroundStyle(.secondary) }
                    }
                    field("Pago (\(region.currencySymbol), total)") { TextField("24.000", text: $paidText).keyboardType(.numberPad) }
                }
                Section {
                    Toggle(isOn: $hasCancel) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cancela grátis até")
                            Text("depois disso, cobra").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if hasCancel {
                        DatePicker("Até", selection: $cancelUntil, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, region.timeZone)
                            .environment(\.locale, region.locale)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let onRemove {
                    Section {
                        Button(role: .destructive) { onRemove(); dismiss() } label: { Label("Remover ingresso", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(ticket == nil ? "Novo ingresso" : "Ingresso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).fontWeight(.semibold) }
            }
            .v9Screen(grouped: true)
        }
        .onAppear(perform: load)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image]) { result in
            switch result {
            case .success(let url):
                do {
                    let name = try TicketFiles.importFile(at: url)
                    if let fresh { TicketFiles.remove(fresh) }
                    fresh = name
                    pdfName = name
                    error = nil
                } catch {
                    self.error = "Não consegui guardar o arquivo: \(error.localizedDescription)"
                }
            case .failure(let failure):
                error = "Não consegui abrir o arquivo: \(failure.localizedDescription)"
            }
        }
        .onDisappear {
            // Cancelou depois de anexar: o arquivo novo não fica órfão.
            if !saved, let fresh, fresh != ticket?.pdfName { TicketFiles.remove(fresh) }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 2)
    }

    private func load() {
        guard let ticket else {
            // Padrão: a próxima hora cheia (no fuso da região).
            let c = region.calendar.dateComponents([.year, .month, .day, .hour], from: AppClock.now)
            at = (region.calendar.date(from: c).map { $0.addingTimeInterval(3600) }) ?? AppClock.now
            cancelUntil = at
            return
        }
        at = ticket.at
        sessionId = ticket.sessionId
        confirmation = ticket.confirmation ?? ""
        qrText = ticket.qrPayload ?? ""
        pdfName = ticket.pdfName
        people = ticket.people ?? 1
        paidText = ticket.paid.map { region.money($0, symbol: false) } ?? ""
        hasCancel = ticket.cancelUntil != nil
        cancelUntil = ticket.cancelUntil ?? ticket.at
    }

    private func save() {
        // Minuto inteiro: o board guarda ISO sem fração.
        let c = region.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        let when = region.calendar.date(from: c) ?? at
        let paid = NumberInput.double(paidText.filter { ($0.isASCII && $0.isNumber) || $0 == "," }.replacingOccurrences(of: ",", with: "."))
        let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let cancelValue = hasCancel ? region.calendar.date(from: region.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: cancelUntil)) : nil
        let result = Ticket(id: ticket?.id ?? UUID().uuidString, at: when, sessionId: sessionId,
                            confirmation: trimmed(confirmation).isEmpty ? nil : trimmed(confirmation),
                            qrPayload: trimmed(qrText).isEmpty ? nil : trimmed(qrText),
                            pdfName: pdfName, paid: paid, people: people, cancelUntil: cancelValue,
                            walletPassURL: ticket?.walletPassURL)
        // Trocou o arquivo: o anterior sai do aparelho.
        if let old = ticket?.pdfName, old != pdfName { TicketFiles.remove(old) }
        saved = true
        onSave(result)
        dismiss()
    }
}

/// Lista de ingressos de um lugar: Editar lugar › Ingresso (rascunho) e Lugar › Anexar ingresso.
struct TicketsEditor: View {
    @Binding var tickets: [Ticket]
    var sessions: [EventSession]
    var region: Region
    var placeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var editing: Target?

    private enum Target: Identifiable {
        case new
        case edit(Ticket)
        var id: String { if case .edit(let t) = self { t.id } else { "new" } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if tickets.isEmpty {
                        Text("Nenhum ingresso anexado.").foregroundStyle(.secondary)
                    } else {
                        ForEach(tickets.sorted { $0.at < $1.at }) { t in
                            Button { editing = .edit(t) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(region.shortDay(t.at)) · \(region.timeString(t.at))").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                        let sub = [t.confirmation, t.pdfName == nil ? nil : "PDF"].compactMap { $0 }.joined(separator: " · ")
                                        if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } footer: {
                    Text("Cada ingresso vira âncora do dia, como a reserva. Ele aparece em Reservas.")
                }
                Section { Button { editing = .new } label: { Label("Anexar ingresso", systemImage: "plus") } }
            }
            .navigationTitle("Ingressos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Pronto") { dismiss() }.fontWeight(.semibold) } }
            .v9Screen(grouped: true)
        }
        .sheet(item: $editing) { target in
            let current: Ticket? = if case .edit(let t) = target { t } else { nil }
            TicketEditor(ticket: current, sessions: sessions, region: region, placeName: placeName,
                         onSave: { updated in
                             if let i = tickets.firstIndex(where: { $0.id == updated.id }) { tickets[i] = updated } else { tickets.append(updated) }
                         },
                         onRemove: current.map { t in
                             {
                                 TicketFiles.remove(t.pdfName)
                                 tickets.removeAll { $0.id == t.id }
                             }
                         })
        }
    }
}
