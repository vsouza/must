import AVFoundation
import Foundation
import Speech
import Synchronization
import Vision

struct VideoProgress: Equatable, Sendable {
    enum Stage: String, Sendable { case preparing, screen, speech, done }
    var stage: Stage
    /// 0...1 do trabalho todo.
    var fraction: Double

    var label: String {
        switch stage {
        case .preparing: "Abrindo o vídeo…"
        case .screen: "Lendo o texto da tela…"
        case .speech: "Ouvindo o que é falado…"
        case .done: "Pronto"
        }
    }
}

struct VideoReading: Equatable, Sendable {
    var screen: [VideoSnippet] = []
    var speech: [VideoSnippet] = []
    var duration: Double = 0
    /// Avisos pra mostrar ("sem fala", "modelo de fala só baixa no Wi-Fi").
    var notes: [String] = []

    func merged(caption: String?) -> String {
        VideoText.merge(caption: caption, screen: screen, speech: speech)
    }
}

/// Lê um vídeo no aparelho (prompt 29): texto na tela (Vision) e fala (SpeechAnalyzer, com SFSpeechRecognizer de reserva).
/// Fora do main, cancelável (cancelar a `Task` que chama `read` para tudo) e com progresso. O vídeo não sai do aparelho.
actor VideoReader {
    struct Options: Sendable {
        var locale: Locale = Locale(identifier: "pt-BR")
        var ocrLanguages: [String] = ["pt-BR", "en-US", "ja-JP", "it-IT"]
        var maxFrames = 90
        /// Baixar o modelo de fala se faltar: só no Wi-Fi e fora do Modo de Pouco Dados.
        var allowModelDownload = false
        var readSpeech = true
        var readScreen = true

        /// Idioma da fala pela região (BH fala português; Japão, japonês).
        static func locale(for region: Region) -> Locale {
            Locale(identifier: region.profile.day?.videoLocale ?? "pt-BR")
        }
    }

    enum ReadError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Não consegui abrir esse vídeo." }
    }

    func read(_ url: URL, options: Options = Options(), progress: @escaping @Sendable (VideoProgress) -> Void = { _ in }) async throws -> VideoReading {
        progress(VideoProgress(stage: .preparing, fraction: 0))
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { throw ReadError.unreadable }
        let hasVideo = ((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false
        let hasAudio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
        try Task.checkCancellation()

        let meter = Meter(parts: (options.readScreen && hasVideo ? 1 : 0) + (options.readSpeech && hasAudio ? 1 : 0), report: progress)
        async let screen = options.readScreen && hasVideo
            ? Self.readScreen(asset, duration: duration, options: options, meter: meter) : []
        async let speech = options.readSpeech && hasAudio
            ? Self.readSpeech(asset: asset, options: options, meter: meter) : (snippets: [], note: nil as String?)

        var reading = VideoReading(duration: duration)
        reading.screen = try await screen
        let spoken = try await speech
        reading.speech = spoken.snippets
        if let note = spoken.note { reading.notes.append(note) }
        if !hasAudio { reading.notes.append("vídeo sem fala") }
        progress(VideoProgress(stage: .done, fraction: 1))
        return reading
    }

    /// Soma o progresso das duas leituras (que correm juntas) numa fração só.
    final class Meter: Sendable {
        enum Part: Int, Sendable { case screen, speech }
        private let state = Mutex<[Int: Double]>([:])
        private let parts: Int
        private let report: @Sendable (VideoProgress) -> Void

        init(parts: Int, report: @escaping @Sendable (VideoProgress) -> Void) {
            self.parts = max(parts, 1)
            self.report = report
        }

        func update(_ part: Part, _ fraction: Double) {
            let total = state.withLock { values -> Double in
                values[part.rawValue] = min(max(fraction, 0), 1)
                return values.values.reduce(0, +)
            }
            report(VideoProgress(stage: part == .screen ? .screen : .speech, fraction: min(total / Double(parts), 0.99)))
        }
    }

    // MARK: Texto na tela

    /// 1 quadro por segundo (no máximo `maxFrames`; vídeo mais longo espaça os quadros).
    static func sampleTimes(duration: Double, maxFrames: Int) -> [Double] {
        guard duration > 0, maxFrames > 0 else { return [] }
        let step = max(1.0, duration / Double(maxFrames))
        var times: [Double] = []
        var t = min(0.2, duration / 2)
        while t < duration, times.count < maxFrames {
            times.append(t)
            t += step
        }
        return times
    }

    static func readScreen(_ asset: AVURLAsset, duration: Double, options: Options, meter: Meter) async throws -> [VideoSnippet] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)
        let times = sampleTimes(duration: duration, maxFrames: options.maxFrames)
        guard !times.isEmpty else { return [] }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = options.ocrLanguages.map { Locale.Language(identifier: $0) }

        var found: [VideoSnippet] = []
        var done = 0
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            try Task.checkCancellation()
            done += 1
            meter.update(.screen, Double(done) / Double(times.count))
            guard case .success(_, let image, let actual) = result else { continue }
            let observations = (try? await request.perform(on: image)) ?? []
            for observation in observations {
                guard let top = observation.topCandidates(1).first, top.confidence >= 0.45 else { continue }
                let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isUseful(text) else { continue }
                found.append(VideoSnippet(origin: .screen, seconds: actual.seconds, text: text))
            }
        }
        try Task.checkCancellation()
        meter.update(.screen, 1)
        return VideoText.dedupe(found)
    }

    /// Descarta ruído do OCR: curto demais, sem letra e palavras da interface do app.
    static func isUseful(_ text: String) -> Bool {
        guard text.count >= 3, text.contains(where: \.isLetter) else { return false }
        if VideoText.normalize(text).count < 3 { return false }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return !VideoText.interfaceWords.contains(folded)
    }

    // MARK: Fala

    static func readSpeech(asset: AVURLAsset, options: Options, meter: Meter) async throws -> (snippets: [VideoSnippet], note: String?) {
        meter.update(.speech, 0)
        let audioURL = FileManager.default.temporaryDirectory.appending(path: "must-video-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return ([], "sem áudio legível") }
        do {
            try await export.export(to: audioURL, as: .m4a)
        } catch {
            if error is CancellationError { throw error }
            return ([], "sem áudio legível")
        }
        try Task.checkCancellation()
        meter.update(.speech, 0.15)

        // 1) SpeechAnalyzer (iOS 26), com o modelo do aparelho.
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: options.locale) {
            let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            let installed = await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == supported.identifier(.bcp47) }
            if installed || options.allowModelDownload {
                do {
                    if !installed, let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        try await request.downloadAndInstall()
                    }
                    let snippets = try await transcribe(audioURL, with: transcriber, meter: meter)
                    return (snippets, snippets.isEmpty ? "não ouvi fala" : nil)
                } catch {
                    if error is CancellationError { throw error }
                    Log.intelligence.error("fala (SpeechAnalyzer): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        // 2) SFSpeechRecognizer no aparelho.
        if let recognizer = SFSpeechRecognizer(locale: options.locale), recognizer.supportsOnDeviceRecognition,
           SFSpeechRecognizer.authorizationStatus() == .authorized {
            let snippets = try await recognize(audioURL, with: recognizer)
            return (snippets, snippets.isEmpty ? "não ouvi fala" : nil)
        }
        return ([], "sem modelo de fala no aparelho (baixa no Wi-Fi)")
    }

    private static func transcribe(_ audioURL: URL, with transcriber: SpeechTranscriber, meter: Meter) async throws -> [VideoSnippet] {
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)
        let total = max(Double(file.length) / file.processingFormat.sampleRate, 0.1)
        let collector = Task { () -> [VideoSnippet] in
            var out: [VideoSnippet] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = result.range.start.seconds
                out.append(VideoSnippet(origin: .speech, seconds: start.isFinite ? start : 0, text: text))
                meter.update(.speech, 0.15 + 0.85 * min((start.isFinite ? start : 0) / total, 1))
            }
            return out
        }
        return try await withTaskCancellationHandler {
            do {
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                collector.cancel()
                throw error
            }
            let snippets = try await collector.value
            meter.update(.speech, 1)
            return snippets
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private static func recognize(_ audioURL: URL, with recognizer: SFSpeechRecognizer) async throws -> [VideoSnippet] {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let snippets = result.bestTranscription.segments.reduce(into: [(Double, String)]()) { acc, segment in
                        // Agrupa em frases de ~6 s.
                        if let last = acc.last, segment.timestamp - last.0 < 6 {
                            acc[acc.count - 1].1 += " " + segment.substring
                        } else {
                            acc.append((segment.timestamp, segment.substring))
                        }
                    }.map { VideoSnippet(origin: .speech, seconds: $0.0, text: $0.1) }
                    if !resumed.withLock({ let was = $0; $0 = true; return was }) { continuation.resume(returning: snippets) }
                } else if let error, !resumed.withLock({ let was = $0; $0 = true; return was }) {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
