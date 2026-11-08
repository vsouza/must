#if DEBUG
import Foundation
import UIKit

/// Ingresso de exemplo pros prints (`-debugScreen ingresso-revisar`): um PDF de experiência escrito na caixa
/// do Share Extension, como se tivesse vindo do Mail.
enum TicketSamples {
    /// Grava o PDF na caixa e devolve o id (o que a `must://import?id=` levaria).
    @MainActor
    static func stashSamplePDF() -> String? {
        let url = FileManager.default.temporaryDirectory.appending(path: "viator-sample.pdf")
        do {
            try pdfData().write(to: url, options: .atomic)
            return try ShareInbox.stash(fileAt: url, kind: .pdf).id
        } catch {
            Log.app.error("ingresso de exemplo: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @MainActor
    static func pdfData() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let lines = [
            "teamLab Planets TOKYO",
            "Admission Ticket · Date-time designated",
            "Visit date: 16 Nov 2026",
            "Entry time: 10:30 - 11:00",
            "Venue: 6-1-16 Toyosu, Koto City, Tokyo 135-0061",
            "Gate A · Seat 12A",
            "Adult x 2 · ¥4,200 each",
            "Ticket No. TLP-8F3K-2291",
            "Name: SOUZA VINICIUS",
        ]
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 60
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                y += 24
            }
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 370, y: 410, width: 200, height: 200))
            TicketQR.image(for: "TLP-8F3K-2291", points: 180)?.draw(in: CGRect(x: 380, y: 420, width: 180, height: 180))
        }
    }
}
#endif
