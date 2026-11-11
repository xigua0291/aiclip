import SwiftUI

struct SettingsView: View {
    @Environment(AISettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var revealKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("演示模式", isOn: Bindable(settings).demoMode)
                    Text("开启后，AI 剪辑面板只使用本地规则解析示例指令，不会发起网络请求，也不需要 API 密钥。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("AI 接口")
                }

                Section("接口配置") {
                    TextField("API 地址", text: Bindable(settings).baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Toggle("OpenAI 兼容 Chat Completions", isOn: Bindable(settings).usesOpenAICompatibleEndpoint)
                    TextField("模型名称", text: Bindable(settings).modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if revealKey {
                                TextField("API 密钥", text: Bindable(settings).apiKey)
                            } else {
                                SecureField("API 密钥", text: Bindable(settings).apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Text(settings.usesOpenAICompatibleEndpoint
                         ? "地址填写到 /v1 这一级即可，例如 https://api.openai.com/v1。应用会请求 /chat/completions，并把密钥存在本机钥匙串，而不是写进代码。"
                         : "关闭兼容模式后，应用会把 {schemaVersion, instruction, context} 直接 POST 到上面的完整地址，并期望返回 schemaVersion 1.0 的决策 JSON。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(settings.demoMode)

                Section("关于") {
                    LabeledContent("应用") { Text("智能剪辑") }
                    LabeledContent("版本") { Text("1.0 MVP") }
                    Text("这是一个可在 iPhone 上本地安装的最小可用剪辑应用：导入、裁剪、分割、滤镜、字幕、淡入淡出、导出，以及可插拔的 AI 剪辑接口。它不是完整的剪映替代品。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
