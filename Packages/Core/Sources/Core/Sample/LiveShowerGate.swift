import Foundation
import Observation

/// The one place that decides between 「先看看示例」 and a live hot-water step that may reach the
/// controller or the platform (开始洗澡, 结束, 检查水控状态 / 再查一次水控, 再结算一次), so the two
/// never overlap: the sample opens only while the real shower record is known to be at rest and
/// no such step is under way, and every such step is refused while the sample is shown. Both
/// decisions are made here, on the main actor, each in one step with nothing awaited between
/// the check and the claim (`claimSample`, `claimLiveStep`).
@MainActor @Observable public final class LiveShowerGate {
    /// What the live hot-water side knows of its record.
    public enum Record: Equatable, Sendable {
        /// Not read yet (the launch is still loading it).
        case notLoaded
        /// It could not be read (Keychain error, a record another build wrote, a failed write).
        case unreadable
        case known(ShowerState)
    }

    /// The live record as of now. Set by the live hot-water model; until then nothing is known.
    @ObservationIgnored public var record: @MainActor () -> Record
    /// The sample is shown (claimed by `claimSample`, given back by `sampleLeft`).
    public private(set) var sampleShown = false
    /// Live steps between `claimLiveStep` and `liveStepEnded`.
    public private(set) var liveStepsUnderWay = 0

    public init(record: @escaping @MainActor () -> Record = { .notLoaded }) {
        self.record = record
    }

    /// The sample may open now: the record is at rest and no live step is under way.
    public var sampleAllowed: Bool {
        !sampleShown && liveStepsUnderWay == 0 && Self.allowsSample(record())
    }

    /// The record is at rest: idle, done (settled), or failed, whether it issued nothing or
    /// awaits review (待核对: nothing runs any more, only the school's record can say what was
    /// charged). A session still under way (connecting, water on or maybe on, closing, settling;
    /// also a running record to check), and any record not known, refuses. While the sample is
    /// shown no live step begins (`claimLiveStep`): no start, no 再结算一次, no check of the
    /// controller, no 结束.
    public static func allowsSample(_ record: Record) -> Bool {
        guard case .known(let state) = record else { return false }
        switch state.phase {
        case .idle, .done, .failed: return true
        case .authorizing, .writePending, .running, .closing, .settling: return false
        }
    }

    /// The sample opens: true when it may (and from now on no live step begins).
    func claimSample() -> Bool {
        guard sampleAllowed else { return false }
        sampleShown = true
        return true
    }

    /// The sample was left: live steps may begin again.
    func sampleLeft() { sampleShown = false }

    /// A live step begins: true when it may (the sample is not shown); then `liveStepEnded` must
    /// follow once the step returned and its record is known here.
    public func claimLiveStep() -> Bool {
        guard !sampleShown else { return false }
        liveStepsUnderWay += 1
        return true
    }

    public func liveStepEnded() { liveStepsUnderWay = max(0, liveStepsUnderWay - 1) }
}
