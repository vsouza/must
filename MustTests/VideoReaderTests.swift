import AVFoundation
import Foundation
import Testing
import UIKit
@testable import Must

/// Leitura de vídeo no aparelho (prompt 29): OCR de quadros desenhados no teste, junção dos repetidos, cancelar e fala sintetizada.
struct VideoReaderTests {
    /// Vídeo de fixture: cada trecho `(texto, segundos)` desenhado em preto sobre branco, 4 quadros por segundo.
    static func makeVideo(_ parts: [(text: String, seconds: Double)]) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "must-fixture-\(UUID().uuidString).mov")
        let size = CGSize(width: 720, height: 1280)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps = 4
        var frame = 0
        for part in parts {
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                (part.text as NSString).draw(in: CGRect(x: 20, y: 520, width: size.width - 40, height: 300), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.black, .paragraphStyle: style,
                ])
            }
            for _ in 0..<Int(part.seconds * Double(fps)) {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &buffer)
                let pixels = try #require(buffer)
                CVPixelBufferLockBaseAddress(pixels, [])
                let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: Int(size.width), height: Int(size.height),
                                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
                context?.draw(try #require(image.cgImage), in: CGRect(origin: .zero, size: size))
                CVPixelBufferUnlockBaseAddress(pixels, [])
                adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
                frame += 1
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
        return url
    }

    static var screenOnly: VideoReader.Options {
        var options = VideoReader.Options()
        options.readSpeech = false
        options.maxFrames = 30
        return options
    }

    @Test func sampleTimesAreOnePerSecondUpToTheCap() {
        #expect(VideoReader.sampleTimes(duration: 10, maxFrames: 90).count == 10)
        let long = VideoReader.sampleTimes(duration: 300, maxFrames: 90)
        #expect(long.count == 90)
        #expect(long.last! < 300)
        #expect(VideoReader.sampleTimes(duration: 0, maxFrames: 90).isEmpty)
    }

    @Test func ocrFindsTheNameAndMergesRepeatedFrames() async throws {
        let url = try await Self.makeVideo([("Mercado Central", 3), ("Fígado com jiló", 3)])
        defer { try? FileManager.default.removeItem(at: url) }
        let reading = try await VideoReader().read(url, options: Self.screenOnly)
        let joined = reading.screen.map(\.text).joined(separator: " | ").lowercased()
        #expect(joined.contains("mercado central"), "\(joined)")
        // 3 s de quadros repetidos viram uma linha só.
        #expect(reading.screen.filter { VideoText.normalize($0.text).contains("mercadocentral") }.count == 1)
        let merged = reading.merged(caption: nil)
        #expect(merged.contains("[tela 00:00] ") || merged.contains("[tela 00:01] "), "\(merged)")
        let origin = VideoText.origin(of: ["Mercado Central"], in: merged)
        #expect(origin?.origin == .screen)
    }

    @Test func cancelStopsTheRead() async throws {
        let url = try await Self.makeVideo([("Udatsu Sushi", 8)])
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task { try await VideoReader().read(url, options: Self.screenOnly) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unreadableFileFails() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "nao-existe.mov")
        await #expect(throws: VideoReader.ReadError.self) { try await VideoReader().read(url) }
    }

    @Test func reportsProgressUpToDone() async throws {
        let url = try await Self.makeVideo([("Bar do Lulu", 2)])
        defer { try? FileManager.default.removeItem(at: url) }
        let seen = LockedBox<[Double]>([])
        _ = try await VideoReader().read(url, options: Self.screenOnly) { seen.append($0.fraction) }
        let values = seen.value
        #expect(values.first == 0)
        #expect(values.last == 1)
    }

    /// Fala sintetizada gravada em arquivo (sem modelo no simulador a leitura devolve um aviso, nunca quebra).
    @Test func synthesizedSpeechFileReadsWithoutCrashing() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "must-fala-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Self.synthesize("Mercado Central, fígado com jiló", to: url)
        var options = VideoReader.Options()
        options.readScreen = false
        let reading = try await VideoReader().read(url, options: options)
        #expect(reading.duration > 0)
        #expect(reading.speech.isEmpty == false || reading.notes.isEmpty == false)
    }

    @MainActor
    static func synthesize(_ text: String, to url: URL) async throws {
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        let file = LockedBox<AVAudioFile?>(nil)
        let finished = LockedBox<Bool>(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !finished.value { finished.set(true); continuation.resume() }
                    return
                }
                if file.value == nil { file.set(try? AVAudioFile(forWriting: url, settings: pcm.format.settings)) }
                try? file.value?.write(from: pcm)
            }
        }
        withExtendedLifetime(synth) {}
    }
}

/// Caixa mínima pra juntar valores vindos de callbacks `@Sendable` nos testes.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func set(_ value: Value) { lock.withLock { stored = value } }
}

extension LockedBox where Value == [Double] {
    func append(_ item: Double) { lock.withLock { stored.append(item) } }
}
