import Foundation

/// The shower page as a page pushed on a navigation stack (清爽) rather than a cover: it stays
/// on the stack after the model lets it go, so it says what is left to show then.
extension ShowerPageFlow {
    /// The back button and the tab bar show: the page is down, or water runs (going back
    /// collapses it, as the cover's ⌄ does). Connecting, settling and a result to answer keep the
    /// user on it.
    public var mayLeave: Bool { !presented || mayCollapse }

    /// The face the pushed page shows; nil when there is no session to show (ready to start).
    /// Once the page is down an answered result (done, denied, not connected) is not shown again;
    /// a shower that is over (the next one starts there) and a session in progress are.
    public var pushedPhase: ShowerPagePhase? {
        guard let phase = page?.phase else { return nil }
        if presented { return phase }
        switch phase {
        case .done, .denied, .connectFailed: return nil
        case .connecting, .running, .settling, .stopped: return phase
        }
    }
}
