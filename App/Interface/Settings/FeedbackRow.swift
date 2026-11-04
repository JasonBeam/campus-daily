import SwiftUI

/// Settings › 反馈问题 (both themes): opens the feedback form. Absent from builds without the
/// feedback key.
struct FeedbackRow: View {
    @State private var open = false

    var body: some View {
        if let endpoint = FeedbackReporter.endpoint, let http = AppEnvironment.feedbackHTTP {
            Button { open = true } label: { SettingsRow(symbol:"bubble.left", title:"反馈问题") }
                .accessibilityIdentifier("feedbackRow")
                .sheet(isPresented:$open) { FeedbackView(endpoint:endpoint, http:http) }
        }
    }
}
