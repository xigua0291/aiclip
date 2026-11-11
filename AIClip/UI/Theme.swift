import SwiftUI

enum EditorTheme {
    static let background = Color(red: 0.05, green: 0.055, blue: 0.08)
    static let panel = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let panelElevated = Color(red: 0.14, green: 0.15, blue: 0.20)
    static let accent = Color(red: 0.42, green: 0.75, blue: 0.98)
    static let accentSoft = Color(red: 0.42, green: 0.75, blue: 0.98).opacity(0.18)
    static let warning = Color(red: 0.95, green: 0.78, blue: 0.40)
    static let danger = Color(red: 0.94, green: 0.35, blue: 0.36)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let clipFill = Color(red: 0.23, green: 0.36, blue: 0.62)
    static let clipSelected = Color(red: 0.32, green: 0.55, blue: 0.92)
    static let playhead = Color(red: 0.98, green: 0.86, blue: 0.42)
}
