import SwiftUI

/// Lugar › "Dicas de quem foi" (Dicas.png): resumo no aparelho, temas, legenda de origem e dicas das fontes.
struct TipsSection: View {
    var model: TipsModel
    var region: Region

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dicas de quem foi").font(.must.archivo(22, .semibold)).foregroundStyle(Color.must.ink)
                Spacer()
                if model.phase == .off { Tag("desligado em Ajustes") }
            }
            switch model.phase {
            case .idle, .loading:
                skeleton
            case .loaded, .off:
                if model.phase == .loaded, model.tips.contains(where: { $0.source != .caption }) || model.summarizing {
                    summaryCard
                }
                if model.tips.count > 1 { filters }
                let visible = model.visible
                if visible.isEmpty {
                    Text(model.tips.isEmpty ? emptyText : "Nada nesse filtro.")
                        .mustMeta()
                        .padding(.vertical, 8)
                }
                ForEach(visible) { tip in
                    if tip.source == .caption { captionCard(tip) } else { tipCard(tip) }
                }
            }
            Text("Avaliações do Google, Foursquare e Reddit mostradas com autor e fonte, não armazenadas além de 30 dias. Traduções e resumo gerados no aparelho.")
                .font(.must.archivo(11))
                .foregroundStyle(Color.must.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var emptyText: String {
        model.phase == .off
            ? "Dicas de pessoas estão desligadas (Ajustes → Dados)."
            : "Nenhuma dica de quem foi pra esse lugar ainda. O Google não achou avaliações (ou o lugar no Places); o Foursquare está sem créditos e o Reddit, sem chave."
    }

    // MARK: Resumo

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Micro("resumo · \(model.tips.count) \(model.tips.count == 1 ? "dica" : "dicas") · \(max(1, model.sources.count)) \(model.sources.count == 1 ? "fonte" : "fontes")")
                Spacer()
                Text("no aparelho").font(.must.archivo(12)).foregroundStyle(Color.must.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                MustIconView(.assistente, size: 14)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [Color.must.blue, Color.must.green], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                if let summary = model.summary {
                    Text(Self.markdown(summary.summary))
                        .font(.must.archivo(16.5))
                        .foregroundStyle(Color.must.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.summarizing {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(Color.must.surface).frame(height: 12).frame(maxWidth: i == 2 ? 160 : .infinity)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    Text(OnDeviceAI.unavailableReason.map { "Resumo indisponível: \($0)." } ?? "O modelo do aparelho não resumiu essas dicas.")
                        .font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                }
            }
            if let themes = model.summary?.themes, !themes.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(themes) { theme in themeChip(theme) }
                }
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
        .shadow(color: Color(hex: 0x121316, opacity: 0.08), radius: 16, y: 8)
        .rotationEffect(.degrees(-0.8))
    }

    private func themeChip(_ theme: TipsSummary.Theme) -> some View {
        let (bg, fg): (Color, Color) = switch theme.sentiment {
        case .positive: (MustColor.eat.light, MustColor.eat.text)
        case .negative: (MustColor.coffee.light, MustColor.coffee.text)
        case .neutral: (Color.must.surface, Color.must.ink)
        }
        return Text("\(theme.word) · \(theme.count)×")
            .font(.must.archivo(14))
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(bg))
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: Filtros

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TipsModel.Filter.allCases) { f in
                    if f != .japanese || model.hasJapanese {
                        Button { model.filter = f } label: { Pill(f.label, isOn: model.filter == f) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Cards

    private func captionCard(_ tip: Tip) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("“\(tip.text)”")
                .font(.must.serif(19))
                .foregroundStyle(MustColor.eat.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 10) {
                sourceChip("IG", dark: true)
                Text(captionMeta(tip)).font(.must.archivo(13)).foregroundStyle(MustColor.eat.text.opacity(0.7)).lineLimit(2)
                Spacer(minLength: 6)
                Text("de onde veio este must").font(.must.archivo(13, .semibold)).foregroundStyle(MustColor.eat.text)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [MustColor.eat.light, MustColor.eat.light.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func captionMeta(_ tip: Tip) -> String {
        let kind = tip.url.map { $0.contains("tiktok") ? "TikTok" : ($0.contains("youtu") ? "Vídeo" : "Reel") } ?? "Post"
        let who = tip.author.map { " do \($0)" } ?? ""
        let when = tip.date.map { " · salvo \(region.shortDay($0))" } ?? ""
        return "\(kind)\(who)\(when)"
    }

    private func tipCard(_ tip: Tip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if tip.isJapanese {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(tip.quote)”").font(.must.serif(18)).foregroundStyle(Color.must.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pt = tip.translation {
                        Text("→ \(pt)").font(.must.archivo(12)).foregroundStyle(Color.must.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("“\(tip.text)”").font(.must.serif(16.5)).foregroundStyle(Color.must.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(8)
            }
            HStack(alignment: .center, spacing: 10) {
                Text(String((tip.author ?? tip.subreddit ?? "?").replacingOccurrences(of: "u/", with: "").prefix(1)).uppercased())
                    .font(.must.archivo(12, .semibold)).foregroundStyle(Color.must.ink)
                    .frame(width: 26, height: 26).background(Circle().fill(Color.must.line))
                Text(tip.author ?? (tip.subreddit.map { "r/\($0)" } ?? "")).font(.must.archivo(13)).foregroundStyle(Color.must.secondary).lineLimit(1)
                sourceChip(tip.source.chip, dark: false)
                Text(meta(tip)).font(.must.archivo(13)).foregroundStyle(Color.must.secondary).lineLimit(2)
                Spacer(minLength: 0)
                if tip.translated != nil { Tag("traduzido no aparelho") }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func meta(_ tip: Tip) -> String {
        var parts: [String] = []
        if let r = tip.rating { parts.append("\(Int(r))★") }
        if let v = tip.votes, tip.source == .reddit { parts.append("↑ \(v)") }
        if let s = tip.subreddit, tip.author != nil { parts.append("r/\(s)") }
        if let rel = tip.relativeDate { parts.append(rel) } else if let d = tip.date { parts.append(d.formatted(.relative(presentation: .named).locale(Locale(identifier: "pt-BR")))) }
        if tip.source == .google, tip.id == model.visible.first(where: { $0.source == .google })?.id,
           let count = model.ratingCount, let avg = model.rating {
            parts.append("\(count.formatted(.number.locale(Locale(identifier: "pt-BR")))) avaliações · \(avg.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt-BR"))))")
        }
        return parts.joined(separator: " · ")
    }

    private func sourceChip(_ text: String, dark: Bool) -> some View {
        Text(text)
            .font(.must.mono(11, .semibold))
            .foregroundStyle(dark ? .white : Color.must.ink)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(dark ? Color.must.ink : .white))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(dark ? .clear : Color.must.line))
    }

    // MARK: Skeleton

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.must.surface2)
                    .frame(height: i == 0 ? 170 : 110)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            Capsule().fill(Color.must.surface).frame(width: 140, height: 10)
                            Capsule().fill(Color.must.surface).frame(height: 12)
                            Capsule().fill(Color.must.surface).frame(width: 200, height: 12)
                        }
                        .padding(20)
                    }
            }
        }
        .redacted(reason: .placeholder)
    }
}
