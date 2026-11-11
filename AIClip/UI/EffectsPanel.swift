import SwiftUI

struct EffectsPanel: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var scopeAllClips: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(ColorFilterID.allCases) { filter in
                        Button {
                            store.setFilter(filter, clipID: scopeAllClips ? nil : store.selectedClipID)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(swatch(for: filter))
                                    .frame(height: 64)
                                Text(filter.displayName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(EditorTheme.text)
                            }
                            .padding(8)
                            .background(EditorTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(EditorTheme.background)
            .navigationTitle("滤镜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(for filter: ColorFilterID) -> LinearGradient {
        switch filter {
        case .none:
            return LinearGradient(colors: [.gray.opacity(0.6), .gray], startPoint: .top, endPoint: .bottom)
        case .vivid:
            return LinearGradient(colors: [.pink, .orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mono:
            return LinearGradient(colors: [.white, .black], startPoint: .top, endPoint: .bottom)
        case .warm:
            return LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
        case .cool:
            return LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
        case .vintage:
            return LinearGradient(colors: [.yellow.opacity(0.8), .brown], startPoint: .top, endPoint: .bottom)
        case .cinema:
            return LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct SpeedPanel: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let options: [Double] = [0.25, 0.5, 1, 1.5, 2, 4]

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.self) { speed in
                    Button {
                        _ = store.setSpeed(speed, clipID: store.selectedClipID)
                        dismiss()
                    } label: {
                        HStack {
                            Text(label(for: speed))
                            Spacer()
                            if let current = store.selectedClip?.speed ?? store.project.clip(atTimeline: store.currentTime)?.clip.speed,
                               abs(current - speed) < 0.001 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(EditorTheme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("倍速")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func label(for speed: Double) -> String {
        if speed == 0.25 { return "0.25× 极慢" }
        if speed == 0.5 { return "0.5× 慢放" }
        if speed == 1 { return "1× 原速" }
        if speed == 1.5 { return "1.5×" }
        if speed == 2 { return "2× 快放" }
        return "\(String(format: "%g", speed))×"
    }
}

struct FadePanel: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var duration: Double = 1.0

    var body: some View {
        NavigationStack {
            Form {
                Section("时长") {
                    Stepper(value: $duration, in: 0.2...5, step: 0.2) {
                        Text("\(TimeFormatting.string(from: duration))")
                    }
                }
                Section {
                    Button("添加淡入（从开头）") {
                        store.addFade(style: .fadeIn, startSeconds: 0, durationSeconds: duration)
                        dismiss()
                    }
                    Button("添加淡出（到结尾）") {
                        store.addFade(style: .fadeOut, startSeconds: nil, durationSeconds: duration)
                        dismiss()
                    }
                }
                if !store.project.fades.isEmpty {
                    Section("已有淡入淡出") {
                        ForEach(store.project.fades) { fade in
                            Text("\(fade.style.displayName) · 从 \(TimeFormatting.string(from: fade.startSeconds)) 起，持续 \(TimeFormatting.string(from: fade.durationSeconds))")
                        }
                    }
                }
            }
            .navigationTitle("淡入 / 淡出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
