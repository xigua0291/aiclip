import Foundation

enum EditorError: LocalizedError {
    case noVideoSelected
    case noVideoTrack
    case emptyTimeline
    case copyFailed
    case photoPermissionDenied
    case exportFailed(String)
    case invalidTimeRange
    case unsupportedSpeed

    var errorDescription: String? {
        switch self {
        case .noVideoSelected:
            return "请先从相册导入视频。"
        case .noVideoTrack:
            return "这个文件里没有可用的视频轨道。"
        case .emptyTimeline:
            return "时间线上没有可导出的片段。"
        case .copyFailed:
            return "导入视频失败，请重试。"
        case .photoPermissionDenied:
            return "没有相册写入权限，无法保存导出的视频。请在系统设置中允许「智能剪辑」添加照片。"
        case .exportFailed(let message):
            return "导出失败：\(message)"
        case .invalidTimeRange:
            return "时间范围无效。"
        case .unsupportedSpeed:
            return "倍速需要在 0.25× 到 4× 之间。"
        }
    }
}
