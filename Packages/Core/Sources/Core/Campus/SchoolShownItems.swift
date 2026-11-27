//
//  SchoolShownItems.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

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

    /// The items as stored now. During `.switching`, `.signedOutPendingClear`, or `.signedOut`
    /// (or an undecodable epoch), account and profile are hidden regardless of any leftover items.
    /// A Keychain read failure (before the first unlock) keeps what is shown.
    public func reread(from vault: SchoolVault) -> SchoolShownItems {
        do {
            if let epoch = try vault.sessionEpoch(), epoch.hidesAccountUI {
                return SchoolShownItems(signedIn: false, profile: nil, account: nil)
            }
        } catch let error as StorageError where error.isUndecodable {
            return SchoolShownItems(signedIn: false, profile: nil, account: nil)
        } catch {
            return self
        }
        func read<T>(_ item: () throws -> T?, else shown: T?) -> T? {
            do { return try item() } catch { return shown }
        }
        return SchoolShownItems(signedIn: vault.cardSessionStored() ?? signedIn,
                                profile: read(vault.profile, else: profile),
                                account: read(vault.account, else: account))
    }
}
