import SwiftUI
import Core

/// 「U净 账号」 at the bottom of the common-washer page while signed in: the number (masked) and
/// 退出 U净 behind a confirmation. Greyed while an order is unfinished, with the reason under it;
/// a sign-out that didn't go through says so in the same place.
struct UjingAccountSection: View {
    let mobile: String?
    let refusal: UjingSignOut.Refusal?
    /// The last sign-out didn't go through.
    var failed = false
    let signOut: () -> Void
    @State private var confirming = false

    var body: some View {
        Section {
            if let mobile {
                LabeledContent(UjingAccountText.phone) { Text(UjingAccountText.maskedPhone(mobile)).monospacedDigit() }
            }
            Button(UjingAccountText.signOut, role:.destructive) { confirming = true }
                .disabled(refusal != nil)
                .accessibilityIdentifier("ujingSignOut")
                .confirmationDialog(UjingAccountText.confirmTitle, isPresented:$confirming, titleVisibility:.visible) {
                    Button(UjingAccountText.confirm, role:.destructive) { signOut() }
                    Button(UjingAccountText.cancel, role:.cancel) {}
                } message: { Text(UjingAccountText.confirmMessage) }
        } header: { Text(UjingAccountText.title) } footer: {
            if let footer = UjingSignOut.footer(refusal, failed:failed) { Text(footer) }
        }
    }
}
