import Foundation

enum MediaStore {
    static var videosDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AIClip/Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var exportDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AIClip/Export", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func copyImportedVideo(from temporaryURL: URL) throws -> URL {
        let ext = temporaryURL.pathExtension.isEmpty ? "mov" : temporaryURL.pathExtension
        let dest = videosDirectory.appendingPathComponent("clip-\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: temporaryURL, to: dest)
        return dest
    }

    static func makeExportURL() -> URL {
        exportDirectory.appendingPathComponent("aiclip-\(UUID().uuidString).mp4")
    }
}
