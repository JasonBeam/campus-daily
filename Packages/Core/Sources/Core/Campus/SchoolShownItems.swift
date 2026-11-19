import Foundation

/// What the app shows of the stored school items: signed in or not, the dorm and meter, the
/// account. Re-read at launch, back in the foreground and after a sign-in or sign-out.
public struct SchoolShownItems: Sendable, Equatable {
    public var signedIn: Bool
    public var profile: SchoolProfile?
    public var account: SchoolAccount?

    public init(signedIn: Bool = false, profile: SchoolProfile? = nil, account: SchoolAccount? = nil) {
        self.signedIn = signedIn; self.profile = profile; self.account = account
    }

    /// The items as stored now. One whose read fails (the Keychain before the first unlock, an
    /// item that no longer decodes) keeps what is shown: only a read that finds nothing clears it.
    public func reread(from vault: SchoolVault) -> SchoolShownItems {
        func read<T>(_ item: () throws -> T?, else shown: T?) -> T? {
            do { return try item() } catch { return shown }
        }
        return SchoolShownItems(signedIn: vault.cardSessionStored() ?? signedIn,
                                profile: read(vault.profile, else: profile),
                                account: read(vault.account, else: account))
    }
}
