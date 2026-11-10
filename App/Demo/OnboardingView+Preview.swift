#if DEBUG
import SwiftUI
import Core

extension OnboardingView {
    /// DEBUG demo values; when set, no real login or picker is opened.
    struct Preview {
        var dorm: String?
        /// The dorm's full directory location under the room (nil: the line is left out).
        var dormLocation: String?
        var laundryConnected = false
        /// Same-name meter locations for the dorm step's picker.
        var powerChoices: [LocationChoice] = []
        /// The same-name row already picked (design `ob-dorm-picked`).
        var picked: String?
        /// Login step: what the form starts with.
        var account = ""
        var password = ""
        var savePassword = false
        /// Login step: the account saved on this phone (prefilled; 保存密码 follows it).
        var saved: SchoolAccount?
        var loginState = SchoolLoginState.idle
        /// Controller step: checking, or what the check found.
        var waterChecking = false
        var waterOutcome: ShowerModel.InspectionOutcome?
        /// Controller step: why the check can't run now.
        var waterBlocked: String?
        /// Dorm step: what the meter lookup shows under the dorm (nil: nothing).
        var meter: DormStepMeter?
        /// Dorm step: the question's row already picked.
        var meterPicked: String?
    }
}
#endif
