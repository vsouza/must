import SwiftData
import SwiftUI

/// O que o Board apresenta por cima da lista.
enum BoardSheet: Identifiable, Hashable {
    case move
    case city
    /// Marcar 済 (swipe): `Place.id`.
    case done(String)

    var id: String {
        switch self {
        case .move: "move"
        case .city: "city"
        case .done(let id): "done-\(id)"
        }
    }
}

/// Barra preta de ações em lote (modo edição, com seleção).
struct BoardBatchBar: View {
    var count: Int
    /// "Selecionar tudo em Must eat" (nil quando não há lista de foco).
    var focusTitle: String?
    var saveForEndTitle: String
    var onSelectAll: () -> Void
    var onMove: () -> Void
    var onSaveForEnd: () -> Void
    var onCity: () -> Void
    var onResolve: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("\(count) \(count == 1 ? "selecionado" : "selecionados")")
                    .font(.must.archivo(17, .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let focusTitle {
                    Button(action: onSelectAll) {
                        Text("Selecionar tudo em \(focusTitle)")
                            .font(.must.archivo(13, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(MustPressStyle())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BatchChip(title: "Mover pra lista…", action: onMove)
                    BatchChip(title: saveForEndTitle, action: onSaveForEnd)
                    BatchChip(title: "Cidade", action: onCity)
                    BatchChip(title: "Resolver no Places", action: onResolve)
                    BatchChip(title: "Apagar", destructive: true, action: onDelete)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x121316)))
        .shadow(color: Color(hex: 0x121316, opacity: 0.25), radius: 20, x: 0, y: 12)
        .padding(.horizontal, 22)
    }
}

private struct BatchChip: View {
    var title: String
    var destructive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.must.archivo(14, .semibold))
                .foregroundStyle(destructive ? Color(hex: 0xFF8A80) : .white)
                .lineLimit(1)
                .padding(.vertical, 11)
                .padding(.horizontal, 15)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Mover pra lista…: as listas, com a cor e a contagem.
struct MoveListSheet: View {
    var lists: [MustList]
    var count: Int
    var onPick: (MustList) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHandle().frame(maxWidth: .infinity)
            Text("Mover \(count) \(count == 1 ? "lugar" : "lugares")")
                .font(.must.archivo(22, .semibold))
                .foregroundStyle(Color.must.ink)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(lists) { list in
                        Button {
                            onPick(list)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(list.color.strong).frame(width: 10, height: 10)
                                Text(list.displayName)
                                    .font(.must.archivo(16, .semibold))
                                    .foregroundStyle(Color.must.ink)
                                Spacer()
                                Text("\(list.places.count)")
                                    .font(.must.mono(13))
                                    .foregroundStyle(Color.must.secondary)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        RowDivider()
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Color.must.bg)
    }
}

/// Um item do seletor de cidade (o título já traz "Tóquio 13–17" quando o nome se repete).
struct CityOption: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Cidade…: troca a cidade dos lugares selecionados.
struct CityPickSheet: View {
    var options: [CityOption]
    var onPick: (CityOption) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHandle().frame(maxWidth: .infinity)
            Text("Cidade")
                .font(.must.archivo(22, .semibold))
                .foregroundStyle(Color.must.ink)
            ForEach(options) { option in
                Button {
                    onPick(option)
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                RowDivider()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Color.must.bg)
    }
}

/// Feito (swipe à direita): quanto foi. Sem valor também marca 済.
struct DoneSheet: View {
    var place: Place
    var region: Region

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHandle().frame(maxWidth: .infinity)
            Text(place.name)
                .font(.must.archivo(22, .semibold))
                .foregroundStyle(Color.must.ink)
            Micro("quanto foi?")
            HStack(spacing: 10) {
                Text(region.currencySymbol).font(.must.mono(17)).foregroundStyle(Color.must.secondary)
                TextField("0", text: $amount)
                    .font(.must.mono(17))
                    .keyboardType(.decimalPad)
                    .foregroundStyle(Color.must.ink)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Pode deixar em branco: marca como feito do mesmo jeito.").mustMeta()
            PrimaryButton("Marcar feito") { mark() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Color.must.bg)
    }

    private func mark() {
        let spent = NumberInput.double(amount.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
        PlaceActions.markDone(place, spent: spent, context: context)
        dismiss()
    }
}
