import Foundation

/// The user's 「电量低于 N 度」/「校园卡低于 N 元」 lines, shared with the widget through the
/// Keychain item `shared.reminderLines`. Defaults 10 度 / 20 元.
public struct ReminderLines: Sendable, Codable, Equatable {
    public var powerKWh: Int = 10
    public var cardYuan: Int = 20
    public var power: Decimal { Decimal(powerKWh) }
    public var card: Decimal { Decimal(cardYuan) }

    public init(powerKWh: Int = 10, cardYuan: Int = 20) {
        self.powerKWh = powerKWh; self.cardYuan = cardYuan
    }

    /// Shared value, or the defaults when nothing was saved yet.
    public static func shared() -> ReminderLines {
        guard let bytes = (try? SharedKeychain.store.read(.sharedReminderLines)) ?? nil, bytes.count <= 1024,
              let value = try? JSONDecoder().decode(ReminderLines.self, from:bytes) else { return ReminderLines() }
        return value
    }
    /// App only. Returns false when the keychain refused the write.
    @discardableResult public func share() -> Bool {
        guard let bytes = try? JSONEncoder().encode(self) else { return false }
        return (try? SharedKeychain.store.write(bytes, for:.sharedReminderLines)) != nil
    }
}
