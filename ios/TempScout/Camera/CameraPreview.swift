import AVFoundation
import SwiftUI

/// The live camera picture, plus the job of turning "the white square on screen" into "that part of the camera frame".
struct CameraPreview: UIViewRepresentable {
    let controller: CameraController
    /// The measure square, in this view's own coordinates (the view fills the whole screen)
    var targetRect: CGRect

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.targetRect = targetRect
        view.onMeasureRect = { [weak controller] rect in controller?.setMeasureRect(rect) }
        view.reportMeasureRect()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var targetRect: CGRect = .zero
    var onMeasureRect: ((CGRect) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        reportMeasureRect()
    }

    /// The picture is scaled and cropped to fill the screen, so ask the preview layer where the square really
    /// lands in the camera frame (0-1 in both directions). All four corners are converted so rotation is handled.
    func reportMeasureRect() {
        guard targetRect.width > 0, bounds.width > 0 else { return }
        let corners = [
            CGPoint(x: targetRect.minX, y: targetRect.minY), CGPoint(x: targetRect.maxX, y: targetRect.minY),
            CGPoint(x: targetRect.minX, y: targetRect.maxY), CGPoint(x: targetRect.maxX, y: targetRect.maxY)
        ].map { previewLayer.captureDevicePointConverted(fromLayerPoint: $0) }
        let xs = corners.map { $0.x }, ys = corners.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
        onMeasureRect?(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }
}
