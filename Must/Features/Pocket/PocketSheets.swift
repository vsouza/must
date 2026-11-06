import AVFoundation
import SwiftUI

/// Detalhe de um card do Bolso: o valor grande e as linhas do país. Saldo da Suica leva pra Carteira (anotar à mão).
struct PocketDetailSheet: View {
    var card: PocketCard
    var region: Region
    var onWallet: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    V8SpecStack(lines: [card.label, "offline"]).padding(.top, 14)
                    Spacer()
                    V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
                }
                Text(card.value.replacingOccurrences(of: "\n", with: " "))
                    .font(V8Font.display(40))
                    .tracking(-1.2)
                    .foregroundStyle(V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                Text(card.detail)
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(card.more.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(V8Font.mono(11))
                                .foregroundStyle(V8.orangeDeep)
                            Text(line)
                                .font(V8Font.text(15))
                                .foregroundStyle(V8.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                        Rectangle().fill(V8.ink.opacity(0.12)).frame(height: 1)
                    }
                }
                .padding(.top, 20)
                if let onWallet {
                    V8Button("Anotar o saldo na Carteira", .ink, action: onWallet).padding(.top, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(V8.paper.ignoresSafeArea())
    }
}

/// Conversor offline: moeda da região ⇄ reais, com o câmbio guardado (ou o padrão do país).
struct PocketConverterSheet: View {
    var region: Region
    /// R$ por 1 unidade da moeda da região (BH: R$ por US$ 1).
    var rate: Double

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var toBRL = true
    @FocusState private var focused: Bool

    private var foreign: String { region == .bh ? "USD" : region.currency }
    private var foreignSymbol: String { region == .bh ? "US$" : region.currencySymbol }

    private var value: Double {
        NumberInput.double(text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var result: String {
        let converted = PocketRules.convert(value, region: region, rate: rate, toBRL: toBRL)
        if toBRL { return converted.formatted(.money("BRL")) }
        let decimals = foreign == "JPY" ? 0 : 2
        return "\(foreignSymbol) " + converted.formatted(.number.locale(region.locale).precision(.fractionLength(decimals)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                V8SpecStack(lines: ["Câmbio · offline", rateLine]).padding(.top, 14)
                Spacer()
                V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(toBRL ? foreignSymbol : "R$").font(V8Font.display(34)).foregroundStyle(V8.mute)
                TextField("0", text: $text)
                    .font(V8Font.numeral(54))
                    .foregroundStyle(V8.ink)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .accessibilityLabel("Valor em \(toBRL ? foreignSymbol : "reais")")
            }
            .padding(.top, 26)
            Rectangle().fill(V8.ink.opacity(0.2)).frame(height: 1)
            Text(result)
                .font(V8Font.numeral(44))
                .foregroundStyle(V8.orangeDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 14)
            V8Button(toBRL ? "Trocar: reais → \(foreignSymbol)" : "Trocar: \(foreignSymbol) → reais", .line) { toBRL.toggle() }
                .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(V8.paper.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private var rateLine: String {
        let unit = foreign == "JPY" ? 100.0 : 1
        let symbol = foreign == "JPY" ? "¥100" : "\(foreignSymbol) 1"
        return "\(symbol) = \((unit * rate).formatted(.money("BRL")))"
    }
}

/// Frases com áudio: letras latinas e o sentido em pt-BR; o toque fala a frase (sintetizador do aparelho, offline).
struct PocketPhrasesSheet: View {
    var region: Region

    @Environment(\.dismiss) private var dismiss
    @State private var speaker = PhraseSpeaker()

    var body: some View {
        let phrases = PocketRules.phrases(for: region)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    V8SpecStack(lines: ["Frases · \(phrases.count)", "toque pra ouvir · offline"]).padding(.top, 14)
                    Spacer()
                    V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
                }
                Text("Frases").font(V8Font.display(44)).tracking(-1.3).foregroundStyle(V8.ink).padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(phrases) { phrase in
                        Button { speaker.speak(phrase.speech, language: PocketRules.country(region).speechLanguage) } label: {
                            HStack(alignment: .center, spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(phrase.latin).font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(phrase.meaning).font(V8Font.text(14)).foregroundStyle(V8.mute)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: speaker.speaking == phrase.speech ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(V8.ink)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(speaker.speaking == phrase.speech ? V8.orange : V8.white))
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(phrase.latin), \(phrase.meaning)")
                        .accessibilityHint("toca o áudio")
                        Rectangle().fill(V8.ink.opacity(0.12)).frame(height: 1)
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(V8.paper.ignoresSafeArea())
    }
}

/// Fala uma frase com a voz do aparelho (offline). Um sintetizador por tela, nunca em segundo plano.
@MainActor
@Observable
final class PhraseSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var speaking: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        speaking = text
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = nil }
    }
}
