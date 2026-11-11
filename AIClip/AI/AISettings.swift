import Foundation
import Observation

@MainActor
@Observable
final class AISettingsStore {
    private enum Keys {
        static let demoMode = "aiclip.demoMode"
        static let baseURL = "aiclip.baseURL"
        static let modelName = "aiclip.modelName"
        static let openAICompatible = "aiclip.openAICompatible"
        static let apiKeyAccount = "openai-compatible-api-key"
    }

    var demoMode: Bool {
        didSet { UserDefaults.standard.set(demoMode, forKey: Keys.demoMode) }
    }

    var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL) }
    }

    var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: Keys.modelName) }
    }

    var usesOpenAICompatibleEndpoint: Bool {
        didSet { UserDefaults.standard.set(usesOpenAICompatibleEndpoint, forKey: Keys.openAICompatible) }
    }

    var apiKey: String {
        didSet { KeychainStore.set(apiKey, account: Keys.apiKeyAccount) }
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.demoMode) == nil {
            self.demoMode = true
        } else {
            self.demoMode = defaults.bool(forKey: Keys.demoMode)
        }
        self.baseURLString = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        self.modelName = defaults.string(forKey: Keys.modelName) ?? "gpt-4o-mini"
        if defaults.object(forKey: Keys.openAICompatible) == nil {
            self.usesOpenAICompatibleEndpoint = true
        } else {
            self.usesOpenAICompatibleEndpoint = defaults.bool(forKey: Keys.openAICompatible)
        }
        self.apiKey = KeychainStore.get(account: Keys.apiKeyAccount) ?? ""
    }
}

enum AISystemPrompt {
    static let text = """
你是「智能剪辑」App 的剪辑决策引擎。根据用户的自然语言指令和当前时间线元数据，输出一份可执行的剪辑决策列表。

必须遵守：
1. 只输出一个 JSON 对象，不要输出解释、Markdown、代码围栏或其它文字。
2. JSON 必须符合 schemaVersion "1.0"，形状为：
   {"schemaVersion":"1.0","operations":[ ... ]}
3. operations 是按执行顺序排列的数组。支持的 op：
   - trim：可选 clipId；startSeconds、endSeconds 为可选数字。若提供 clipId，时间是该片段输出时间线上的局部时间（0 表示片段开头）。若省略 clipId，时间是整个项目时间线，表示只保留 [startSeconds, endSeconds] 区间。
   - split：可选 timeSeconds（项目时间线，秒）。省略时使用当前播放头。
   - deleteRange：必须有 startSeconds 与 endSeconds（项目时间线）。
   - deleteClip：必须有 clipId。
   - setSpeed：必须有 speed（0.25 到 4 之间），可选 clipId。
   - addFilter：必须有 filter，取值只能是 none、vivid、mono、warm、cool、vintage、cinema。可选 clipId；省略则应用到全部片段。
   - addTextOverlay：必须有 text。可选 startSeconds、durationSeconds、position（top|center|bottom，默认 bottom）、fontSize。
   - removeTextOverlays：无其它字段。
   - addFade：必须有 style（in 或 out）。可选 startSeconds、durationSeconds（默认 1）。省略 startSeconds 时，淡入从 0 开始，淡出从片尾往前 durationSeconds。
   - reorder：必须有 clipIds，且必须是现有片段 ID 的完整排列。
4. 不要编造不存在的 clipId。需要引用片段时，只能使用上下文里提供的 id。
5. 不要输出未知操作。不要请求危险或与剪辑无关的动作。时间必须是有限的非负数。
6. 如果指令无法完成，返回 {"schemaVersion":"1.0","operations":[]}。
"""
}
