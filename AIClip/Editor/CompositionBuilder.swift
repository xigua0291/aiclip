import AVFoundation
import CoreGraphics
import Foundation

struct BuiltComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let duration: Double
    let renderSize: CGSize
}

enum CompositionBuilder {
    static let videoTrackID: CMPersistentTrackID = 1
    static let audioTrackID: CMPersistentTrackID = 2

    static func displaySize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let applied = naturalSize.applying(transform)
        return CGSize(width: abs(applied.width), height: abs(applied.height))
    }

    static func loadAssetInfo(url: URL) async throws -> AssetInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw EditorError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let display = displaySize(naturalSize: naturalSize, transform: transform)
        return AssetInfo(
            url: url,
            duration: duration.seconds,
            displayWidth: display.width,
            displayHeight: display.height,
            frameRate: fps > 1 ? Double(fps) : 30
        )
    }

    static func build(_ project: EditProject) throws -> BuiltComposition {
        guard !project.clips.isEmpty else { throw EditorError.emptyTimeline }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: videoTrackID
        ) else {
            throw EditorError.noVideoTrack
        }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: audioTrackID
        )

        var cursor = CMTime.zero
        var instructions: [EditInstruction] = []
        let renderSize = project.canvasSize
        let frameRate = max(15, min(project.frameRate, 60))

        for clip in project.clips {
            let asset = AVURLAsset(url: clip.assetURL)
            let sourceRange = MediaTime.range(start: clip.sourceStart, end: clip.sourceEnd)
            guard sourceRange.duration.seconds > 0.01 else { continue }

            let outputDuration = MediaTime.time(seconds: clip.outputDuration)
            let insertStart = cursor

            if let srcVideo = asset.tracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(sourceRange, of: srcVideo, at: insertStart)
                if abs(clip.speed - 1.0) > 0.001 {
                    let insertedRange = CMTimeRange(start: insertStart, duration: sourceRange.duration)
                    videoTrack.scaleTimeRange(insertedRange, toDuration: outputDuration)
                }

                let info = TrackGeometry(
                    naturalSize: srcVideo.naturalSize,
                    preferredTransform: srcVideo.preferredTransform
                )
                let instruction = EditInstruction(
                    timeRange: CMTimeRange(start: insertStart, duration: outputDuration),
                    sourceTrackID: videoTrackID,
                    geometry: info,
                    renderSize: renderSize,
                    filter: clip.filter,
                    overlays: project.overlays,
                    fades: project.fades,
                    projectDuration: project.totalDuration
                )
                instructions.append(instruction)
            }

            if let audioTrack, let srcAudio = asset.tracks(withMediaType: .audio).first {
                do {
                    try audioTrack.insertTimeRange(sourceRange, of: srcAudio, at: insertStart)
                    if abs(clip.speed - 1.0) > 0.001 {
                        let insertedRange = CMTimeRange(start: insertStart, duration: sourceRange.duration)
                        audioTrack.scaleTimeRange(insertedRange, toDuration: outputDuration)
                    }
                } catch {
                    // Some files have an audio track that cannot be inserted for a sub-range; skip audio for this clip.
                }
            }

            cursor = CMTimeAdd(insertStart, outputDuration)
        }

        guard !instructions.isEmpty else { throw EditorError.noVideoTrack }

        composition.removeEmptyTracks()

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, Int(frameRate.rounded()))))
        videoComposition.renderSize = renderSize
        videoComposition.renderScale = 1.0
        videoComposition.instructions = instructions
        videoComposition.customVideoCompositorClass = EditCompositor.self
        if #available(iOS 17.0, *) {
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        }

        return BuiltComposition(
            composition: composition,
            videoComposition: videoComposition,
            duration: cursor.seconds,
            renderSize: renderSize
        )
    }
}

private extension AVMutableComposition {
    func removeEmptyTracks() {
        for track in tracks where track.timeRange.duration.seconds <= 0 {
            removeTrack(track)
        }
    }
}

struct TrackGeometry: Hashable {
    var naturalSize: CGSize
    var preferredTransform: CGAffineTransform

    var displaySize: CGSize {
        CompositionBuilder.displaySize(naturalSize: naturalSize, transform: preferredTransform)
    }

    /// Transform that maps the raw sample buffer into a positive, upright pixel space of `displaySize`.
    func uprightTransform() -> CGAffineTransform {
        var transform = preferredTransform
        let upright = CGRect(origin: .zero, size: naturalSize).applying(transform)
        transform = transform.concatenating(CGAffineTransform(translationX: -upright.origin.x, y: -upright.origin.y))
        return transform
    }
}
