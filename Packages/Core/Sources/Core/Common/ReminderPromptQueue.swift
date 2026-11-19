import Foundation

/// The automatic reminder pre-permission sheet (first paid laundry order, first home read):
/// queued until home is visible with nothing on top, then shown once ever. While the live app
/// is covered (`held`: the sample is on) a queued prompt stays queued, nothing is stored and no
/// sheet comes up; it is shown after.
@MainActor public final class ReminderPromptQueue {
    public private(set) var pending = false
    private let storage: PreferenceStorage
    private let promptedKey: String
    /// True while the live app is not on screen (the sample).
    public var held: () -> Bool

    public init(storage: PreferenceStorage, promptedKey: String, held: @escaping () -> Bool = { false }) {
        self.storage = storage
        self.promptedKey = promptedKey
        self.held = held
    }

    /// The sheet was shown once (by any trigger, 「以后再说」 included).
    public var prompted: Bool { (storage.object(forKey: promptedKey) as? Bool) ?? false }

    /// An automatic trigger: queued while the system hasn't asked and the sheet was never shown.
    public func request(notDetermined: Bool) {
        guard notDetermined, !prompted, !pending else { return }
        pending = true
    }

    /// Home is clear: true when the sheet is to show now (and it is marked shown). Held: false,
    /// still queued, nothing stored. `force`: shown whatever was stored (a DEBUG demo).
    public func take(notDetermined: Bool, showing: Bool, force: Bool = false) -> Bool {
        guard pending, !held() else { return false }
        pending = false
        guard force || (notDetermined && !prompted), !showing else { return false }
        markShown()
        return true
    }

    /// Shown from elsewhere (Settings' 「打开提醒」, a toggle switched on).
    public func markShown() { storage.set(true, forKey: promptedKey) }

    /// After a reset: nothing queued.
    public func clear() { pending = false }
}
