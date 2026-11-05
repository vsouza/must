import SwiftUI
import UIKit

/// Cartaz → PNG 1080×1920 e viagem → PDF (um dia por página, o mesmo desenho em vetor). `ImageRenderer` roda no main;
/// chamar fora do `body` (num `.task`/ação), nunca a cada redesenho.
@MainActor
enum DayPosterRenderer {
    /// Multiplicador dos pontos (360×640) pros pixels do cartaz.
    static let scale: CGFloat = 3
    static var pixelSize: CGSize { CGSize(width: DayPosterView.size.width * scale, height: DayPosterView.size.height * scale) }

    static func image(_ poster: DayPoster, options: PosterOptions) -> UIImage? {
        let renderer = ImageRenderer(content: DayPosterView(poster: poster, options: options))
        renderer.scale = scale
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(DayPosterView.size)
        return renderer.uiImage
    }

    static func png(_ poster: DayPoster, options: PosterOptions) -> Data? {
        image(poster, options: options)?.pngData()
    }

    /// Um dia por página, página do tamanho do cartaz (9:16, em pontos).
    static func pdf(_ posters: [DayPoster], options: PosterOptions) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: DayPosterView.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle as String: "Must · a viagem"] as CFDictionary)
        else { return Data() }
        for poster in posters {
            let renderer = ImageRenderer(content: DayPosterView(poster: poster, options: options))
            renderer.proposedSize = ProposedViewSize(DayPosterView.size)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
    }

    /// Grava no temporário com um nome legível (é o nome que aparece no WhatsApp) e devolve a URL.
    static func write(_ data: Data, name: String) -> URL? {
        let dir = URL.temporaryDirectory.appending(path: "must-share", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.app.error("cartaz: não gravou \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
