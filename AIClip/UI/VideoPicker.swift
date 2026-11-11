import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onPicked: (URL) -> Void
    var onFailed: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onFailed: onFailed, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.onPicked = onPicked
        context.coordinator.onFailed = onFailed
        context.coordinator.dismiss = dismiss
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPicked: (URL) -> Void
        var onFailed: (String) -> Void
        var dismiss: DismissAction

        init(onPicked: @escaping (URL) -> Void, onFailed: @escaping (String) -> Void, dismiss: DismissAction) {
            self.onPicked = onPicked
            self.onFailed = onFailed
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // This controller is presented by a SwiftUI sheet; dismiss the sheet instead of the picker itself.
            DispatchQueue.main.async { self.dismiss() }
            guard let provider = results.first?.itemProvider else { return }
            let type: UTType
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                type = .movie
            } else if provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
                type = .mpeg4Movie
            } else {
                type = .audiovisualContent
            }
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onFailed("导入失败：\(error.localizedDescription)")
                    }
                    return
                }
                guard let url else {
                    DispatchQueue.main.async { self.onFailed("没有拿到视频文件。") }
                    return
                }
                // The provided URL is temporary and is deleted when this callback returns. Copy first.
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("aiclip-import-\(UUID().uuidString).\(ext)")
                do {
                    if FileManager.default.fileExists(atPath: temp.path) {
                        try FileManager.default.removeItem(at: temp)
                    }
                    try FileManager.default.copyItem(at: url, to: temp)
                    DispatchQueue.main.async { self.onPicked(temp) }
                } catch {
                    DispatchQueue.main.async { self.onFailed("复制视频失败：\(error.localizedDescription)") }
                }
            }
        }
    }
}
