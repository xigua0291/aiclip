import Foundation
import CoreMedia

enum TimeFormatting {
    /// Formats seconds as m:ss or m:ss.d depending on `showTenths`.
    static func string(from seconds: Double, showTenths: Bool = true) -> String {
        guard seconds.isFinite, seconds >= 0 else { return showTenths ? "0:00.0" : "0:00" }
        let totalTenths = Int((seconds * 10).rounded(.down))
        let tenths = totalTenths % 10
        let totalSeconds = totalTenths / 10
        let s = totalSeconds % 60
        let m = totalSeconds / 60
        if showTenths {
            return String(format: "%d:%02d.%d", m, s, tenths)
        }
        return String(format: "%d:%02d", m, s)
    }
}

enum MediaTime {
    static let timescale: CMTimeScale = 600

    static func time(seconds: Double) -> CMTime {
        guard seconds.isFinite else { return .zero }
        return CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
    }

    static func seconds(_ time: CMTime) -> Double {
        guard time.isNumeric else { return 0 }
        return time.seconds
    }

    static func range(start: Double, end: Double) -> CMTimeRange {
        let s = time(seconds: start)
        let e = time(seconds: end)
        let duration = CMTimeSubtract(e, s)
        return CMTimeRange(start: s, duration: duration)
    }
}
