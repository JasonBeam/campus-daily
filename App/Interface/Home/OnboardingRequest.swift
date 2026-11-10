import Foundation
import Core

/// One presentation of the onboarding cover; a new id replaces the current one. Asked for while
/// one is up (`asking`), the same one is kept (`GuideRequest`).
struct OnboardingRequest: Identifiable {
    var guide: GuideRequest<OnboardingView.Step>
    #if DEBUG
    var preview: OnboardingView.Preview? = nil
    #endif
    var id: UUID { guide.id }
    var step: OnboardingView.Step { guide.start ?? .login }

    #if DEBUG
    init(step: OnboardingView.Step, preview: OnboardingView.Preview? = nil) {
        guide = GuideRequest(start:step); self.preview = preview
    }
    #else
    init(step: OnboardingView.Step) { guide = GuideRequest(start:step) }
    #endif

    /// The cover asked for at `step` with `current` up: `current` kept while it is.
    static func asking(_ step: OnboardingView.Step, over current: OnboardingRequest?) -> OnboardingRequest {
        guard var request = current else { return OnboardingRequest(step:step) }
        request.guide = GuideRequest.ask(step, over:request.guide)
        return request
    }
}
