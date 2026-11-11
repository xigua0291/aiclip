import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class EditorStore {
    var project = EditProject()
    var selectedClipID: UUID?
    var lastErrorMessage: String?
    var lastWarningMessages: [String] = []
    var isRebuilding = false
    var isExporting = false
    var exportProgress: Double = 0
    var canUndo: Bool { !undoStack.isEmpty }

    let player = PlayerController()
    let exporter = VideoExporter()

    @ObservationIgnored private var undoStack: [EditProject] = []
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    private let maxUndo = 20

    var currentTime: Double { player.currentTime }
    var duration: Double { project.totalDuration }
    var hasVideo: Bool { !project.clips.isEmpty }
    var selectedClip: ClipSegment? {
        guard let selectedClipID else { return nil }
        return project.clips.first(where: { $0.id == selectedClipID })
    }

    func shutdown() {
        rebuildTask?.cancel()
        player.shutdown()
        exporter.cancel()
    }

    // MARK: - Import

    func importVideo(from temporaryURL: URL, append: Bool) async {
        do {
            let stored = try MediaStore.copyImportedVideo(from: temporaryURL)
            let info = try await CompositionBuilder.loadAssetInfo(url: stored)
            let clip = ClipSegment(
                assetURL: stored,
                sourceStart: 0,
                sourceEnd: info.duration,
                speed: 1,
                filter: .none
            )
            pushUndo()
            if !append || project.clips.isEmpty {
                project = EditProject(
                    clips: [clip],
                    overlays: [],
                    fades: [],
                    canvasWidth: max(16, info.displayWidth),
                    canvasHeight: max(16, info.displayHeight),
                    frameRate: info.frameRate > 1 ? info.frameRate : 30
                )
                selectedClipID = clip.id
                player.currentTime = 0
            } else {
                project.clips.append(clip)
                selectedClipID = clip.id
            }
            await rebuildPreview(seekTo: append && project.clips.count > 1 ? project.totalDuration - clip.outputDuration : 0)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Manual edit operations

    func setInPointAtPlayhead() {
        guard let target = clipForEditing() else { return }
        let playhead = currentTime
        guard let range = project.timelineRange(of: target.id) else { return }
        guard playhead > range.start + 0.05, playhead < range.end - 0.02 else {
            lastErrorMessage = "请把播放头移到所选片段内部，再设置入点。"
            return
        }
        pushUndo()
        updateClip(id: target.id) { clip in
            clip.sourceStart = clip.sourceTime(forOutputLocal: playhead - range.start)
        }
        selectedClipID = target.id
        scheduleRebuild(seekTo: range.start)
    }

    func setOutPointAtPlayhead() {
        guard let target = clipForEditing() else { return }
        let playhead = currentTime
        guard let range = project.timelineRange(of: target.id) else { return }
        guard playhead > range.start + 0.02, playhead < range.end - 0.05 else {
            lastErrorMessage = "请把播放头移到所选片段内部，再设置出点。"
            return
        }
        pushUndo()
        updateClip(id: target.id) { clip in
            clip.sourceEnd = clip.sourceTime(forOutputLocal: playhead - range.start)
        }
        selectedClipID = target.id
        scheduleRebuild(seekTo: playhead)
    }

    func splitAtPlayhead() {
        split(at: currentTime)
    }

    @discardableResult
    func split(at timelineTime: Double) -> Bool {
        guard let hit = project.clip(atTimeline: timelineTime) else {
            lastErrorMessage = "没有可分割的片段。"
            return false
        }
        let local = timelineTime - hit.start
        if local < 0.05 || (hit.clip.outputDuration - local) < 0.05 {
            lastErrorMessage = "播放头离片段边缘太近，无法分割。"
            return false
        }
        pushUndo()
        let sourceSplit = hit.clip.sourceTime(forOutputLocal: local)
        var left = hit.clip
        var right = hit.clip
        left.sourceEnd = sourceSplit
        right.id = UUID()
        right.sourceStart = sourceSplit
        project.clips.replaceSubrange(hit.index...hit.index, with: [left, right])
        selectedClipID = right.id
        scheduleRebuild(seekTo: timelineTime)
        return true
    }

    func deleteSelectedSegment() {
        guard let id = selectedClipID ?? clipForEditing()?.id,
              let index = project.clips.firstIndex(where: { $0.id == id }) else {
            lastErrorMessage = "请先选中要删除的片段。"
            return
        }
        let start = project.timelineStart(of: id) ?? 0
        let end = start + project.clips[index].outputDuration
        pushUndo()
        project.clips.remove(at: index)
        project.adjustAnnotationsAfterDeleting(rangeStart: start, rangeEnd: end)
        selectedClipID = project.clips.indices.contains(index)
            ? project.clips[index].id
            : project.clips.last?.id
        scheduleRebuild(seekTo: start)
    }

    @discardableResult
    func deleteRange(start: Double, end: Double) -> Bool {
        let lo = max(0, min(start, end))
        let hi = min(project.totalDuration, max(start, end))
        guard hi - lo > 0.03 else {
            lastErrorMessage = "删除范围太短或超出时间线。"
            return false
        }
        pushUndo()
        var newClips: [ClipSegment] = []
        var t = 0.0
        for clip in project.clips {
            let clipStart = t
            let clipEnd = t + clip.outputDuration
            t = clipEnd
            if clipEnd <= lo + 0.001 || clipStart >= hi - 0.001 {
                newClips.append(clip)
                continue
            }
            if lo > clipStart + 0.03 {
                var left = clip
                left.id = UUID()
                left.sourceEnd = clip.sourceTime(forOutputLocal: lo - clipStart)
                if left.sourceDuration > 0.03 { newClips.append(left) }
            }
            if hi < clipEnd - 0.03 {
                var right = clip
                right.id = UUID()
                right.sourceStart = clip.sourceTime(forOutputLocal: hi - clipStart)
                if right.sourceDuration > 0.03 { newClips.append(right) }
            }
        }
        project.clips = newClips
        project.adjustAnnotationsAfterDeleting(rangeStart: lo, rangeEnd: hi)
        selectedClipID = project.clip(atTimeline: lo)?.clip.id ?? project.clips.last?.id
        scheduleRebuild(seekTo: lo)
        return true
    }

    func trimClip(id: UUID?, startSeconds: Double?, endSeconds: Double?, timesAreTimeline: Bool) -> Bool {
        let target: ClipSegment?
        if let id, let clip = project.clips.first(where: { $0.id == id }) {
            target = clip
        } else if timesAreTimeline || id == nil {
            target = nil
        } else {
            target = nil
        }

        if let clip = target, let range = project.timelineRange(of: clip.id), !timesAreTimeline {
            // start/end are local output times on this clip (0 = clip start).
            let newLocalStart = startSeconds ?? 0
            let newLocalEnd = endSeconds ?? clip.outputDuration
            let lo = max(0, min(newLocalStart, newLocalEnd))
            let hi = min(clip.outputDuration, max(newLocalStart, newLocalEnd))
            guard hi - lo > 0.05 else { return false }
            pushUndo()
            updateClip(id: clip.id) { item in
                let srcStart = item.sourceTime(forOutputLocal: lo)
                let srcEnd = item.sourceTime(forOutputLocal: hi)
                item.sourceStart = srcStart
                item.sourceEnd = srcEnd
            }
            selectedClipID = clip.id
            scheduleRebuild(seekTo: range.start)
            return true
        }

        // Treat as keep only [start, end] on the project timeline.
        let total = project.totalDuration
        let keepStart = max(0, startSeconds ?? 0)
        let keepEnd = min(total, endSeconds ?? total)
        guard keepEnd - keepStart > 0.05 else { return false }
        if keepEnd < total - 0.03 {
            _ = deleteRange(start: keepEnd, end: total)
        }
        if keepStart > 0.03 {
            _ = deleteRange(start: 0, end: keepStart)
        }
        return true
    }

    func setSpeed(_ speed: Double, clipID: UUID?) -> Bool {
        let rate = (speed * 100).rounded() / 100
        guard rate >= 0.25, rate <= 4 else {
            lastErrorMessage = EditorError.unsupportedSpeed.errorDescription
            return false
        }
        guard let target = (clipID.flatMap { id in project.clips.first(where: { $0.id == id }) }) ?? clipForEditing() else {
            lastErrorMessage = "没有可调整倍速的片段。"
            return false
        }
        pushUndo()
        updateClip(id: target.id) { $0.speed = rate }
        selectedClipID = target.id
        scheduleRebuild(seekTo: currentTime)
        return true
    }

    func setFilter(_ filter: ColorFilterID, clipID: UUID?) {
        pushUndo()
        if let clipID {
            updateClip(id: clipID) { $0.filter = filter }
        } else {
            for index in project.clips.indices {
                project.clips[index].filter = filter
            }
        }
        scheduleRebuild(seekTo: currentTime)
    }

    func addTextOverlay(
        text: String,
        startSeconds: Double?,
        durationSeconds: Double?,
        position: OverlayPosition,
        fontSize: Double?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let start = max(0, startSeconds ?? 0)
        let duration = max(0.2, durationSeconds ?? min(3, max(1, project.totalDuration - start)))
        pushUndo()
        project.overlays.append(
            TextOverlay(
                text: String(trimmed.prefix(80)),
                startSeconds: start,
                durationSeconds: duration,
                position: position,
                fontSize: fontSize ?? 42
            )
        )
        scheduleRebuild(seekTo: start)
    }

    func updateOverlay(_ overlay: TextOverlay) {
        guard let index = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        pushUndo()
        project.overlays[index] = overlay
        scheduleRebuild(seekTo: overlay.startSeconds)
    }

    func removeOverlay(id: UUID) {
        pushUndo()
        project.overlays.removeAll { $0.id == id }
        scheduleRebuild(seekTo: currentTime)
    }

    func removeAllOverlays() {
        guard !project.overlays.isEmpty else { return }
        pushUndo()
        project.overlays.removeAll()
        scheduleRebuild(seekTo: currentTime)
    }

    func addFade(style: FadeStyle, startSeconds: Double?, durationSeconds: Double) {
        let duration = max(0.1, min(durationSeconds, max(0.1, project.totalDuration)))
        let start: Double
        switch style {
        case .fadeIn:
            start = max(0, startSeconds ?? 0)
        case .fadeOut:
            if let startSeconds {
                start = max(0, startSeconds)
            } else {
                start = max(0, project.totalDuration - duration)
            }
        }
        pushUndo()
        // Replace an existing fade of the same style that overlaps heavily, so repeat commands stay deterministic.
        project.fades.removeAll { fade in
            fade.style == style && abs(fade.startSeconds - start) < 0.05
        }
        project.fades.append(FadeEffect(style: style, startSeconds: start, durationSeconds: duration))
        scheduleRebuild(seekTo: start)
    }

    func reorder(clipIDs: [UUID]) -> Bool {
        let currentIDs = project.clips.map(\.id)
        guard Set(clipIDs) == Set(currentIDs), clipIDs.count == currentIDs.count else {
            lastErrorMessage = "重排序需要包含全部现有片段，且不能多出未知 ID。"
            return false
        }
        pushUndo()
        let map = Dictionary(uniqueKeysWithValues: project.clips.map { ($0.id, $0) })
        project.clips = clipIDs.compactMap { map[$0] }
        scheduleRebuild(seekTo: 0)
        return true
    }

    func selectClip(id: UUID?) {
        selectedClipID = id
    }

    func seek(to seconds: Double) {
        player.seek(to: min(max(0, seconds), max(duration, 0)))
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        project = previous
        if let selectedClipID, !project.clips.contains(where: { $0.id == selectedClipID }) {
            self.selectedClipID = project.clips.first?.id
        }
        scheduleRebuild(seekTo: currentTime)
    }

    func applyAIPlan(_ plan: AIEditPlan) -> AIApplyResult {
        var applied: [String] = []
        var skipped: [String] = []
        // Snapshot once so a single AI command list is one undo step.
        pushUndo()
        let undoCount = undoStack.count
        for (index, command) in plan.operations.enumerated() {
            let label = "第 \(index + 1) 步 \(command.opName)"
            let before = undoStack.count
            let ok = applyOne(command, skipped: &skipped, label: label)
            // Individual operations also push undo; collapse them into the one snapshot we already took.
            if undoStack.count > before {
                undoStack.removeLast(undoStack.count - before)
            }
            if ok {
                applied.append(label)
            }
            // Prevent nested undo from shrinking the batch snapshot.
            if undoStack.count < undoCount {
                break
            }
        }
        // If nothing changed, drop the snapshot.
        if applied.isEmpty {
            if undoStack.count >= undoCount {
                // The snapshot is still there; pop if project is unchanged is hard to detect — keep if any applied.
            }
            if applied.isEmpty, let last = undoStack.last, last == project {
                _ = undoStack.popLast()
            }
        }
        scheduleRebuild(seekTo: currentTime)
        lastWarningMessages = skipped
        return AIApplyResult(applied: applied, skipped: skipped)
    }

    func exportToPhotos() async {
        guard hasVideo else {
            lastErrorMessage = EditorError.emptyTimeline.errorDescription
            return
        }
        player.pause()
        isExporting = true
        exportProgress = 0
        defer { isExporting = false }
        do {
            let url = try await exporter.export(project: project) { [weak self] value in
                Task { @MainActor in
                    self?.exportProgress = value
                }
            }
            try await exporter.saveToPhotoLibrary(fileURL: url)
            lastErrorMessage = nil
            lastWarningMessages = ["已保存到相册。"]
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Preview

    func scheduleRebuild(seekTo time: Double) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.rebuildPreview(seekTo: time)
        }
    }

    func rebuildPreview(seekTo time: Double) async {
        guard hasVideo else {
            player.replace(item: nil, duration: 0)
            return
        }
        isRebuilding = true
        defer { isRebuilding = false }
        do {
            let built = try CompositionBuilder.build(project)
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioTimePitchAlgorithm = .spectral
            player.replace(item: item, duration: built.duration)
            player.seek(to: min(max(0, time), built.duration))
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Context for AI

    func projectContext() -> AIProjectContext {
        var t = 0.0
        let clips: [AIProjectContext.Clip] = project.clips.map { clip in
            let item = AIProjectContext.Clip(
                id: clip.id.uuidString,
                index: 0,
                timelineStart: t,
                timelineEnd: t + clip.outputDuration,
                sourceStart: clip.sourceStart,
                sourceEnd: clip.sourceEnd,
                speed: clip.speed,
                filter: clip.filter.rawValue
            )
            t += clip.outputDuration
            return item
        }.enumerated().map { index, clip in
            var copy = clip
            copy.index = index
            return copy
        }
        return AIProjectContext(
            schemaVersion: AIEditPlan.currentSchemaVersion,
            durationSeconds: project.totalDuration,
            playheadSeconds: currentTime,
            selectedClipId: selectedClipID?.uuidString,
            canvasWidth: project.canvasWidth,
            canvasHeight: project.canvasHeight,
            clips: clips,
            textOverlays: project.overlays.map {
                AIProjectContext.Overlay(
                    id: $0.id.uuidString,
                    text: $0.text,
                    startSeconds: $0.startSeconds,
                    durationSeconds: $0.durationSeconds,
                    position: $0.position.rawValue
                )
            },
            fades: project.fades.map {
                AIProjectContext.Fade(
                    id: $0.id.uuidString,
                    style: $0.style.rawValue,
                    startSeconds: $0.startSeconds,
                    durationSeconds: $0.durationSeconds
                )
            }
        )
    }

    // MARK: - Private

    private func clipForEditing() -> ClipSegment? {
        if let selectedClip { return selectedClip }
        return project.clip(atTimeline: currentTime)?.clip
    }

    private func updateClip(id: UUID, mutate: (inout ClipSegment) -> Void) {
        guard let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        mutate(&project.clips[index])
    }

    private func pushUndo() {
        undoStack.append(project)
        if undoStack.count > maxUndo {
            undoStack.removeFirst(undoStack.count - maxUndo)
        }
    }

    private func applyOne(_ command: AIEditCommand, skipped: inout [String], label: String) -> Bool {
        switch command {
        case .trim(let clipId, let start, let end):
            let uuid = clipId.flatMap(UUID.init(uuidString:))
            if let clipId, uuid == nil {
                skipped.append("\(label)：无效的 clipId。")
                return false
            }
            let timesAreTimeline = (uuid == nil)
            let ok = trimClip(id: uuid, startSeconds: start, endSeconds: end, timesAreTimeline: timesAreTimeline)
            if !ok { skipped.append("\(label)：裁剪范围无效。") }
            return ok

        case .split(let time):
            let at = time ?? currentTime
            let ok = split(at: at)
            if !ok { skipped.append("\(label)：无法在 \(TimeFormatting.string(from: at)) 处分割。") }
            return ok

        case .deleteRange(let start, let end):
            let ok = deleteRange(start: start, end: end)
            if !ok { skipped.append("\(label)：删除范围无效。") }
            return ok

        case .deleteClip(let clipId):
            guard let uuid = UUID(uuidString: clipId),
                  project.clips.contains(where: { $0.id == uuid }) else {
                skipped.append("\(label)：找不到片段 \(clipId)。")
                return false
            }
            selectedClipID = uuid
            deleteSelectedSegment()
            return true

        case .setSpeed(let clipId, let speed):
            let uuid = clipId.flatMap(UUID.init(uuidString:))
            if let clipId, uuid == nil {
                skipped.append("\(label)：无效的 clipId。")
                return false
            }
            return setSpeed(speed, clipID: uuid)

        case .addFilter(let clipId, let filter):
            let uuid = clipId.flatMap(UUID.init(uuidString:))
            if let clipId, uuid == nil {
                skipped.append("\(label)：无效的 clipId，已忽略该滤镜。")
                return false
            }
            setFilter(filter, clipID: uuid)
            return true

        case .addTextOverlay(let text, let start, let duration, let position, let fontSize):
            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                skipped.append("\(label)：字幕文本为空。")
                return false
            }
            addTextOverlay(
                text: content,
                startSeconds: start,
                durationSeconds: duration,
                position: position,
                fontSize: fontSize
            )
            return true

        case .removeTextOverlays:
            removeAllOverlays()
            return true

        case .addFade(let style, let start, let duration):
            addFade(style: style, startSeconds: start, durationSeconds: duration ?? 1)
            return true

        case .reorder(let clipIds):
            let ids = clipIds.compactMap(UUID.init(uuidString:))
            if ids.count != clipIds.count {
                skipped.append("\(label)：包含无效的 clipId。")
                return false
            }
            return reorder(clipIDs: ids)

        case .unknown(let name):
            skipped.append("\(label)：未知操作 “\(name)”，已忽略。")
            return false
        }
    }
}

struct AIApplyResult {
    var applied: [String]
    var skipped: [String]

    var summary: String {
        var parts: [String] = []
        if !applied.isEmpty {
            parts.append("已执行：\(applied.joined(separator: "；"))")
        }
        if !skipped.isEmpty {
            parts.append("已跳过：\(skipped.joined(separator: "；"))")
        }
        if parts.isEmpty {
            return "没有可执行的操作。"
        }
        return parts.joined(separator: "\n")
    }
}
