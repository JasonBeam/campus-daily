import Foundation

/// Recharge and the hot-water hand-off on a card session that expired: it is renewed once the
/// way home renews it (portal token, else the saved password), and the step is tried once more.
/// Only when that renewal did not read the card again does the expiry reach the user, who is
/// then asked to sign in. Any other failure is passed on as it is, with nothing renewed.
public enum CardSessionRenewal {
    /// `attempt` runs at most twice. `renew` runs at most once, between the two, outside
    /// `attempt`'s lease (a refresh takes the lease itself); true when it read the card again.
    public static func renewingOnce<T>(isolation: isolated (any Actor)? = #isolation,
                                       _ attempt: () async throws -> T,
                                       renew: () async -> Bool) async throws -> T {
        do {
            return try await attempt()
        } catch let error as ServiceError where error.isSessionExpired {
            guard await renew() else { throw error }
            return try await attempt()
        }
    }
}
