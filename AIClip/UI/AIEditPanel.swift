import SwiftUI

struct AIEditPanel: View {
    @Environment(EditorStore.self) private var store
    @Environment(AISettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var instruction: String = ""
    @State private var isRunning = false
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                modeBanner

                Text("用一句话描述你想怎么剪，应用会把它转成结构化剪辑指令并执行。")
                    .font(.subheadline)
                    .foregroundStyle(EditorTheme.secondary)

                TextField("例如：去掉开头 3 秒，加上淡入，并在底部加字幕", text: $instruction, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(EditorTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if settings.demoMode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("演示模式可用示例")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EditorTheme.warning)
                        ForEach(DemoCommandParser.sampleCommands, id: \.self) { sample in
                            Button {
                                instruction = sample
                            } label: {
                                Text(sample)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(EditorTheme.accentSoft, in: Capsule())
                                    .foregroundStyle(EditorTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? EditorTheme.danger : EditorTheme.secondary)
                        .textSelection(.enabled)
                }

                Button(action: runCommand) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isRunning ? "正在应用…" : "执行指令")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(EditorTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.black)
                }
                .disabled(isRunning || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.hasVideo)

                Spacer()
            }
            .padding()
            .background(EditorTheme.background)
            .navigationTitle("AI 剪辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var modeBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: settings.demoMode ? "sparkles" : "network")
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.demoMode ? "当前为演示模式" : "当前使用已配置的 AI 接口")
                    .font(.subheadline.weight(.semibold))
                Text(
                    settings.demoMode
                        ? "不会请求网络，只按本地规则解析若干常见中文指令。这不是实时模型回复。"
                        : "将把时间线元数据和你的指令发送到设置中的接口，并只接受符合 schema 的 JSON。"
                )
                .font(.caption)
                .foregroundStyle(EditorTheme.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            (settings.demoMode ? EditorTheme.warning.opacity(0.16) : EditorTheme.accentSoft),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .foregroundStyle(settings.demoMode ? EditorTheme.warning : EditorTheme.accent)
    }

    private func runCommand() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isRunning = true
        statusMessage = nil
        isError = false
        Task {
            defer { isRunning = false }
            do {
                let client = AIEditClient(settings: settings)
                let plan = try await client.requestPlan(instruction: text, context: store.projectContext())
                if plan.operations.isEmpty {
                    statusMessage = "没有可执行的操作。请换一种说法，或检查模型是否只返回了空列表。"
                    isError = true
                    return
                }
                let result = store.applyAIPlan(plan)
                if result.applied.isEmpty {
                    statusMessage = result.summary
                    isError = true
                } else {
                    statusMessage = result.summary
                    isError = false
                }
            } catch {
                isError = true
                statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
