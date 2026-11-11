import SwiftUI

struct EditorView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var showPicker = false
    @State private var showFilters = false
    @State private var showSpeed = false
    @State private var showText = false
    @State private var showFade = false
    @State private var showAI = false
    @State private var showSettings = false
    @State private var appendOnImport = false
    @State private var showImportChoice = false

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            Group {
                if verticalSizeClass == .compact {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if store.isExporting {
                exportOverlay
            }
        }
        .sheet(isPresented: $showPicker) {
            VideoPicker { url in
                Task { await store.importVideo(from: url, append: appendOnImport) }
            } onFailed: { message in
                store.lastErrorMessage = message
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilters) { EffectsPanel() }
        .sheet(isPresented: $showSpeed) { SpeedPanel() }
        .sheet(isPresented: $showText) { TextOverlaySheet() }
        .sheet(isPresented: $showFade) { FadePanel() }
        .sheet(isPresented: $showAI) { AIEditPanel() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("无法完成操作", isPresented: errorBinding) {
            Button("好", role: .cancel) { store.lastErrorMessage = nil }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
        .alert("提示", isPresented: infoBinding) {
            Button("好", role: .cancel) { store.lastWarningMessages = [] }
        } message: {
            Text(store.lastWarningMessages.joined(separator: "\n"))
        }
        .confirmationDialog("导入视频", isPresented: $showImportChoice, titleVisibility: .visible) {
            Button("替换当前项目") {
                appendOnImport = false
                showPicker = true
            }
            if store.hasVideo {
                Button("追加到时间线") {
                    appendOnImport = true
                    showPicker = true
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: Layouts

    private var portraitLayout: some View {
        VStack(spacing: 10) {
            topBar
            PlayerContainerView()
                .frame(maxHeight: .infinity)
            transportBar
            TimelineView()
                .frame(height: 140)
            toolRail
        }
    }

    private var landscapeLayout: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                topBar
                PlayerContainerView()
                    .frame(maxHeight: .infinity)
                transportBar
            }
            VStack(spacing: 8) {
                TimelineView()
                    .frame(maxHeight: .infinity)
                toolRail
            }
            .frame(maxWidth: 420)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("智能剪辑")
                    .font(.title3.weight(.bold))
                Text(store.hasVideo ? "共 \(store.project.clips.count) 个片段" : "尚未导入视频")
                    .font(.caption)
                    .foregroundStyle(EditorTheme.secondary)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(EditorTheme.secondary)
                    .frame(width: 36, height: 36)
            }
            Button {
                Task {
                    await store.exportToPhotos()
                }
            } label: {
                Text("导出")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(store.hasVideo ? EditorTheme.accent : EditorTheme.panelElevated, in: Capsule())
                    .foregroundStyle(store.hasVideo ? .black : EditorTheme.secondary)
            }
            .disabled(!store.hasVideo || store.isExporting)
        }
        .padding(.top, 8)
    }

    private var transportBar: some View {
        HStack(spacing: 16) {
            Text(TimeFormatting.string(from: store.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(EditorTheme.secondary)
                .frame(width: 64, alignment: .leading)
            Spacer()
            Button { store.seek(to: 0) } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(!store.hasVideo)
            Button { store.player.toggle() } label: {
                Image(systemName: store.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(EditorTheme.accent)
            }
            .disabled(!store.hasVideo)
            Button {
                store.seek(to: min(store.duration, store.currentTime + 1))
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!store.hasVideo)
            Spacer()
            Text(TimeFormatting.string(from: store.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(EditorTheme.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .foregroundStyle(EditorTheme.text)
    }

    private var toolRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tool("导入", symbol: "plus") { showImportChoice = true }
                tool("撤销", symbol: "arrow.uturn.backward", enabled: store.canUndo) { store.undo() }
                tool("入点", symbol: "arrow.right.to.line", enabled: store.hasVideo) {
                    store.setInPointAtPlayhead()
                }
                tool("出点", symbol: "arrow.left.to.line", enabled: store.hasVideo) {
                    store.setOutPointAtPlayhead()
                }
                tool("分割", symbol: "scissors", enabled: store.hasVideo) { store.splitAtPlayhead() }
                tool("删除", symbol: "trash", enabled: store.selectedClip != nil || store.hasVideo, destructive: true) {
                    store.deleteSelectedSegment()
                }
                tool("倍速", symbol: "speedometer", enabled: store.hasVideo) { showSpeed = true }
                tool("滤镜", symbol: "camera.filters", enabled: store.hasVideo) { showFilters = true }
                tool("字幕", symbol: "textformat", enabled: store.hasVideo) { showText = true }
                tool("淡入淡出", symbol: "circle.lefthalf.filled", enabled: store.hasVideo) { showFade = true }
                tool("AI", symbol: "sparkles", enabled: store.hasVideo, highlighted: true) { showAI = true }
            }
            .padding(.vertical, 4)
        }
    }

    private func tool(
        _ title: String,
        symbol: String,
        enabled: Bool = true,
        destructive: Bool = false,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(
                        highlighted ? EditorTheme.accent : EditorTheme.panelElevated,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .foregroundStyle(highlighted ? Color.black : (destructive ? EditorTheme.danger : EditorTheme.text))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(EditorTheme.secondary)
            }
            .frame(width: 58)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: store.exportProgress)
                    .tint(EditorTheme.accent)
                Text("正在导出… \(Int((store.exportProgress * 100).rounded()))%")
                    .font(.subheadline.weight(.medium))
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastErrorMessage != nil },
            set: { if !$0 { store.lastErrorMessage = nil } }
        )
    }

    private var infoBinding: Binding<Bool> {
        Binding(
            get: { store.lastErrorMessage == nil && !store.lastWarningMessages.isEmpty },
            set: { if !$0 { store.lastWarningMessages = [] } }
        )
    }
}
