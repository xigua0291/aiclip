import CoreGraphics
import Foundation

struct ClipSegment: Identifiable, Hashable, Codable {
    var id: UUID
    var assetURL: URL
    /// Inclusive start in the source file, in seconds.
    var sourceStart: Double
    /// Exclusive end in the source file, in seconds.
    var sourceEnd: Double
    /// Playback rate. 1.0 is normal. Output duration is sourceDuration / speed.
    var speed: Double
    var filter: ColorFilterID

    init(
        id: UUID = UUID(),
        assetURL: URL,
        sourceStart: Double,
        sourceEnd: Double,
        speed: Double = 1.0,
        filter: ColorFilterID = .none
    ) {
        self.id = id
        self.assetURL = assetURL
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
        self.filter = filter
    }

    var sourceDuration: Double {
        max(0, sourceEnd - sourceStart)
    }

    var outputDuration: Double {
        let rate = max(0.25, speed)
        return sourceDuration / rate
    }

    func sourceTime(forOutputLocal local: Double) -> Double {
        sourceStart + max(0, local) * max(0.25, speed)
    }
}

struct TextOverlay: Identifiable, Hashable, Codable {
    var id: UUID
    var text: String
    var startSeconds: Double
    var durationSeconds: Double
    var position: OverlayPosition
    var fontSize: Double

    init(
        id: UUID = UUID(),
        text: String,
        startSeconds: Double,
        durationSeconds: Double,
        position: OverlayPosition = .bottom,
        fontSize: Double = 42
    ) {
        self.id = id
        self.text = text
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.position = position
        self.fontSize = fontSize
    }

    var endSeconds: Double { startSeconds + durationSeconds }

    func isVisible(at time: Double) -> Bool {
        time >= startSeconds - 0.0001 && time <= endSeconds + 0.0001
    }
}

struct FadeEffect: Identifiable, Hashable, Codable {
    var id: UUID
    var style: FadeStyle
    var startSeconds: Double
    var durationSeconds: Double

    init(
        id: UUID = UUID(),
        style: FadeStyle,
        startSeconds: Double,
        durationSeconds: Double
    ) {
        self.id = id
        self.style = style
        self.startSeconds = startSeconds
        self.durationSeconds = max(0.05, durationSeconds)
    }

    var endSeconds: Double { startSeconds + durationSeconds }

    func opacityContribution(at time: Double) -> Double {
        if time < startSeconds { return style == .fadeIn ? 0 : 1 }
        if time >= endSeconds { return style == .fadeIn ? 1 : 0 }
        let t = (time - startSeconds) / durationSeconds
        switch style {
        case .fadeIn: return min(max(t, 0), 1)
        case .fadeOut: return min(max(1 - t, 0), 1)
        }
    }
}

struct EditProject: Hashable, Codable {
    var clips: [ClipSegment]
    var overlays: [TextOverlay]
    var fades: [FadeEffect]
    /// Render canvas in pixels. Set from the first imported video.
    var canvasWidth: Double
    var canvasHeight: Double
    var frameRate: Double

    init(
        clips: [ClipSegment] = [],
        overlays: [TextOverlay] = [],
        fades: [FadeEffect] = [],
        canvasWidth: Double = 1080,
        canvasHeight: Double = 1920,
        frameRate: Double = 30
    ) {
        self.clips = clips
        self.overlays = overlays
        self.fades = fades
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.frameRate = frameRate
    }

    var canvasSize: CGSize {
        CGSize(width: max(16, canvasWidth), height: max(16, canvasHeight))
    }

    var totalDuration: Double {
        clips.reduce(0) { $0 + $1.outputDuration }
    }

    var isEmpty: Bool { clips.isEmpty }

    func timelineStart(of clipID: UUID) -> Double? {
        var t = 0.0
        for clip in clips {
            if clip.id == clipID { return t }
            t += clip.outputDuration
        }
        return nil
    }

    func timelineRange(of clipID: UUID) -> (start: Double, end: Double)? {
        guard let start = timelineStart(of: clipID),
              let clip = clips.first(where: { $0.id == clipID }) else { return nil }
        return (start, start + clip.outputDuration)
    }

    func clip(atTimeline time: Double) -> (clip: ClipSegment, index: Int, start: Double)? {
        var t = 0.0
        for (index, clip) in clips.enumerated() {
            let end = t + clip.outputDuration
            if time < end || index == clips.count - 1 {
                if time + 0.0001 >= t || index == clips.count - 1 {
                    return (clip, index, t)
                }
            }
            t = end
        }
        return nil
    }

    func opacity(at time: Double) -> Double {
        var alpha = 1.0
        for fade in fades {
            alpha *= fade.opacityContribution(at: time)
        }
        return min(max(alpha, 0), 1)
    }

    /// After a range is removed from the timeline, shift or drop annotations so they stay attached to remaining content.
    mutating func adjustAnnotationsAfterDeleting(rangeStart lo: Double, rangeEnd hi: Double) {
        let cut = max(0, hi - lo)
        overlays = overlays.compactMap { overlay in
            var item = overlay
            let start = overlay.startSeconds
            let end = overlay.endSeconds
            if end <= lo { return item }
            if start >= hi {
                item.startSeconds = start - cut
                return item
            }
            // Overlaps the deleted range: keep the portion that remains after the cut, if any.
            let keptStart = start < lo ? start : lo
            let keptEnd = end > hi ? (end - cut) : lo
            if keptEnd - keptStart < 0.05 { return nil }
            item.startSeconds = keptStart
            item.durationSeconds = keptEnd - keptStart
            return item
        }
        fades = fades.compactMap { fade in
            var item = fade
            let start = fade.startSeconds
            let end = fade.endSeconds
            if end <= lo { return item }
            if start >= hi {
                item.startSeconds = start - cut
                return item
            }
            let keptStart = start < lo ? start : lo
            let keptEnd = end > hi ? (end - cut) : lo
            if keptEnd - keptStart < 0.05 { return nil }
            item.startSeconds = keptStart
            item.durationSeconds = keptEnd - keptStart
            return item
        }
    }
}

struct AssetInfo: Hashable {
    var url: URL
    var duration: Double
    var displayWidth: Double
    var displayHeight: Double
    var frameRate: Double
}
