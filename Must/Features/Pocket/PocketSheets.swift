import AVFoundation
import SwiftUI

/// Detalhe de um card do Bolso (V9): o valor e as linhas do país numa lista nativa. Saldo da Suica leva pra Carteira.
struct PocketDetailSheet: View {
    var card: PocketCard
    var region: Region
    var onWallet: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.value.replacingOccurrences(of: "\n", with: " ")).font(.title.weight(.bold)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        Text(card.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                if !card.more.isEmpty {
                    Section {
                        ForEach(Array(card.more.enumerated()), id: \.offset) { _, line in
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    } footer: { Text("Funciona sem internet.") }
                }
                if let onWallet {
                    Section { Button("Anotar o saldo na Carteira", action: onWallet) }
                }
            }
            .navigationTitle(card.label.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen(grouped: true)
        }
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

    /// Moeda do conversor: a do país, salvo quando o Bolso converte outra (BH: dólar).
    private var foreign: String { PocketRules.country(region).exchangeCurrency ?? region.currency }
    private var foreignSymbol: String { PocketRules.country(region).exchangeSymbol ?? region.currencySymbol }

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
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(toBRL ? foreignSymbol : "R$").font(.title2).foregroundStyle(.secondary)
                        TextField("0", text: $text)
                            .font(.largeTitle.weight(.semibold)).monospacedDigit()
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .accessibilityLabel("Valor em \(toBRL ? foreignSymbol : "reais")")
                    }
                } footer: { Text("Câmbio offline · \(rateLine)") }
                Section("Vale") {
                    Text(result).font(.largeTitle.weight(.bold)).monospacedDigit().foregroundStyle(V9.accent)
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
                Section {
                    Button(toBRL ? "Trocar: reais → \(foreignSymbol)" : "Trocar: \(foreignSymbol) → reais") { toBRL.toggle() }
                }
            }
            .navigationTitle("Câmbio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen(grouped: true)
            .onAppear { focused = true }
        }
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
        NavigationStack {
            List {
                Section {
                    ForEach(phrases) { phrase in
                        Button { speaker.speak(phrase.speech, language: PocketRules.country(region).speechLanguage) } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(phrase.latin).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                    Text(phrase.meaning).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: speaker.speaking == phrase.speech ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .font(.title3).foregroundStyle(speaker.speaking == phrase.speech ? V9.accent : .secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(phrase.latin), \(phrase.meaning)")
                        .accessibilityHint("toca o áudio")
                    }
                } footer: { Text("\(phrases.count) frases · toque pra ouvir · funciona sem internet") }
            }
            .navigationTitle("Frases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen(grouped: true)
        }
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
