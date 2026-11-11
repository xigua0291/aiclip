import SwiftUI

@main
struct AIClipApp: App {
    @State private var store = EditorStore()
    @State private var settings = AISettingsStore()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(store)
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}
