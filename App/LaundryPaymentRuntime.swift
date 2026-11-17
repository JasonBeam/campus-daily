import UIKit
import WaterCore

/// UIKit may expire this lease before the local cap. Never renew it to keep the app alive.
@MainActor final class IOSLaundryPaymentRuntime: LaundryPaymentRuntime {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var deadline: Task<Void, Never>?
    private var events: [[String:String]] = []

    func begin(maximumDuration: TimeInterval, expiration: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard identifier == .invalid else { return false }
        events = []; record("requested")
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish immediate laundry payment") { [weak self] in
            self?.record("systemExpired")
            expiration()
        }
        guard identifier != .invalid else { record("denied"); return false }
        record("granted")
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(maximumDuration)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.record("localLimitReached")
            expiration()
        }
        return true
    }

    func end() {
        deadline?.cancel(); deadline = nil
        let previous = identifier; identifier = .invalid
        if previous != .invalid {
            record("ended")
            UIApplication.shared.endBackgroundTask(previous)
        }
    }

    private func record(_ event: String) {
        events.append(["event":event,"at":ISO8601DateFormatter().string(from:Date())])
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("LaundryCache",isDirectory:true)
        // Local timing only; no order/device identifiers, payment links or credentials.
        if let bytes = try? JSONSerialization.data(withJSONObject:events,options:[.sortedKeys]) {
            try? bytes.write(to:folder.appendingPathComponent("payment-background-window.json"),
                             options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
