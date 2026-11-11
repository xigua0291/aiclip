import SwiftUI

struct TextOverlaySheet: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var position: OverlayPosition = .bottom
    @State private var startSeconds: Double = 0
    @State private var durationSeconds: Double = 3
    @State private var fontSize: Double = 42

    var body: some View {
        NavigationStack {
            Form {
                Section("新字幕") {
                    TextField("输入字幕文本", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("位置", selection: $position) {
                        ForEach(OverlayPosition.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    HStack {
                        Text("开始")
                        Spacer()
                        Text(TimeFormatting.string(from: startSeconds))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $startSeconds, in: 0...max(0.1, store.duration), step: 0.1)
                    HStack {
                        Text("持续")
                        Spacer()
                        Text(TimeFormatting.string(from: durationSeconds))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $durationSeconds, in: 0.2...max(0.2, store.duration), step: 0.1)
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(Int(fontSize))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSize, in: 24...72, step: 2)
                    Button("在播放头处添加") {
                        startSeconds = store.currentTime
                        add()
                    }
                    Button("添加字幕") { add() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !store.project.overlays.isEmpty {
                    Section("已有字幕") {
                        ForEach(store.project.overlays) { overlay in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(overlay.text)
                                Text("\(TimeFormatting.string(from: overlay.startSeconds)) · \(overlay.durationSeconds, specifier: "%.1f") 秒 · \(overlay.position.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.removeOverlay(id: overlay.id)
                                } label: {
                                    Text("删除")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                if startSeconds == 0 {
                    startSeconds = store.currentTime
                }
                if durationSeconds == 3, store.duration > 0 {
                    durationSeconds = min(3, max(0.5, store.duration - startSeconds))
                }
            }
        }
    }

    private func add() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        store.addTextOverlay(
            text: content,
            startSeconds: startSeconds,
            durationSeconds: durationSeconds,
            position: position,
            fontSize: fontSize
        )
        text = ""
    }
}
