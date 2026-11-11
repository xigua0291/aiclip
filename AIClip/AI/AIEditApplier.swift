import Foundation

/// Deterministic applier for a validated `AIEditPlan`.
/// Unknown or unsafe operations are skipped and reported; they never crash the editor.
enum AIEditApplier {
    @MainActor
    @discardableResult
    static func apply(_ plan: AIEditPlan, to store: EditorStore) -> AIApplyResult {
        store.applyAIPlan(plan)
    }
}
