import Foundation

/// The widget process's last drawn entry, read and written from the timeline's tasks.
final class LastEntry: @unchecked Sendable {
    // @unchecked: `value` is touched only under `lock`.
    private let lock = NSLock()
    private var value: CampusEntry?
    var entry: CampusEntry? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }

    /// The last entry drawn again at `now`, so its footer says 「昨天」 once midnight has passed.
    func redrawn(at now: Date) -> CampusEntry? {
        guard let entry else { return nil }
        var model = entry.model
        model.now = now
        return CampusEntry(date:now, model:model)
    }
}
