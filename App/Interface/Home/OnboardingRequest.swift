import Foundation

/// One presentation of the onboarding cover; a new id replaces the current one.
struct OnboardingRequest: Identifiable {
    let id = UUID()
    var step: OnboardingView.Step
    var preview: OnboardingView.Preview? = nil
}
