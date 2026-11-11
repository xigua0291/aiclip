import Foundation

/// Deterministic, clearly-labeled local parser used by 演示模式.
/// It does not call a model and does not invent a live AI response.
enum DemoCommandParser {
    static let sampleCommands = [
        "去掉开头 3 秒，加上淡入，并在底部加字幕",
        "应用黑白滤镜",
        "添加 1 秒淡出",
        "两倍速",
        "在底部加字幕「你好」"
    ]

    static func parse(_ instruction: String, context: AIProjectContext) throws -> AIEditPlan {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIClientError.emptyInstruction }

        var operations: [AIEditCommand] = []

        // 去掉/删除开头 X 秒
        if let seconds = firstMatch(in: text, patterns: [
            #"去掉开头\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
            #"删除开头\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
            #"裁掉开头\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
            #"trim(?:\s+the)?\s+first\s+([0-9]+(?:\.[0-9]+)?)\s*(?:s|sec|seconds)?"#
        ]) {
            operations.append(.deleteRange(startSeconds: 0, endSeconds: seconds))
        }

        // 去掉/删除结尾 X 秒
        if let seconds = firstMatch(in: text, patterns: [
            #"去掉结尾\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
            #"删除结尾\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
            #"裁掉结尾\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#
        ]) {
            let end = context.durationSeconds
            let start = max(0, end - seconds)
            operations.append(.deleteRange(startSeconds: start, endSeconds: end))
        }

        // 删除 A 到 B 秒
        if let range = rangeMatch(in: text, patterns: [
            #"删除\s*([0-9]+(?:\.[0-9]+)?)\s*(?:到|至|-)\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#
        ]) {
            operations.append(.deleteRange(startSeconds: range.0, endSeconds: range.1))
        }

        // 分割
        if text.contains("分割") || text.lowercased().contains("split") {
            if let seconds = firstMatch(in: text, patterns: [
                #"(?:从第|在|于)\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#
            ]) {
                operations.append(.split(timeSeconds: seconds))
            } else {
                operations.append(.split(timeSeconds: context.playheadSeconds))
            }
        }

        // 倍速
        if let speed = speedMatch(in: text) {
            operations.append(.setSpeed(clipId: context.selectedClipId, speed: speed))
        }

        // 滤镜
        if let filter = filterMatch(in: text) {
            operations.append(.addFilter(clipId: nil, filter: filter))
        }

        if text.contains("去掉滤镜") || text.contains("取消滤镜") || text.contains("还原滤镜") {
            operations.append(.addFilter(clipId: nil, filter: .none))
        }

        // 淡入 / 淡出
        if text.contains("淡入") || text.lowercased().contains("fade in") {
            let duration = firstMatch(in: text, patterns: [
                #"淡入\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
                #"([0-9]+(?:\.[0-9]+)?)\s*秒淡入"#
            ]) ?? 1.0
            operations.append(.addFade(style: .fadeIn, startSeconds: nil, durationSeconds: duration))
        }
        if text.contains("淡出") || text.lowercased().contains("fade out") {
            let duration = firstMatch(in: text, patterns: [
                #"淡出\s*([0-9]+(?:\.[0-9]+)?)\s*秒"#,
                #"([0-9]+(?:\.[0-9]+)?)\s*秒淡出"#
            ]) ?? 1.0
            operations.append(.addFade(style: .fadeOut, startSeconds: nil, durationSeconds: duration))
        }

        // 字幕
        if text.contains("字幕") || text.lowercased().contains("subtitle") || text.lowercased().contains("caption") || text.contains("加文字") {
            if text.contains("删除字幕") || text.contains("去掉字幕") || text.contains("清除字幕") {
                operations.append(.removeTextOverlays)
            } else {
                let caption = quotedText(in: text) ?? "字幕"
                let position: OverlayPosition = text.contains("顶部") || text.contains("上方")
                    ? .top
                    : (text.contains("中间") || text.contains("居中") ? .center : .bottom)
                let duration = firstMatch(in: text, patterns: [
                    #"字幕[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)\s*秒"#
                ])
                operations.append(
                    .addTextOverlay(
                        text: caption,
                        startSeconds: 0,
                        durationSeconds: duration ?? max(3, min(context.durationSeconds, 8)),
                        position: position,
                        fontSize: nil
                    )
                )
            }
        }

        guard !operations.isEmpty else {
            throw AIClientError.demoUnrecognized(
                "演示模式无法解析这条指令。可以试试：「\(sampleCommands[0])」，或在设置中关闭演示模式并配置 API。"
            )
        }
        return AIEditPlan(operations: operations)
    }

    private static func firstMatch(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 2,
               let swiftRange = Range(match.range(at: 1), in: text),
               let value = Double(text[swiftRange]) {
                return value
            }
        }
        return nil
    }

    private static func rangeMatch(in text: String, patterns: [String]) -> (Double, Double)? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 3,
               let r1 = Range(match.range(at: 1), in: text),
               let r2 = Range(match.range(at: 2), in: text),
               let a = Double(text[r1]),
               let b = Double(text[r2]) {
                return (a, b)
            }
        }
        return nil
    }

    private static func speedMatch(in text: String) -> Double? {
        if let value = firstMatch(in: text, patterns: [
            #"([0-9]+(?:\.[0-9]+)?)\s*[xX×倍]"#,
            #"倍速\s*([0-9]+(?:\.[0-9]+)?)"#
        ]) {
            return value
        }
        if text.contains("两倍速") || text.contains("二倍速") || text.contains("2倍") { return 2 }
        if text.contains("半速") || text.contains("0.5倍") { return 0.5 }
        if text.contains("四倍速") { return 4 }
        if text.contains("一点五倍") || text.contains("1.5倍") { return 1.5 }
        if text.contains("恢复原速") || text.contains("正常速度") || text.contains("一倍速") { return 1 }
        return nil
    }

    private static func filterMatch(in text: String) -> ColorFilterID? {
        if text.contains("黑白") { return .mono }
        if text.contains("鲜艳") || text.contains("饱和") { return .vivid }
        if text.contains("暖色") || text.contains("温暖") { return .warm }
        if text.contains("冷色") { return .cool }
        if text.contains("复古") || text.contains("怀旧") { return .vintage }
        if text.contains("电影") { return .cinema }
        return nil
    }

    private static func quotedText(in text: String) -> String? {
        let patterns = [#"「([^」]+)」"#, #"“([^”]+)”"#, #""([^"]+)""#, #"'([^']+)'"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 2,
               let swiftRange = Range(match.range(at: 1), in: text) {
                let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return String(value.prefix(80)) }
            }
        }
        return nil
    }
}
