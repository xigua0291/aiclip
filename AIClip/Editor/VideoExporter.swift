import AVFoundation
import Foundation
import Photos

@MainActor
final class VideoExporter {
    private var session: AVAssetExportSession?
    private var progressTimer: Timer?

    func cancel() {
        session?.cancelExport()
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func export(project: EditProject, progress: @escaping (Double) -> Void) async throws -> URL {
        guard !project.clips.isEmpty else { throw EditorError.emptyTimeline }
        let built = try CompositionBuilder.build(project)
        let composition = built.composition
        let videoComposition = built.videoComposition

        let compatible = AVAssetExportSession.exportPresets(compatibleWith: composition)
        let preferred = [
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality
        ]
        guard let preset = preferred.first(where: { compatible.contains($0) }) else {
            throw EditorError.exportFailed("当前设备没有兼容的导出预设。")
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw EditorError.exportFailed("无法创建导出会话。")
        }
        self.session = session

        let outputURL = MediaStore.makeExportURL()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        if session.supportedFileTypes.contains(.mp4) == false {
            session.outputFileType = session.supportedFileTypes.first ?? .mov
            if session.outputFileType != .mp4 {
                let moved = outputURL.deletingPathExtension().appendingPathExtension("mov")
                session.outputURL = moved
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak session] _ in
                let value = Double(session?.progress ?? 0)
                Task { @MainActor in
                    progress(min(max(value, 0), 1))
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.progressTimer = timer
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        progressTimer?.invalidate()
        progressTimer = nil
        progress(1)

        switch session.status {
        case .completed:
            guard let url = session.outputURL else {
                throw EditorError.exportFailed("导出完成但没有输出文件。")
            }
            return url
        case .cancelled:
            throw EditorError.exportFailed("已取消导出。")
        default:
            let message = session.error?.localizedDescription ?? "未知错误（状态：\(session.status.rawValue)）。"
            throw EditorError.exportFailed(message)
        }
    }

    func saveToPhotoLibrary(fileURL: URL) async throws {
        let status = await requestAddOnlyAccess()
        guard status == .authorized || status == .limited else {
            throw EditorError.photoPermissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: EditorError.exportFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: EditorError.exportFailed("系统未能把视频写入相册。"))
                }
            })
        }
    }

    private func requestAddOnlyAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
