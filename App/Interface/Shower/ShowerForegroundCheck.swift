import SwiftUI
import Core

/// The automatic check of the controller while the app is active, on any page: every
/// `ShowerAutoReview.tick` it asks the live model to look, and the model sends the read-only probe
/// only when the record allows it and the interval has passed (`ShowerModel.autoReviewIfDue`).
/// Stops when the app leaves the foreground.
struct ShowerForegroundCheck: ViewModifier {
    let shower: ShowerModel
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.task(id:phase == .active) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await shower.autoReviewIfDue()
                try? await Task.sleep(for:ShowerAutoReview.tick)
            }
        }
    }
}
