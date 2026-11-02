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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHandle().frame(maxWidth: .infinity)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ticket == nil ? "Novo ingresso" : "Ingresso").mustTitle()
                        Text(placeName).mustMeta()
                    }
                    Spacer()
                    Button(action: save) {
                        Text("Salvar").font(.must.archivo(15, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(Capsule().fill(Color.must.ink))
                    }
                    .buttonStyle(MustPressStyle())
                }

                if !sortedSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Micro("sessão")
                        FlowLayout(spacing: 8) {
                            Button { sessionId = nil } label: { Pill("sem sessão", isOn: sessionId == nil) }.buttonStyle(MustPressStyle())
                            ForEach(sortedSessions) { s in
                                Button {
                                    sessionId = s.id
                                    at = s.at
                                } label: { Pill("\(region.shortDay(s.at)) \(region.timeString(s.at))", isOn: sessionId == s.id) }
                                .buttonStyle(MustPressStyle())
                            }
                        }
                    }
                }

                DatePicker("Quando", selection: $at, displayedComponents: [.date, .hourAndMinute])
                    .font(.must.body).tint(Color.must.ink)
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)

                field("código de confirmação") { TextField("BR-7K2M-9931", text: $confirmation).font(.must.mono(17)).textInputAutocapitalization(.characters) }
                field("código do QR (colar)") { TextField("texto que o leitor lê", text: $qrText).font(.must.archivo(15)) }

                VStack(alignment: .leading, spacing: 10) {
                    Micro("PDF ou foto")
                    HStack(spacing: 10) {
                        GhostButton(pdfName == nil ? "Anexar" : "Trocar arquivo", icon: .colarLink) { picking = true }
                        if pdfName != nil {
                            Button { pdfName = nil } label: { Pill("remover", icon: .remover) }.buttonStyle(MustPressStyle())
                        }
                    }
                    if pdfName != nil { Text("arquivo anexado · fica só neste aparelho").mustMeta() }
                }

                Stepper(value: $people, in: 1...12) {
                    HStack {
                        Text("Pessoas").mustBody()
                        Spacer()
                        Text("\(people)").font(.must.mono(15))
                    }
                }

                field("pago (\(region.currencySymbol), total)") { TextField("24.000", text: $paidText).font(.must.mono(17)).keyboardType(.numberPad) }

                Toggle(isOn: $hasCancel) { FormRow("Cancela grátis até", subtitle: "depois disso, cobra") }.toggleStyle(.must)
                if hasCancel {
                    DatePicker("Até", selection: $cancelUntil, displayedComponents: [.date, .hourAndMinute])
                        .font(.must.body).tint(Color.must.ink)
                        .environment(\.timeZone, region.timeZone)
                        .environment(\.locale, region.locale)
                }

                if let error { Text(error).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D)) }

                if let onRemove {
                    GhostButton("Remover ingresso", icon: .remover) {
                        onRemove()
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
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
        VStack(alignment: .leading, spacing: 10) {
            Micro(label)
            content()
                .foregroundStyle(Color.must.ink)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
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
        let paid = Double(paidText.filter { $0.isNumber || $0 == "," }.replacingOccurrences(of: ",", with: "."))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHandle().frame(maxWidth: .infinity)
                HStack {
                    Text("Ingressos").mustTitle()
                    Spacer()
                    Button("Pronto") { dismiss() }
                        .font(.must.archivo(15, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 40)
                        .background(Capsule().fill(Color.must.ink))
                }
                Text("Cada ingresso vira âncora do dia, como a reserva. Ele aparece em Reservas.").mustMeta()
                if tickets.isEmpty {
                    Text("Nenhum ingresso anexado.").mustMeta().padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tickets.sorted { $0.at < $1.at }) { t in
                            RowDivider()
                            Button { editing = .edit(t) } label: {
                                FormRow("\(region.shortDay(t.at)) · \(region.timeString(t.at))",
                                        subtitle: [t.confirmation, t.pdfName == nil ? nil : "PDF"].compactMap { $0 }.joined(separator: " · ")) {
                                    MustIconView(.avancar, size: 14).foregroundStyle(Color.must.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                PrimaryButton("Anexar ingresso", icon: .colarLink, style: .dark) { editing = .new }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
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
