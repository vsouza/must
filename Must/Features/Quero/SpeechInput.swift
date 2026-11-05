import AVFoundation
import Foundation
import Observation
import Speech

/// Voz do Quero… (prompt 25 · A.1): `SFSpeechRecognizer` em pt-BR, no aparelho quando ele suporta
/// (`requiresOnDeviceRecognition`). Fala → texto parcial no campo; ao parar (toque de novo ou 1,6 s de silêncio), `onFinal`.
@MainActor
@Observable
final class SpeechInput {
    enum State: Equatable { case idle, listening, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var transcript = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored var onFinal: ((String) -> Void)?

    var isListening: Bool { state == .listening }

    func toggle() async {
        if isListening { finish(); return }
        await start()
    }

    func start() async {
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        guard await Self.authorize() else { state = .denied; return }
        stopAudio()
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let engine = AVAudioEngine()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(request))
            engine.prepare()
            try engine.start()
        } catch {
            Log.intelligence.error("quero · voz: \(error.localizedDescription, privacy: .public)")
            state = .unavailable
            return
        }
        self.engine = engine
        self.request = request
        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in self?.receive(text: text, isFinal: isFinal, failed: failed) }
        }
    }

    /// O bloco do tap roda na thread de áudio: só repassa o buffer (o pedido é thread-safe pra `append`).
    private nonisolated static func tap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in request.append(buffer) }
    }

    private func receive(text: String?, isFinal: Bool, failed: Bool) {
        guard state == .listening else { return }
        if let text, !text.isEmpty {
            transcript = text
            // 1,6 s sem palavra nova = terminou de falar.
            silence?.cancel()
            silence = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1600))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
        if isFinal || failed { finish() }
    }

    func finish() {
        guard state == .listening else { return }
        silence?.cancel()
        stopAudio()
        state = .idle
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onFinal?(text) }
    }

    func cancel() {
        silence?.cancel()
        stopAudio()
        if state == .listening { state = .idle }
    }

    private func stopAudio() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Fala + microfone. Pergunta só na primeira vez (o iOS lembra a resposta).
    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in done.resume(returning: status == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
