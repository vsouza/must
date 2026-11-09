import SwiftUI
import VisionKit

/// Escanear (V9): câmera com `DataScannerViewController` (VisionKit), título e Voltar do sistema, e o card "Encontrei".
struct TicketScanView: View {
    @Bindable var model: TicketImportModel
    var back: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if TicketScanner.isAvailable {
                CodeScannerView(onUpdate: { model.scanUpdated($0) }).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("Câmera de leitura indisponível aqui.").foregroundStyle(.white)
            }
            VStack(spacing: 12) {
                Text("Aponte pro ingresso: QR, código de barras ou o papel inteiro.")
                    .font(.subheadline).multilineTextAlignment(.center)
                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
                if let scanned = model.scanned, !scanned.codes.isEmpty || !scanned.text.isEmpty {
                    foundCard(scanned)
                } else if !TicketScanner.isAvailable {
                    Button("Voltar e usar Fotos ou Arquivo", action: back).v9Secondary()
                }
            }
            .padding(V9.gutter)
        }
        .navigationTitle("Escanear")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func foundCard(_ scanned: TicketImportModel.ScanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Encontrei: \(model.scanPreview ?? "um código")", systemImage: "checkmark.circle.fill")
                .font(.headline)
            if let code = scanned.codes.first {
                Text("código \(code)").font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                Button("Conferir e salvar") { Task { await model.scannedConfirm() } }.v9Primary()
                Button("Outra leitura") {
                    model.scanned = nil
                    model.scanPreview = nil
                }.v9Secondary()
            }
        }
        .v9Card()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
    }
}

/// Câmera de códigos e texto (VisionKit). No simulador e em aparelho sem suporte, `isAvailable` é falso.
enum TicketScanner {
    @MainActor
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
}

struct CodeScannerView: UIViewControllerRepresentable {
    var onUpdate: (TicketImportModel.ScanSnapshot) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .aztec, .pdf417, .code128]), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onUpdate: onUpdate) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onUpdate: (TicketImportModel.ScanSnapshot) -> Void

        init(onUpdate: @escaping (TicketImportModel.ScanSnapshot) -> Void) {
            self.onUpdate = onUpdate
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            var codes: [String] = []
            var lines: [String] = []
            for item in items {
                switch item {
                case .barcode(let barcode):
                    if let payload = barcode.payloadStringValue, !payload.isEmpty { codes.append(payload) }
                case .text(let text):
                    lines.append(text.transcript)
                @unknown default:
                    break
                }
            }
            onUpdate(TicketImportModel.ScanSnapshot(codes: codes, text: lines.joined(separator: "\n")))
        }
    }
}
