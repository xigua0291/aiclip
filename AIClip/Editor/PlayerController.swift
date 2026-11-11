import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .pause
    }

    deinit {
        // Observers are removed in shutdown() from the main actor before release when possible.
    }

    func shutdown() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
            self.statusObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    func replace(item: AVPlayerItem?, duration: Double) {
        let restore = currentTime
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        self.duration = max(0, duration)
        currentTime = min(restore, self.duration)
        player.replaceCurrentItem(with: item)
        attachObservers()
        if let item {
            let seekTime = MediaTime.time(seconds: currentTime)
            item.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func play() {
        guard player.currentItem != nil else { return }
        if currentTime >= duration - 0.05, duration > 0 {
            seek(to: 0)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), max(duration, 0))
        currentTime = clamped
        let time = MediaTime.time(seconds: clamped)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func attachObservers() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.isNumeric {
                    self.currentTime = min(max(0, time.seconds), self.duration)
                }
                self.isPlaying = self.player.rate > 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }
}
