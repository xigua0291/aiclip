import AVFoundation
import CoreImage
import Foundation
import UIKit
import Metal

final class EditInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = true
    var containsTweening: Bool = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let sourceTrackID: CMPersistentTrackID
    let geometry: TrackGeometry
    let renderSize: CGSize
    let filter: ColorFilterID
    let overlays: [TextOverlay]
    let fades: [FadeEffect]
    let projectDuration: Double

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        geometry: TrackGeometry,
        renderSize: CGSize,
        filter: ColorFilterID,
        overlays: [TextOverlay],
        fades: [FadeEffect],
        projectDuration: Double
    ) {
        self.timeRange = timeRange
        self.sourceTrackID = sourceTrackID
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID) as NSValue]
        self.geometry = geometry
        self.renderSize = renderSize
        self.filter = filter
        self.overlays = overlays
        self.fades = fades
        self.projectDuration = projectDuration
        super.init()
    }
}

final class EditCompositor: NSObject, AVVideoCompositing {
    private let renderLock = NSLock()
    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .workingColorSpace: NSNull()
            ])
        }
        return CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: NSNull()
        ])
    }()

    var sourcePixelBufferAttributes: [String: Any]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    var supportsWideColorSourceFrames: Bool { false }
    var supportsHDRSourceFrames: Bool { false }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderLock.lock()
        renderContext = newRenderContext
        renderLock.unlock()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            do {
                let buffer = try render(request)
                request.finish(withComposedVideoFrame: buffer)
            } catch {
                request.finish(with: error)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    private func render(_ request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        guard let instruction = request.videoCompositionInstruction as? EditInstruction else {
            throw CompositorError.badInstruction
        }
        guard let sourceBuffer = request.sourceFrame(byTrackID: instruction.sourceTrackID) else {
            throw CompositorError.missingSource
        }
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            throw CompositorError.noOutputBuffer
        }

        let renderSize = request.renderContext.size
        let canvas = CGRect(origin: .zero, size: renderSize)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: canvas)

        var frame = CIImage(cvPixelBuffer: sourceBuffer)
        frame = frame.transformed(by: instruction.geometry.uprightTransform())
        let uprightExtent = frame.extent
        if uprightExtent.origin != .zero {
            frame = frame.transformed(by: CGAffineTransform(
                translationX: -uprightExtent.origin.x,
                y: -uprightExtent.origin.y
            ))
        }

        let display = CGSize(width: max(1, frame.extent.width), height: max(1, frame.extent.height))
        let scale = min(renderSize.width / display.width, renderSize.height / display.height)
        frame = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaled = frame.extent
        let ox = (renderSize.width - scaled.width) / 2 - scaled.origin.x
        let oy = (renderSize.height - scaled.height) / 2 - scaled.origin.y
        frame = frame.transformed(by: CGAffineTransform(translationX: ox, y: oy))

        frame = instruction.filter.apply(to: frame)
        var output = frame.cropped(to: canvas).composited(over: background)

        let time = request.compositionTime.seconds
        let alpha = opacity(at: time, fades: instruction.fades)
        if alpha < 0.999 {
            output = fade(output, alpha: alpha, canvas: canvas)
        }

        let visibleOverlays = instruction.overlays.filter { $0.isVisible(at: time) }
        if !visibleOverlays.isEmpty, let textImage = TextRenderer.image(overlays: visibleOverlays, canvas: renderSize) {
            output = textImage.composited(over: output)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        ciContext.render(output, to: outputBuffer, bounds: canvas, colorSpace: colorSpace)
        return outputBuffer
    }

    private func opacity(at time: Double, fades: [FadeEffect]) -> Double {
        var alpha = 1.0
        for fade in fades {
            alpha *= fade.opacityContribution(at: time)
        }
        return min(max(alpha, 0), 1)
    }

    private func fade(_ image: CIImage, alpha: Double, canvas: CGRect) -> CIImage {
        let clamped = min(max(alpha, 0), 1)
        let faded = image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: clamped)
        ])
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: canvas)
        return faded.composited(over: black)
    }
}

private enum CompositorError: LocalizedError {
    case badInstruction
    case missingSource
    case noOutputBuffer

    var errorDescription: String? {
        switch self {
        case .badInstruction: return "合成指令无效。"
        case .missingSource: return "缺少源视频帧。"
        case .noOutputBuffer: return "无法创建输出像素缓冲。"
        }
    }
}

enum TextRenderer {
    static func image(overlays: [TextOverlay], canvas: CGSize) -> CIImage? {
        guard !overlays.isEmpty, canvas.width > 1, canvas.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let uiImage = renderer.image { _ in
            for overlay in overlays {
                let text = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let fontSize = max(16, min(overlay.fontSize, canvas.height / 6))
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3.0
                ]
                let maxWidth = canvas.width * 0.9
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let bounding = attributed.boundingRect(
                    with: CGSize(width: maxWidth, height: canvas.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let x = (canvas.width - bounding.width) / 2
                let y: CGFloat
                switch overlay.position {
                case .top:
                    y = canvas.height * 0.08
                case .center:
                    y = (canvas.height - bounding.height) / 2
                case .bottom:
                    y = canvas.height * 0.84 - bounding.height
                }
                let rect = CGRect(x: x, y: y, width: bounding.width, height: ceil(bounding.height))
                attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
        }
        guard let cgImage = uiImage.cgImage else { return nil }
        // Core Image has a flipped y-axis relative to UIKit. Flip the overlay back.
        let ci = CIImage(cgImage: cgImage)
        let flipped = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: canvas.height))
        return flipped
    }
}
