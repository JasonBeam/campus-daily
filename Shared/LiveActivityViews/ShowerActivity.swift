import Foundation
import AppIntents
import Core
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for one hot-water shower session. Compiled into both the app and the widget.
struct ShowerActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable {
        case active, settling, settled, unconfirmed
    }
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var phase: Phase
        /// Only set once the server confirmed settlement.
        var durationMinutes: Int?
        /// Only set once the server confirmed settlement. Never an estimate.
        var amountYuan: Decimal?
        /// The authorization write got no device confirmation (stage .authorizationWritePending).
        /// Optional so states from earlier builds still decode.
        var writeUnconfirmed: Bool?
    }
    /// Short dorm label, e.g. "3 栋 108".
    var dorm: String
}
#endif

/// Shared copy for the app and the widget.
enum ShowerCopy {
    /// Under the shower timer while the authorization write is unconfirmed (Home, lock screen, expanded island).
    static let writeUnconfirmed = "水控没回应，有热水就照常洗"
}

/// Hook set by the app at launch. LiveActivityIntent.perform runs in the app process,
/// so in the widget extension this stays nil; reaching it without the hook is an error, never a silent success.
enum ShowerActivityBridge {
    @MainActor static var finish: (@MainActor () async throws -> Void)?
}

struct FinishShowerLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "结束并结算"
    static let description = IntentDescription("结束正在进行的热水会话并提交结算。")
    static let isDiscoverable = false
    // Same as FinishShowerIntent: the keychain is WhenUnlocked and Bluetooth has no background mode,
    // so finishing from the lock screen must unlock and bring the app forward.
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        guard let finish = ShowerActivityBridge.finish else { throw ShowerDeviceError.interrupted }
        try await finish()
        return .result()
    }
}
