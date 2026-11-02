import SwiftUI
import VisionKit

/// TicketScan (`design/screens/TicketScan.png`): câmera com `DataScannerViewController` (VisionKit) e o card "Encontrei".
struct TicketScanView: View {
    @Bindable var model: TicketImportModel
    var back: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if TicketScanner.isAvailable {
                CodeScannerView(onUpdate: { model.scanUpdated($0) }).ignoresSafeArea()
            } else {
                Color(hex: 0x17181C).ignoresSafeArea()
                Text("Câmera de leitura indisponível aqui.").mustBody().foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconButton(.fechar, style: .glass, label: "Voltar pra entrada", action: back)
                    Spacer()
                    Micro("escanear · 2 de 3", color: .white.opacity(0.6))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, 8)
                Text("Aponte pro ingresso").font(.must.archivo(30, .semibold)).foregroundStyle(.white).padding(.top, 18)
                Text("QR, código de barras ou o papel inteiro — pode ser a tela de outro app")
                    .mustSerif(18).foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                Spacer()
                if let scanned = model.scanned, !scanned.codes.isEmpty || !scanned.text.isEmpty {
                    foundCard(scanned)
                } else if !TicketScanner.isAvailable {
                    GhostButton("Voltar e usar Fotos ou Arquivo", action: back).padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(hex: 0x17181C))
    }

    private func foundCard(_ scanned: TicketImportModel.ScanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                KanjiSeal(done: true, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encontrei: \(model.scanPreview ?? "um código")").font(.must.archivo(17, .semibold)).foregroundStyle(Color.must.ink)
                    if let code = scanned.codes.first {
                        Text("código \(code)").font(.must.mono(13)).foregroundStyle(Color.must.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                PrimaryButton("Conferir e salvar") { Task { await model.scannedConfirm() } }
                GhostButton("Outra foto") {
                    model.scanned = nil
                    model.scanPreview = nil
                }
                .frame(width: 130)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.bottom, 24)
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
