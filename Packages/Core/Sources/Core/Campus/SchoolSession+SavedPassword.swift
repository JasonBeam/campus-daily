import Foundation

/// The saved-password login a refresh falls back to, the hold written before the password goes
/// out, and the login device id.
extension SchoolSession {
    /// One login from the form or Settings. Nothing is sent when the lease was lost before a
    /// new device id could be stored (`busy`) or the id could not be stored (`cannotSave`).
    func passwordLoginOnce(account: String, password: String, owning: LeaseOwnership) async throws -> PortalToken {
        guard let passwordLogin else { throw SchoolLoginFailure.cannotLoginDirectly }
        let visitorID: String
        switch loginDeviceID(owning: owning) {
        case .id(let id): visitorID = id
        case .notSaved: throw SchoolLoginFailure.cannotSave
        case .lostLease: throw SchoolLoginFailure.busy
        }
        return try await passwordLogin.login(account: account, password: password, visitorID: visitorID)
    }

    private enum LoginDeviceID { case id(String), notSaved, lostLease }

    /// A random 32-hex id, kept for this install so the school sees the same browser each time.
    /// A new one is stored in one locked step under `owning`, only while none is stored (one
    /// the other process stored meanwhile is used instead). A new id that could not be stored
    /// (`notSaved`) is not sent: the school would see a new browser on every login.
    private func loginDeviceID(owning: LeaseOwnership) -> LoginDeviceID {
        if let id = (try? vault.loginDeviceID()) ?? nil, !id.isEmpty { return .id(id) }
        let fresh = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let vault = vault
        let step = (try? owning.write { () -> LoginDeviceID in
            if let id = (try? vault.loginDeviceID()) ?? nil, !id.isEmpty { return .id(id) }
            guard (try? vault.saveLoginDeviceID(fresh)) != nil else { return .notSaved }
            return .id(fresh)
        }) ?? nil
        return step ?? .lostLease
    }

    /// `notTried`: no password to send (none saved, paused, held, or no direct login), nothing sent.
    enum PasswordStep { case signedIn((BoundCard, EcyktSession)), offline, failed(ServiceError), notTried, unavailable, retryLater, lostLease, signedOut }

    /// The last step of the refresh: one login with the saved password. Anything but success,
    /// no network or a school server error pauses the password, so a wrong or blocked login is never repeated. After
    /// the school accepted it, only a definite refusal of the card login pauses it. A login
    /// that was sent but got no answer holds automatic logins off for a few hours instead, and so
    /// does an accepted one whose card session then could not be made.
    ///
    /// The widget can be suspended or killed at any await, so each fact is stored as soon as it
    /// is known: the hold is written before the password goes out and lifted when a refusal or
    /// no network comes back (or nothing was sent), and after an accepted password only once
    /// the card session is made; the portal token is saved as soon as the login returns it,
    /// before the exchange that follows.
    ///
    /// `previous` and `seenPortalToken` are the credentials this refresh found dead. If the
    /// other process stored new ones meanwhile (its own password login was accepted), nothing
    /// is sent: the next refresh uses them.
    /// Every write here (the hold, the pause, the portal token) is one locked step under
    /// `owning` with the compare it depends on: with the lease lost, nothing is written. A
    /// password accepted after that keeps its hold (its answer was not kept), so it is not sent
    /// again right away; the other process, which holds the lease now, carries on.
    func signInWithSavedPassword(previous: EcyktSession, seenPortalToken: String?, since started: Int,
                                         mayMint: @Sendable () async -> Bool, owning: LeaseOwnership) async -> PasswordStep {
        guard let saved = (try? vault.account()) ?? nil, let password = saved.automaticPassword(at: now()) else { return .notTried }
        // Not moved to the shared group yet: like no network, nothing is paused or held.
        if !createsLoginDeviceID, ((try? vault.loginDeviceID()) ?? nil)?.isEmpty ?? true {
            diagnostic("school.passwordLogin deferred reason=noLoginDeviceID")
            return .offline
        }
        // The portal exchange may have taken most of the lease: confirm it before the password goes out.
        guard await mayMint() else { return .lostLease }
        guard credentialsUnchanged(previous: previous, seenPortalToken: seenPortalToken) else {
            diagnostic("school.passwordLogin skipped reason=credentialsChanged")
            return .retryLater
        }
        guard let passwordLogin else { return .notTried }
        let visitorID: String
        switch loginDeviceID(owning: owning) {
        case .id(let id): visitorID = id
        case .lostLease: return .lostLease
        case .notSaved:
            // The Keychain refused the new id: an interruption, so several in a row show on home
            // as not saving.
            diagnostic("school.passwordLogin skipped reason=deviceIDNotSaved")
            return .retryLater
        }
        let sentAt = now()
        // Not written: signed out only when the account is really gone. Changed meanwhile (保存密码,
        // 重新输入密码) or a write that failed leave the user signed in, with nothing to report;
        // nothing is sent this time and the next refresh tries again.
        switch updateSavedAccount(saved, since: started, owning: owning, { $0.unansweredAt = sentAt }) {
        case .written: break
        case .lostLease: return .lostLease
        case .changed: return accountGone ? .signedOut : .retryLater
        }
        let token: PortalToken
        do {
            token = try await passwordLogin.login(account: saved.account, password: password, visitorID: visitorID)
        } catch SchoolLoginFailure.noAnswer {
            // The school may have counted this one: the hold written above stays.
            return .offline
        } catch SchoolLoginFailure.offline {
            liftHold(saved, sentAt: sentAt, since: started, owning: owning)
            return .offline
        } catch is CancellationError {
            // Cancelled before the password was sent (after it, the login reports noAnswer).
            liftHold(saved, sentAt: sentAt, since: started, owning: owning)
            return .unavailable
        } catch {
            // Only the password that was tried: one saved meanwhile (保存密码 / 重新输入密码) stays usable.
            _ = updateSavedAccount(saved, since: started, owning: owning) { $0.paused = true; $0.unansweredAt = nil }
            return .unavailable
        }
        // The school accepted the password: the portal token is kept at once, so neither this
        // process nor the other one sends the password again (a read given up after this point
        // leaves a token to exchange). It is written in one locked step while this process is
        // still the lease's owner and the stored account and portal token are still the ones
        // this login started from: a token the other process stored after taking the lease is
        // never overwritten. A lease that only ran out meanwhile (suspended, nobody took it) is
        // taken again in that step. A cancelled task (the widget at its deadline, about to be
        // suspended) writes nothing: it must not take the shared file lock then. A sign-out in
        // between (this process, or the account gone from the Keychain) drops it. The hold
        // stays on until the card session is made: any other way out of this login (the lease
        // lost, a sign-out, a cancelled exchange, a failed one) leaves it, so while the portal
        // keeps failing neither process sends the password again on every refresh.
        guard started == signOutGeneration else { return .unavailable }
        enum TokenSave { case written, gone, changed }
        let vault = vault, fresh = stamped(token)
        let saveStep = (try? owning.writeRetaking { () -> TokenSave in
            let still: SchoolAccount?
            do { still = try vault.account() } catch { return .changed }
            guard let still else { return .gone }
            let portal: PortalToken?
            do { portal = try vault.portalToken() } catch { return .changed }
            guard still.account == saved.account, portal?.value == seenPortalToken else { return .changed }
            guard (try? vault.savePortalToken(fresh)) != nil else { return .changed }
            return .written
        }) ?? nil
        switch saveStep {
        // Lost to a sign-out (it removes the lease first, then the items): reported as one.
        case nil: return accountGone ? .signedOut : .lostLease
        case .gone?: return .signedOut
        case .changed?: return .retryLater
        case .written?: break
        }
        // The account gone right after all the same (a sign-out whose removal of the lease
        // failed, so it deleted the items without it): the token is taken back out, in one more locked step. A new sign-in there writes its token before its
        // account, so a token that is no longer this one is theirs and stays.
        if accountGone {
            let removed = (try? owning.write { () -> Bool in
                guard ((try? vault.portalToken()) ?? nil)?.value == token.value else { return false }
                return (try? vault.savePortalToken(nil)) != nil
            }) ?? nil
            return removed == true ? .signedOut : .retryLater
        }
        do {
            guard await mayMint() else { return .lostLease }
            let fresh = try await exchangeSession(portalToken: token, userAgent: previous.userAgent, previous: previous)
            let found = try await liveCard(fresh)
            guard started == signOutGeneration else { return .unavailable }
            liftHold(saved, sentAt: sentAt, since: started, owning: owning)
            return .signedIn(found)
        } catch let e as ServiceError where Self.isDefiniteRefusal(e) {
            // The password worked but the school turned the card login after it down: paused as
            // before, so the next refresh does not log in again (the saved portal token is still
            // tried first).
            _ = updateSavedAccount(saved, since: started, owning: owning) { $0.paused = true }
            return .unavailable
        } catch let e as ServiceError {
            // The password was accepted; the steps after it got no answer (no network, a timeout,
            // a school server error, a bare 401/403). Nothing is paused: the next refresh
            // exchanges the portal token this login stored. The hold written before the
            // password went out stays, in the shared account item.
            return .failed(e)
        } catch is CancellationError {
            // Cancelled (the widget at its deadline): nothing is known, an interruption.
            return .retryLater
        } catch {
            return .unavailable
        }
    }

    enum AccountUpdate { case written, changed, lostLease }

    /// Changes the saved account only while it is still the one this login started from (same
    /// account and password, not signed out), in one locked step with the lease check. A lease
    /// that only ran out (nobody took it) is taken again in that step, so a hold or a pause is
    /// not skipped then.
    func updateSavedAccount(_ saved: SchoolAccount, since started: Int, owning: LeaseOwnership,
                                    _ change: (inout SchoolAccount) -> Void) -> AccountUpdate {
        guard started == signOutGeneration else { return .changed }
        let vault = vault
        let step = (try? owning.writeRetaking { () -> AccountUpdate in
            guard var current = (try? vault.account()) ?? nil,
                  current.account == saved.account, current.password == saved.password else { return .changed }
            change(&current)
            return (try? vault.saveAccount(current)) != nil ? .written : .changed
        }) ?? nil
        return step ?? .lostLease
    }

    /// The saved account was read and is not there (a read that fails says nothing).
    private var accountGone: Bool {
        do { return try vault.account() == nil } catch { return false }
    }

    /// An answer came back (or the password never left): the hold written for this login goes.
    private func liftHold(_ saved: SchoolAccount, sentAt: Date, since started: Int, owning: LeaseOwnership) {
        _ = updateSavedAccount(saved, since: started, owning: owning) { if $0.unansweredAt == sentAt { $0.unansweredAt = nil } }
    }
}
