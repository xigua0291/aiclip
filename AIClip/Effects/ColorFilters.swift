import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ColorFilterID: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case vivid
    case mono
    case warm
    case cool
    case vintage
    case cinema

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "原片"
        case .vivid: return "鲜艳"
        case .mono: return "黑白"
        case .warm: return "暖色"
        case .cool: return "冷色"
        case .vintage: return "复古"
        case .cinema: return "电影"
        }
    }

    init(parsing raw: String) {
        self = ColorFilterID.resolve(raw) ?? .none
    }

    /// Returns nil when the name is not a supported filter, so callers can ignore it safely.
    static func resolve(_ raw: String) -> ColorFilterID? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "none", "原片", "无", "off":
            return .none
        case "vivid", "鲜艳", "饱和":
            return .vivid
        case "mono", "monochrome", "blackwhite", "黑白", "黑白滤镜":
            return .mono
        case "warm", "暖色", "温暖":
            return .warm
        case "cool", "冷色", "冷静":
            return .cool
        case "vintage", "复古", "怀旧":
            return .vintage
        case "cinema", "cinematic", "电影", "电影感":
            return .cinema
        default:
            return ColorFilterID(rawValue: key)
        }
    }

    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image
        case .vivid:
            let vibrance = image.applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.75])
            return vibrance.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.18,
                kCIInputContrastKey: 1.06
            ])
        case .mono:
            return image.applyingFilter("CIPhotoEffectMono")
        case .warm:
            let warmed = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5200, y: 16)
            ])
            return warmed.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.08
            ])
        case .cool:
            return image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 8200, y: -12)
            ])
        case .vintage:
            let transfer = image.applyingFilter("CIPhotoEffectTransfer")
            return transfer.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 0.65,
                kCIInputRadiusKey: 1.4
            ])
        case .cinema:
            let graded = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.82,
                kCIInputContrastKey: 1.14,
                kCIInputBrightnessKey: -0.03
            ])
            return graded.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 0.45,
                kCIInputRadiusKey: 1.6
            ])
        }
    }
}

enum OverlayPosition: String, Codable, CaseIterable, Identifiable, Hashable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "顶部"
        case .center: return "居中"
        case .bottom: return "底部"
        }
    }

    init(parsing raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "top", "顶部", "上方": self = .top
        case "center", "middle", "居中", "中间": self = .center
        default: self = .bottom
        }
    }
}

enum FadeStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case fadeIn = "in"
    case fadeOut = "out"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fadeIn: return "淡入"
        case .fadeOut: return "淡出"
        }
    }

    init(parsing raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "in", "fadein", "fade-in", "淡入":
            self = .fadeIn
        default:
            self = .fadeOut
        }
    }
}
