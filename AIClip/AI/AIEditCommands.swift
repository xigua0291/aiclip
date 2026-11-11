import Foundation

/// Versioned edit-decision list returned by an AI backend or the local demo parser.
struct AIEditPlan: Codable, Equatable {
    static let currentSchemaVersion = "1.0"

    var schemaVersion: String
    var operations: [AIEditCommand]

    init(schemaVersion: String = AIEditPlan.currentSchemaVersion, operations: [AIEditCommand]) {
        self.schemaVersion = schemaVersion
        self.operations = operations
    }
}

/// Context payload sent to the model together with the user instruction.
struct AIProjectContext: Codable, Equatable {
    struct Clip: Codable, Equatable {
        var id: String
        var index: Int
        var timelineStart: Double
        var timelineEnd: Double
        var sourceStart: Double
        var sourceEnd: Double
        var speed: Double
        var filter: String
    }

    struct Overlay: Codable, Equatable {
        var id: String
        var text: String
        var startSeconds: Double
        var durationSeconds: Double
        var position: String
    }

    struct Fade: Codable, Equatable {
        var id: String
        var style: String
        var startSeconds: Double
        var durationSeconds: Double
    }

    var schemaVersion: String
    var durationSeconds: Double
    var playheadSeconds: Double
    var selectedClipId: String?
    var canvasWidth: Double
    var canvasHeight: Double
    var clips: [Clip]
    var textOverlays: [Overlay]
    var fades: [Fade]
}

enum AIEditCommand: Equatable {
    case trim(clipId: String?, startSeconds: Double?, endSeconds: Double?)
    case split(timeSeconds: Double?)
    case deleteRange(startSeconds: Double, endSeconds: Double)
    case deleteClip(clipId: String)
    case setSpeed(clipId: String?, speed: Double)
    case addFilter(clipId: String?, filter: ColorFilterID)
    case addTextOverlay(text: String, startSeconds: Double?, durationSeconds: Double?, position: OverlayPosition, fontSize: Double?)
    case removeTextOverlays
    case addFade(style: FadeStyle, startSeconds: Double?, durationSeconds: Double?)
    case reorder(clipIds: [String])
    case unknown(name: String)

    var opName: String {
        switch self {
        case .trim: return "trim"
        case .split: return "split"
        case .deleteRange: return "deleteRange"
        case .deleteClip: return "deleteClip"
        case .setSpeed: return "setSpeed"
        case .addFilter: return "addFilter"
        case .addTextOverlay: return "addTextOverlay"
        case .removeTextOverlays: return "removeTextOverlays"
        case .addFade: return "addFade"
        case .reorder: return "reorder"
        case .unknown(let name): return name
        }
    }
}

extension AIEditCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case op
        case clipId
        case startSeconds
        case endSeconds
        case timeSeconds
        case speed
        case filter
        case text
        case durationSeconds
        case position
        case fontSize
        case style
        case type
        case clipIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = (try c.decodeIfPresent(String.self, forKey: .op) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch op {
        case "trim":
            self = .trim(
                clipId: Self.emptyToNil(try c.decodeIfPresent(String.self, forKey: .clipId)),
                startSeconds: try c.decodeIfPresent(Double.self, forKey: .startSeconds),
                endSeconds: try c.decodeIfPresent(Double.self, forKey: .endSeconds)
            )
        case "split":
            self = .split(timeSeconds: try c.decodeIfPresent(Double.self, forKey: .timeSeconds))
        case "deleteRange":
            let start = try c.decode(Double.self, forKey: .startSeconds)
            let end = try c.decode(Double.self, forKey: .endSeconds)
            self = .deleteRange(startSeconds: start, endSeconds: end)
        case "deleteClip":
            let id = try c.decode(String.self, forKey: .clipId)
            self = .deleteClip(clipId: id)
        case "setSpeed":
            let speed = try c.decode(Double.self, forKey: .speed)
            self = .setSpeed(
                clipId: Self.emptyToNil(try c.decodeIfPresent(String.self, forKey: .clipId)),
                speed: speed
            )
        case "addFilter":
            let raw = try c.decode(String.self, forKey: .filter)
            if let filter = ColorFilterID.resolve(raw) {
                self = .addFilter(
                    clipId: Self.emptyToNil(try c.decodeIfPresent(String.self, forKey: .clipId)),
                    filter: filter
                )
            } else {
                self = .unknown(name: "addFilter:\(raw)")
            }
        case "addTextOverlay":
            let text = try c.decode(String.self, forKey: .text)
            let positionRaw = try c.decodeIfPresent(String.self, forKey: .position) ?? "bottom"
            self = .addTextOverlay(
                text: text,
                startSeconds: try c.decodeIfPresent(Double.self, forKey: .startSeconds),
                durationSeconds: try c.decodeIfPresent(Double.self, forKey: .durationSeconds),
                position: OverlayPosition(parsing: positionRaw),
                fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize)
            )
        case "removeTextOverlays":
            self = .removeTextOverlays
        case "addFade":
            let styleRaw = (try c.decodeIfPresent(String.self, forKey: .style))
                ?? (try c.decodeIfPresent(String.self, forKey: .type))
                ?? "in"
            self = .addFade(
                style: FadeStyle(parsing: styleRaw),
                startSeconds: try c.decodeIfPresent(Double.self, forKey: .startSeconds),
                durationSeconds: try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
            )
        case "reorder":
            let ids = try c.decode([String].self, forKey: .clipIds)
            self = .reorder(clipIds: ids)
        default:
            self = .unknown(name: op.isEmpty ? "missing_op" : op)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(opName, forKey: .op)
        switch self {
        case .trim(let clipId, let start, let end):
            try c.encodeIfPresent(clipId, forKey: .clipId)
            try c.encodeIfPresent(start, forKey: .startSeconds)
            try c.encodeIfPresent(end, forKey: .endSeconds)
        case .split(let time):
            try c.encodeIfPresent(time, forKey: .timeSeconds)
        case .deleteRange(let start, let end):
            try c.encode(start, forKey: .startSeconds)
            try c.encode(end, forKey: .endSeconds)
        case .deleteClip(let clipId):
            try c.encode(clipId, forKey: .clipId)
        case .setSpeed(let clipId, let speed):
            try c.encodeIfPresent(clipId, forKey: .clipId)
            try c.encode(speed, forKey: .speed)
        case .addFilter(let clipId, let filter):
            try c.encodeIfPresent(clipId, forKey: .clipId)
            try c.encode(filter.rawValue, forKey: .filter)
        case .addTextOverlay(let text, let start, let duration, let position, let fontSize):
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(start, forKey: .startSeconds)
            try c.encodeIfPresent(duration, forKey: .durationSeconds)
            try c.encode(position.rawValue, forKey: .position)
            try c.encodeIfPresent(fontSize, forKey: .fontSize)
        case .removeTextOverlays:
            break
        case .addFade(let style, let start, let duration):
            try c.encode(style.rawValue, forKey: .style)
            try c.encodeIfPresent(start, forKey: .startSeconds)
            try c.encodeIfPresent(duration, forKey: .durationSeconds)
        case .reorder(let clipIds):
            try c.encode(clipIds, forKey: .clipIds)
        case .unknown:
            break
        }
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AIClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case emptyInstruction
    case noVideo
    case demoUnrecognized(String)
    case network(String)
    case invalidResponse(String)
    case emptyOperations

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未配置 API 密钥。请在设置中填写，或先使用演示模式。"
        case .invalidURL:
            return "API 地址无效，请检查设置中的接口地址。"
        case .emptyInstruction:
            return "请先输入剪辑指令。"
        case .noVideo:
            return "请先导入视频，再使用 AI 剪辑。"
        case .demoUnrecognized(let message):
            return message
        case .network(let message):
            return "网络请求失败：\(message)"
        case .invalidResponse(let message):
            return "无法解析模型返回的剪辑指令：\(message)"
        case .emptyOperations:
            return "模型没有返回可执行的操作。"
        }
    }
}
