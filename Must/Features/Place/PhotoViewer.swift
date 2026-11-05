import SwiftUI
import UIKit

/// Foto do Lugar em tela cheia: a foto inteira (sem corte), pinça e toque duplo pra ampliar, arrastar pra baixo fecha.
/// Usa as mesmas URLs da galeria do Lugar, pelo `PhotoLoader` (memória/disco): abrir não baixa nada novo.
/// O crédito fica sempre visível (regra do Commons / Google).
struct PhotoViewer: View {
    struct Page: Identifiable, Hashable {
        var id: Int
        var url: URL?
        var credit: String
    }

    var pages: [Page]
    @State var index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var dragY: CGFloat = 0
    /// Ampliada: o arrasto é do zoom, não fecha.
    @State private var zoomed = false

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(abs(dragY) / 400, 0.6)).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(pages) { page in
                    ZoomablePhoto(url: page.url, zoomed: $zoomed)
                        .tag(page.id)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            .offset(y: dragY)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard !zoomed, abs(value.translation.height) > abs(value.translation.width) else { return }
                        dragY = value.translation.height
                    }
                    .onEnded { value in
                        guard !zoomed else { return }
                        if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                            dismiss()
                        } else {
                            withAnimation(.snappy) { dragY = 0 }
                        }
                    }
            )
            .accessibilityHint("Toque duplo amplia. Arraste pra baixo pra fechar.")

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(V8.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(V8.ink.opacity(0.7)))
                    }
                    .accessibilityLabel("Fechar foto")
                }
                .padding(.horizontal, 16)
                Spacer()
                if let page = pages.first(where: { $0.id == index }), !page.credit.isEmpty {
                    Text(page.credit.uppercased())
                        .font(V8Font.mono(9))
                        .tracking(0.9)
                        .foregroundStyle(V8.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(V8.ink.opacity(0.7)))
                        .padding(.bottom, pages.count > 1 ? 36 : 16)
                }
            }
            .opacity(dragY == 0 ? 1 : 0.4)
        }
        .statusBarHidden()
    }
}

/// Uma foto com zoom de verdade (UIScrollView): cabe inteira na tela, pinça até 5×, toque duplo alterna 1× / 2,5×.
private struct ZoomablePhoto: View {
    var url: URL?
    @Binding var zoomed: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomScroll(image: image, zoomed: $zoomed)
            } else {
                ProgressView().tint(V8.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await PhotoLoader.load(url)
        }
    }
}

private struct ZoomScroll: UIViewRepresentable {
    var image: UIImage
    @Binding var zoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(zoomed: $zoomed) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Foto do lugar"
        scroll.addSubview(view)
        context.coordinator.imageView = view
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.layout(scroll)
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var zoomed: Bool
        weak var imageView: UIImageView?

        init(zoomed: Binding<Bool>) { _zoomed = zoomed }

        func layout(_ scroll: UIScrollView) {
            guard let imageView, scroll.zoomScale == 1 else { return }
            DispatchQueue.main.async {
                imageView.frame = CGRect(origin: .zero, size: scroll.bounds.size)
                scroll.contentSize = scroll.bounds.size
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let isZoomed = scrollView.zoomScale > 1.01
            if zoomed != isZoomed { zoomed = isZoomed }
        }

        @objc func doubleTapped(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = tap.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}
