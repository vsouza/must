import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// QR do ingresso gerado no aparelho (CoreImage, sem rede).
enum TicketQR {
    /// `payload` vira uma imagem quadrada de ~`points` pt. `nil` se o texto estiver vazio.
    static func image(for payload: String, points: CGFloat = 220) -> UIImage? {
        guard !payload.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: points / output.extent.width, y: points / output.extent.width))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
