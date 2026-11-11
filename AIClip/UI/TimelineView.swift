import SwiftUI

struct TimelineView: View {
    @Environment(EditorStore.self) private var store
    private let pixelsPerSecond: CGFloat = 64
    private let rowHeight: CGFloat = 68

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("时间线")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EditorTheme.secondary)
                Spacer()
                if let selected = store.selectedClip {
                    Text("已选 \(format(selected.outputDuration)) · \(selected.filter.displayName) · \(String(format: "%.2g", selected.speed))×")
                        .font(.caption)
                        .foregroundStyle(EditorTheme.accent)
                }
            }

            GeometryReader { geo in
                let total = max(store.duration, 0.1)
                let contentWidth = max(geo.size.width, total * pixelsPerSecond + 40)
                ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            ruler(total: total, width: contentWidth)

                            HStack(spacing: 2) {
                                ForEach(Array(clipLayout().enumerated()), id: \.element.clip.id) { _, item in
                                    clipCell(item, minWidth: max(8, item.duration * pixelsPerSecond))
                                }
                                if store.project.clips.isEmpty {
                                    roundedPlaceholder(width: contentWidth - 16)
                                }
                            }
                            .padding(.top, 22)
                            .padding(.horizontal, 8)

                            playhead(height: geo.size.height)
                                .offset(x: 8 + CGFloat(store.currentTime) * pixelsPerSecond)
                        }
                        .frame(width: contentWidth, height: geo.size.height, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .gesture(dragSeek)
                    }
            }
        }
        .padding(12)
        .background(EditorTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dragSeek: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = value.location.x - 8
                store.seek(to: Double(max(0, x / pixelsPerSecond)))
            }
    }

    private func ruler(total: Double, width: CGFloat) -> some View {
        let step = tickStep(for: total)
        let ticks = stride(from: 0.0, through: total + 0.001, by: step)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1, height: 8)
                    Text(TimeFormatting.string(from: t, showTenths: step < 1))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(EditorTheme.secondary)
                }
                .offset(x: 8 + CGFloat(t) * pixelsPerSecond)
            }
        }
        .frame(width: width, height: 20, alignment: .topLeading)
    }

    private func tickStep(for total: Double) -> Double {
        if total <= 8 { return 1 }
        if total <= 20 { return 2 }
        if total <= 60 { return 5 }
        return 10
    }

    private func clipLayout() -> [(clip: ClipSegment, start: Double, duration: Double)] {
        var t = 0.0
        return store.project.clips.map { clip in
            let item = (clip, t, clip.outputDuration)
            t += clip.outputDuration
            return item
        }
    }

    private func clipCell(_ item: (clip: ClipSegment, start: Double, duration: Double), minWidth: CGFloat) -> some View {
        let selected = store.selectedClipID == item.clip.id
        return Button {
            store.selectClip(id: item.clip.id)
            store.seek(to: item.start)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.clip.filter == .none ? "片段" : item.clip.filter.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(format(item.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(8)
            .frame(width: minWidth, height: rowHeight, alignment: .topLeading)
            .background(
                (selected ? EditorTheme.clipSelected : EditorTheme.clipFill),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? EditorTheme.playhead : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func roundedPlaceholder(width: CGFloat) -> some View {
        Text("导入视频后，片段会显示在这里")
            .font(.caption)
            .foregroundStyle(EditorTheme.secondary)
            .frame(width: max(width, 200), height: rowHeight)
            .background(EditorTheme.panelElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func playhead(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(EditorTheme.playhead)
                .rotationEffect(.degrees(180))
            Rectangle()
                .fill(EditorTheme.playhead)
                .frame(width: 2, height: max(20, height - 6))
        }
        .offset(x: -5)
        .allowsHitTesting(false)
    }

    private func format(_ seconds: Double) -> String {
        TimeFormatting.string(from: seconds)
    }
}
