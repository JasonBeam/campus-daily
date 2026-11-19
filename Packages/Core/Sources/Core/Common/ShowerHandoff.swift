import Foundation

/// `getSignData.appdata`, the school's signed hand-off to the hot-water platform.
public struct ShowerHandoff: Sendable, Equatable, CustomStringConvertible {
    public var vsuppid: String
    public var appid: String
    public var userId: String
    public var deptId: String
    public var username: String
    public var phone: String
    public var sign: String
    public var nonce: String
    public var timestamp: String
    public init(vsuppid: String, appid: String, userId: String, deptId: String, username: String,
                phone: String, sign: String, nonce: String, timestamp: String) {
        self.vsuppid = vsuppid; self.appid = appid; self.userId = userId; self.deptId = deptId
        self.username = username; self.phone = phone; self.sign = sign; self.nonce = nonce; self.timestamp = timestamp
    }
    public var description: String { "WaterHandoff(<redacted>)" }
}
