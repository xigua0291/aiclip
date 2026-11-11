import Foundation

@MainActor
struct AIEditClient {
    var settings: AISettingsStore

    func requestPlan(instruction: String, context: AIProjectContext) async throws -> AIEditPlan {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIClientError.emptyInstruction }
        guard !context.clips.isEmpty else { throw AIClientError.noVideo }

        if settings.demoMode {
            return try DemoCommandParser.parse(text, context: context)
        }

        let raw = try await sendToBackend(instruction: text, context: context)
        let plan = try decodePlan(from: raw)
        return validate(plan, context: context)
    }

    // MARK: - Network

    private func sendToBackend(instruction: String, context: AIProjectContext) async throws -> Data {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIClientError.missingAPIKey }
        guard let url = resolveEndpointURL() else { throw AIClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if settings.usesOpenAICompatibleEndpoint {
            let body = OpenAIChatRequest(
                model: settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "gpt-4o-mini"
                    : settings.modelName,
                temperature: 0,
                responseFormat: OpenAIChatRequest.ResponseFormat(type: "json_object"),
                messages: [
                    .init(role: "system", content: AISystemPrompt.text),
                    .init(role: "user", content: userMessage(instruction: instruction, context: context, encoder: encoder))
                ]
            )
            request.httpBody = try encoder.encode(body)
        } else {
            let body = CustomAIRequest(
                schemaVersion: AIEditPlan.currentSchemaVersion,
                instruction: instruction,
                context: context
            )
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.network("服务器没有返回有效的 HTTP 响应。")
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240) ?? ""
            throw AIClientError.network("HTTP \(http.statusCode)\(snippet.isEmpty ? "" : "：\(snippet)")")
        }
        return data
    }

    private func resolveEndpointURL() -> URL? {
        let raw = settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if settings.usesOpenAICompatibleEndpoint {
            var base = raw
            while base.hasSuffix("/") { base.removeLast() }
            if base.hasSuffix("/chat/completions") {
                return URL(string: base)
            }
            return URL(string: base + "/chat/completions")
        }
        return URL(string: raw)
    }

    private func userMessage(instruction: String, context: AIProjectContext, encoder: JSONEncoder) -> String {
        let contextJSON: String
        if let data = try? encoder.encode(context), let text = String(data: data, encoding: .utf8) {
            contextJSON = text
        } else {
            contextJSON = "{}"
        }
        return """
当前时间线元数据（JSON）：
\(contextJSON)

用户指令：
\(instruction)
"""
    }

    // MARK: - Decode & validate

    private func decodePlan(from data: Data) throws -> AIEditPlan {
        if settings.usesOpenAICompatibleEndpoint {
            let chat: OpenAIChatResponse
            do {
                chat = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            } catch {
                // Some compatible servers may already return the plan object.
                if let plan = try? JSONDecoder().decode(AIEditPlan.self, from: data) {
                    return plan
                }
                throw AIClientError.invalidResponse("不是 Chat Completions 响应，也不是剪辑决策 JSON。")
            }
            guard let content = chat.choices.first?.message.content, !content.isEmpty else {
                throw AIClientError.invalidResponse("choices 为空。")
            }
            return try decodePlanObject(from: content)
        }
        if let plan = try? JSONDecoder().decode(AIEditPlan.self, from: data) {
            return plan
        }
        if let text = String(data: data, encoding: .utf8) {
            return try decodePlanObject(from: text)
        }
        throw AIClientError.invalidResponse("响应不是 UTF-8 文本或 JSON。")
    }

    private func decodePlanObject(from text: String) throws -> AIEditPlan {
        let jsonData = try extractJSONData(from: text)
        do {
            return try JSONDecoder().decode(AIEditPlan.self, from: jsonData)
        } catch {
            throw AIClientError.invalidResponse(error.localizedDescription)
        }
    }

    private func extractJSONData(from text: String) throws -> Data {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            var bodyLines = Array(lines.dropFirst())
            if let last = bodyLines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                bodyLines.removeLast()
            }
            trimmed = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            let slice = String(trimmed[start...end])
            if let data = slice.data(using: .utf8) { return data }
        }
        throw AIClientError.invalidResponse("内容中没有找到 JSON 对象。")
    }

    func validate(_ plan: AIEditPlan, context: AIProjectContext) -> AIEditPlan {
        let knownIDs = Set(context.clips.map(\.id))
        var cleaned: [AIEditCommand] = []
        for command in plan.operations {
            switch command {
            case .trim(let clipId, let start, let end):
                if let clipId, knownIDs.contains(clipId) == false { continue }
                if let start, !start.isFinite || start < 0 { continue }
                if let end, !end.isFinite || end < 0 { continue }
                if let start, let end, end <= start { continue }
                cleaned.append(command)
            case .split(let time):
                if let time, !time.isFinite || time < 0 { continue }
                cleaned.append(command)
            case .deleteRange(let start, let end):
                guard start.isFinite, end.isFinite, end > start, start >= 0 else { continue }
                cleaned.append(command)
            case .deleteClip(let clipId):
                guard knownIDs.contains(clipId) else { continue }
                cleaned.append(command)
            case .setSpeed(let clipId, let speed):
                if let clipId, knownIDs.contains(clipId) == false { continue }
                guard speed.isFinite, speed >= 0.25, speed <= 4 else { continue }
                cleaned.append(command)
            case .addFilter(let clipId, _):
                if let clipId, knownIDs.contains(clipId) == false { continue }
                cleaned.append(command)
            case .addTextOverlay(let text, let start, let duration, _, let fontSize):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count <= 80 else { continue }
                if let start, !start.isFinite || start < 0 { continue }
                if let duration, !duration.isFinite || duration <= 0 { continue }
                if let fontSize, !fontSize.isFinite || fontSize < 8 || fontSize > 200 { continue }
                cleaned.append(command)
            case .removeTextOverlays:
                cleaned.append(command)
            case .addFade(_, let start, let duration):
                if let start, !start.isFinite || start < 0 { continue }
                if let duration, !duration.isFinite || duration <= 0 { continue }
                cleaned.append(command)
            case .reorder(let clipIds):
                guard Set(clipIds) == knownIDs, clipIds.count == knownIDs.count else { continue }
                cleaned.append(command)
            case .unknown:
                cleaned.append(command) // applier will ignore it and record a warning
            }
        }
        return AIEditPlan(schemaVersion: plan.schemaVersion.isEmpty ? AIEditPlan.currentSchemaVersion : plan.schemaVersion, operations: cleaned)
    }
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct ResponseFormat: Encodable {
        var type: String
    }

    var model: String
    var temperature: Double
    var responseFormat: ResponseFormat
    var messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case responseFormat = "response_format"
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        var message: Message
    }
    struct Message: Decodable {
        var content: String?
    }
    var choices: [Choice]
}

private struct CustomAIRequest: Encodable {
    var schemaVersion: String
    var instruction: String
    var context: AIProjectContext
}
