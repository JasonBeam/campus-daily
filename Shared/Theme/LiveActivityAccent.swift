import SwiftUI
import Core

/// The Live Activities' accent on their dark card (#121212 at 82% in both themes): #FF8A45 in
/// 暖橙, #8ABAFF in 清爽. Read from the shared theme each time an activity is drawn, so a switch
/// in the app shows at the next update.
enum LiveActivityAccent {
    static let warm = Color(red:1, green:138 / 255, blue:69 / 255)
    static var current: Color { ThemePreference.shared() == .clear ? ClearPalette.liveAccent : warm }
}
