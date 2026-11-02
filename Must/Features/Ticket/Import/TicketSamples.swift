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
            "Viator · Confirmação de reserva",
            "Sushi Making Class with a Chef in Tsukiji",
            "Reference BR-7K2M-9931",
            "Sat 15 Nov 2026 · 10:00 AM",
            "2 travelers · ¥24,000 total paid",
            "Meeting point: Tsukiji Outer Market, Gate 1",
            "Free cancellation until 13 Nov 2026",
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
            TicketQR.image(for: "BR-7K2M-9931", points: 180)?.draw(in: CGRect(x: 380, y: 420, width: 180, height: 180))
        }
    }
}
#endif
