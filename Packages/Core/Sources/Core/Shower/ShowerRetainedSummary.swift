import Foundation

/// The showers a next use kept for the user's check (`ShowerVault.retainedShowersForBinding`:
/// only the bound student's), for display only: when each started, on which controller and why
/// it was kept. It carries no record and offers nothing to settle or delete; the records stay
/// as they are.
public struct ShowerRetainedSummary: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable, CaseIterable {
        /// Stopped on the controller before the app settled it.
        case stopped
        /// The close was sent and never confirmed (no answer, or the controller answered busy).
        case closeUnconfirmed
        /// A settlement was sent (or refused) without a clear answer.
        case settleUnconfirmed
        /// The school answered the authorization unclearly: the water may never have run.
        case authorizeUnclear
    }

    public struct Entry: Equatable, Sendable {
        public let started: Date?
        public let machine: String?
        public let reason: Reason

        public init(started: Date?, machine: String?, reason: Reason) {
            self.started = started; self.machine = machine; self.reason = reason
        }
    }

    public let entries: [Entry]
    /// The dorm's controller now (the binding's), when known: a record on it doesn't name it.
    public let currentMachine: String?

    public var count: Int { entries.count }

    public init(entries: [Entry], currentMachine: String? = nil) {
        self.entries = entries; self.currentMachine = currentMachine?.uppercased()
    }

    public init(records: [ShowerState], currentMachine: String? = nil) {
        self.init(entries: records.map { Entry(started: $0.startedAt, machine: $0.machineID, reason: Self.reason($0)) },
                  currentMachine: currentMachine)
    }

    /// Nil when none are kept or the list can't be read: then nothing is shown, and no error.
    public static func read(_ vault: some ShowerVault) -> ShowerRetainedSummary? {
        guard let records = try? vault.retainedShowersForBinding(), !records.isEmpty else { return nil }
        let current = (try? vault.binding())??.machineId
        return ShowerRetainedSummary(records: records, currentMachine: current)
    }

    static func reason(_ record: ShowerState) -> Reason {
        guard record.phase == .failed, let failure = record.failure else { return .stopped }
        switch failure.reason {
        case .closeUnconfirmed, .closeBusy: return .closeUnconfirmed
        case .authorizeUncertain, .authorizationInvalid: return .authorizeUnclear
        default: return .settleUnconfirmed
        }
    }
}
