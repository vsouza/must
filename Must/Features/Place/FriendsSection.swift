import SwiftUI

/// Textos puros de "amigos que foram" (`LugarAmigos.png`), também usados na linha das Dicas e no card do mapa.
enum FriendsLine {
    /// Primeiro nome ("Ana Beatriz" → "Ana").
    static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }

    /// "Ana e Pedro foram", "Ana, Pedro e Carol foram", "Ana foi"; nil sem visita.
    static func names(_ visits: [FriendVisit]) -> String? {
        let n = visits.map { first($0.name) }
        switch n.count {
        case 0: return nil
        case 1: return "\(n[0]) foi"
        case 2: return "\(n[0]) e \(n[1]) foram"
        default: return "\(n.dropLast().joined(separator: ", ")) e \(n[n.count - 1]) foram"
        }
    }

    /// "Ana e Pedro foram · “Vá às 18h.”" (a frase só quando a primeira visita tem uma).
    static func summary(_ visits: [FriendVisit]) -> String? {
        guard let who = names(visits) else { return nil }
        if let note = visits.first(where: { ($0.note ?? "").isEmpty == false })?.note { return "\(who) · “\(note)”" }
        return who
    }
}

/// Provedor de amigos com os exemplos dos prints por baixo (`-debugScreen lugar-amigos`), só em DEBUG.
enum FriendsProvider {
    static func visits(_ source: any FriendsProviding, placeId: String) -> [FriendVisit] {
        let real = source.visits(placeId: placeId)
        #if DEBUG
        if real.isEmpty, (DebugFlags.string("debugScreen") ?? "").hasPrefix("lugar-amigos") {
            return [
                FriendVisit(id: "x1", name: "Ana Beatriz", initials: "AB", when: "out 2025", note: "Vá às 18h, o pôr do sol é o show."),
                FriendVisit(id: "x2", name: "Pedro", initials: "PS", when: "mar 2024", note: "Couvert ¥ 3.500, reserve pelo hotel."),
                FriendVisit(id: "x3", name: "Carol", initials: "CM", when: "abr 2023", note: "Fica lotado depois das 20h."),
            ]
        }
        #endif
        return real
    }
}

/// Lugar › "Amigos que foram": avatar com iniciais, nome, quando e uma frase. A etiqueta "exemplo · lista fixa" fica
/// enquanto a fonte for mock. Sem visitas, o bloco some (quem chama não monta a seção).
struct FriendsSection: View {
    var visits: [FriendVisit]
    var isSample: Bool

    @State private var all = false
    private static let limit = 3

    private var shown: [FriendVisit] { all ? visits : Array(visits.prefix(Self.limit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Amigos que foram").font(V8Font.display(28)).tracking(-0.8).foregroundStyle(V8.ink)
                    .lineLimit(2).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if isSample { V8Tag(text: "exemplo · lista fixa", style: .paper) }
            }
            .padding(.bottom, 10)
            ForEach(Array(shown.enumerated()), id: \.element.id) { offset, visit in
                row(visit, offset: offset).overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
            }
            if visits.count > Self.limit {
                Button { withAnimation(.easeOut(duration: 0.2)) { all.toggle() } } label: {
                    SpecLabel(all ? "mostrar menos" : "\(visits.count) amigos · ver todos", color: V8.mute).padding(.top, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ visit: FriendVisit, offset: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(visit.initials)
                .font(V8Font.mono(12, weight: .bold))
                .foregroundStyle(offset % 3 == 0 ? V8.white : V8.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill([V8.ink, V8.orange, V8.bone][offset % 3]))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                (Text(visit.name).font(V8Font.text(17, weight: .bold)).foregroundColor(V8.ink)
                    + Text(" · \(visit.when)").font(V8Font.text(14)).foregroundColor(V8.mute))
                    .lineLimit(2)
                if let note = visit.note, !note.isEmpty {
                    Text("“\(note)”").font(V8Font.text(15)).foregroundStyle(V8.ink.opacity(0.8))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
