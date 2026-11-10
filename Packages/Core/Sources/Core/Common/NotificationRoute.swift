import Foundation

/// Where a tapped reminder opens: the laundry page for a finished wash, home for the rest.
/// Carried in the notification's userInfo under "route"; anything unknown opens home.
public enum NotificationRoute: String, Sendable, Equatable {
    case home, laundry

    public init(userInfo: [AnyHashable: Any]) {
        self = (userInfo["route"] as? String).flatMap(NotificationRoute.init(rawValue:)) ?? .home
    }

    public var userInfo: [AnyHashable: Any] { ["route": rawValue] }
}
