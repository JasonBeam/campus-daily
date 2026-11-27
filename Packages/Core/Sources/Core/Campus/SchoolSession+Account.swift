//
//  SchoolSession+Account.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Account storage: the app's own sign-in, 保存密码 on and off, the web sign-in, sign-out, and
/// the one locked step every login writes its credentials in.
extension SchoolSession {
    /// Sign-in from the app's own form: one password login, then the same path as a portal
    /// token from the web page. The password is kept only when `savePassword` is on.
    /// Throws `SchoolLoginFailure` for the login itself, `ServiceError` for the steps after it.
    /// Everything is written in one locked step under `owning` (see `commitLogin`): the lease
    /// lost meanwhile, nothing is written and `SchoolLoginFailure.busy` is thrown.
    public func signIn(account: String, password: String, savePassword: Bool, owning: LeaseOwnership) async throws -> SignInSummary {
        var started = personGeneration
        let start = try Self.storedCredentials(vault)
        let before = Self.signedInPerson(start)
        let token = try await passwordLoginOnce(account: account, password: password, owning: owning)
        try ensureSignedIn(since: started)
        return try await signIn(portalToken: token, account: account,
                                saving: SchoolAccount(account: account, password: savePassword ? password : nil),
                                before: before, start: start, started: &started, owning: owning)
    }

    /// Settings › 学校账号 › 保存密码 / 重新输入密码: checks the password with one login before
    /// keeping it. It never switches person: an account other than the signed-in one is refused
    /// (`differentAccount`) without a login when the account is known, and after a web sign-in
    /// (account unknown) the login's card must be the signed-in card. A saved password clears
    /// any pause.
    public func savePassword(_ password: String, account given: String? = nil, owning: LeaseOwnership) async throws {
        let start = try Self.storedCredentials(vault)
        if let phase = start.epochPhase, phase == .switching || phase == .signedOutPendingClear || phase == .signedOut {
            throw SchoolLoginFailure.busy
        }
        // Nobody can tell who is signed in: the password can't be checked against them.
        if start.unreadablePerson { throw SchoolLoginFailure.unreadableAccount }
        let stored = start.account
        if let known = stored?.account, let given, given != known { throw SchoolLoginFailure.differentAccount }
        guard let account = given ?? stored?.account, !account.isEmpty else {
            throw SchoolLoginFailure.wrongCredentials
        }
        let started = personGeneration
        let before = Self.signedInPerson(start)
        let token = try await passwordLoginOnce(account: account, password: password, owning: owning)
        try ensureSignedIn(since: started)
        var exchanged: EcyktSession?
        if stored?.account == nil, let current = start.session {
            // Web sign-in: only the card says whose login this was.
            let session = try await exchangeSession(portalToken: token, userAgent: current.userAgent, previous: current)
            let (card, updated) = try await liveCard(session)
            try ensureSignedIn(since: started)
            guard SignedInPerson.match(before, cardUnionID: Self.evidence(card, updated), account: nil) == .same else {
                throw SchoolLoginFailure.differentAccount
            }
            exchanged = updated
        }
        let vault = vault, portalToken = stamped(token), saving = SchoolAccount(account: account, password: password)
        try await Self.commitLogin(owning, vault, from: start) {
            if let epoch = try vault.sessionEpoch(), epoch.hidesAccountUI {
                throw SchoolLoginFailure.busy
            }
            if let exchanged { try vault.saveEcyktSession(exchanged) }
            try vault.savePortalToken(portalToken)
            try vault.saveAccount(saving)
        }
    }

    /// Turning 保存密码 off: the password goes; the account name stays for display. Read and
    /// written inside the commit lock (`SharedLock.lockedWhenFree`), failing closed when no lock
    /// is available or the lock cannot be acquired.
    public func forgetPassword(lockingWith lock: (any SharedLock)?) async throws {
        guard let lock else { throw LeaseFile.Failure(step: "lock", code: ENOENT) }
        let vault = vault
        try await lock.lockedWhenFree {
            if let epoch = try vault.sessionEpoch(), epoch.hidesAccountUI { return }
            guard let stored = try vault.account(), stored.password != nil else { return }
            try vault.saveAccount(SchoolAccount(account: stored.account))
        }
    }

    /// The card a login's check found, as evidence of who signed in: not when it was a fallback
    /// from the card that session named (`liveCard`).
    static func evidence(_ card: BoundCard, _ session: EcyktSession) -> String? {
        session.cardIsFallback == true ? nil : card.unionID
    }

    /// The person signed in when `stored` was read, or nil when nobody was. A card session or
    /// account that is stored but no longer decodes still means someone was: a person nobody can
    /// tell (what it does tell, the other item, still counts).
    /// A card a read fell back to (`EcyktSession.cardIsFallback`) is only what home shows, never
    /// evidence of who signed in: the person is then told by the account, or by nobody.
    static func signedInPerson(_ stored: StoredCredentials) -> SignedInPerson? {
        guard stored.session != nil || stored.account != nil || stored.unreadablePerson else { return nil }
        let card = stored.session?.cardIsFallback == true ? nil : stored.session?.cardUnionID
        return SignedInPerson(cardUnionID: card, account: stored.account?.account)
    }

    /// Whether a sign-in removed the dorm or meter that `old` had (another dorm counts).
    static func cleared(_ old: SchoolProfile?, now: SchoolProfile?) -> Bool {
        guard let old else { return false }
        if old.meter != nil, now?.meter == nil { return true }
        return old.residence != nil && old.residence?.address != now?.residence?.address
    }

    /// A different person signed in: drop the previous one's dorm, meter, saved account and
    /// tokens before the new ones are written. The login device id stays (same phone).
    private static func clearPreviousPerson(_ vault: SchoolVault) throws {
        try vault.saveAccount(nil)
        try vault.savePortalToken(nil)
        try vault.saveEcyktSession(nil)
        try vault.saveProfile(nil)
    }

    /// What a login compares again just before its writes: the stored card session, portal
    /// token and account, byte for byte. An item that no longer decodes (damaged, or an older
    /// shape) compares equal to itself, so the login writes over it and repairs it, as before;
    /// one the other process rewrote meanwhile compares unequal, decodable or not.
    struct StoredCredentials: Equatable {
        /// Card session, portal token, account (`SchoolVault.credentialBytes()`).
        var bytes: [Data?]
        /// Epoch id and phase at login start (`nil` on 0.11.5 upgrade / fresh install).
        var epochID: String?
        var epochPhase: SessionEpoch.Phase?
        /// Decoded for the login's own use; nil when absent or no longer decodable.
        var session: EcyktSession?
        var account: SchoolAccount?
        static func == (a: StoredCredentials, b: StoredCredentials) -> Bool {
            guard a.bytes == b.bytes, a.epochID == b.epochID else { return false }
            if a.epochPhase == b.epochPhase { return true }
            if a.epochPhase == .activePendingClear && b.epochPhase == .active { return true }
            if a.epochPhase == .signedOutPendingClear && b.epochPhase == .signedOut { return true }
            return false
        }
        /// The card session or the account is stored and doesn't decode: someone was signed in,
        /// and it can't be told who.
        var unreadablePerson: Bool {
            bytes.count == 3 && ((bytes[0] != nil && session == nil) || (bytes[2] != nil && account == nil))
        }
    }

    /// Throws only when the store can't be read (before the first unlock, say).
    static func storedCredentials(_ vault: SchoolVault) throws -> StoredCredentials {
        let bytes = try vault.credentialBytes()
        let epochID: String?
        let epochPhase: SessionEpoch.Phase?
        do {
            let epoch = try vault.sessionEpoch()
            epochID = epoch?.id
            epochPhase = epoch?.phase
        } catch let error as StorageError where error.isUndecodable {
            epochID = "<undecodable>"
            epochPhase = .switching
        }
        return StoredCredentials(bytes: bytes, epochID: epochID, epochPhase: epochPhase,
                                 session: (try? vault.ecyktSession()) ?? nil,
                                 account: (try? vault.account()) ?? nil)
    }

    private static func needsNewEpoch(match: SignedInPerson.Match, vault: SchoolVault) throws -> Bool {
        if match != .same { return true }
        do {
            if let current = try vault.sessionEpoch() {
                return !current.allowsRefreshCommit
            }
            return try vault.hasLegacyStaleMark()
        } catch let error as StorageError where error.isUndecodable {
            return true
        }
    }

    /// A login's writes (sign-in from the form or the web page, 保存密码) in one locked step:
    /// the lease is still ours (`owning`) and the stored credentials are still the ones the login
    /// started from, then `writes` runs. Otherwise the other process took over meanwhile (this
    /// process was suspended past the lease, say) and may have stored newer credentials: nothing
    /// is written and `SchoolLoginFailure.busy` is thrown, so the user tries again.
    static func commitLogin<T>(isolation: isolated (any Actor)? = #isolation, _ owning: LeaseOwnership, _ vault: SchoolVault,
                               from start: StoredCredentials, _ writes: () throws -> T) async throws -> T {
        let result = try await owning.write { () throws -> T? in
            guard (try? storedCredentials(vault)) == start else { return nil }
            return try writes()
        }
        guard let done = result, let value = done else { throw SchoolLoginFailure.busy }
        return value
    }

    /// Anyone but the same person first marks the shared snapshot stale (`markSnapshotStale`),
    /// in the same locked step and before any other write: from then on nobody reads the
    /// previous person's numbers, whether or not their clean-up can write. A mark that can't be
    /// written fails the sign-in before anything changed (no change of person).
    /// A different person clears the previous one's data first. When the dorm address can't be
    /// read, the old dorm and meter are kept only if the card shows it is the same person.
    /// Anyone but the same person makes work still running for the previous one stale, from the
    /// moment the locked step starts writing (also when one of its writes then fails, the
    /// previous person's items maybe gone already); `started` then moves on to the new person. `saving`: the account the form signed in with. Every
    /// write is one locked step (`commitLogin`) over the credentials read at `start`.
    private func signIn(portalToken: PortalToken, account: String?, saving: SchoolAccount?, before: SignedInPerson?,
                        start: StoredCredentials, started: inout Int, owning: LeaseOwnership) async throws -> SignInSummary {
        let residence = try? await portal.myInfo(portalToken)
        let session = try await exchangeSession(portalToken: portalToken, userAgent: EcyktSession.defaultUserAgent, previous: nil)
        let (card, updated) = try await liveCard(session)
        try ensureSignedIn(since: started)
        let match = SignedInPerson.match(before, cardUnionID: Self.evidence(card, updated), account: account)
        let vault = vault, token = stamped(portalToken)
        var writing = false
        var switchedEpoch = false
        let old: SchoolProfile?, profile: SchoolProfile
        do {
            (old, profile) = try await Self.commitLogin(owning, vault, from: start) { () -> (SchoolProfile?, SchoolProfile) in
                let healthyPreviousEpoch = try !Self.needsNewEpoch(match: .same, vault: vault)
                let needsSwitch = match != .same || !healthyPreviousEpoch
                let newEpochID: String? = needsSwitch ? UUID().uuidString : nil
                if let newEpochID {
                    try vault.saveSessionEpoch(SessionEpoch(id: newEpochID, phase: .switching))
                }
                writing = true
                if needsSwitch { switchedEpoch = true }
                let old = (try? vault.profile()) ?? nil
                if needsSwitch { try Self.clearPreviousPerson(vault) }
                try vault.savePortalToken(token)
                try vault.saveEcyktSession(updated)
                let reuseMeterForConfirmedRoom = !needsSwitch || (match == .unknown && healthyPreviousEpoch)
                var profile = reuseMeterForConfirmedRoom ? (old ?? SchoolProfile()) : SchoolProfile()
                if let residence {
                    if profile.residence?.address != residence.address { profile.meter = nil }
                    profile.residence = residence
                } else if match != .same || needsSwitch {
                    profile = SchoolProfile()
                }
                try vault.saveProfile(profile)
                if let saving { try vault.saveAccount(saving) }
                // Post-write read-back verification inside the same commit lock.
                let readSession = try vault.ecyktSession()
                let readToken = try vault.portalToken()
                let readAccount = try vault.account()
                guard readSession == updated, readToken == token,
                      (saving != nil ? readAccount == saving : (!needsSwitch || readAccount == nil)) else {
                    throw StorageError(operation: "verify credentials", status: -1)
                }
                if let newEpochID {
                    try vault.saveSessionEpoch(SessionEpoch(id: newEpochID, phase: .activePendingClear))
                }
                return (old, profile)
            }
        } catch {
            // A write failed after the step began (the previous person's items may be gone
            // already): their work still in flight is stale all the same.
            if writing, (match != .same || switchedEpoch) { started = newPerson() }
            throw error
        }
        if match != .same || switchedEpoch { started = newPerson() }
        return SignInSummary(switchedAccount: match == .different,
                             previousPersonUnconfirmed: before != nil && match == .unknown,
                             dormAndMeterCleared: Self.cleared(old, now: profile))
    }

    /// Fallback while the ticket exchange is uncaptured: adopt the
    /// `localStorage.elecampus_state` the official page wrote, then validate it.
    /// The card session and account are written in one locked step under `owning`
    /// (`commitLogin`): the lease lost meanwhile, nothing is written and `busy` is thrown.
    /// No portal token comes with it, so no dorm is read here (the app keeps the dorm address
    /// the portal page showed).
    public func adoptWebState(_ elecampusState: Data, owning: LeaseOwnership) async throws -> SignInSummary {
        guard let root = try? JSONValue.parse(elecampusState),
              let token = (root["logintoken"] ?? root["loginInfo"]?["token"])?.text, !token.isEmpty,
              let sys = root["loginInfo"]?["syscustid"]?.text, !sys.isEmpty else {
            throw ServiceError.malformed(.ecykt, "elecampus_state")
        }
        let areacode = root["schoolid"]?.text ?? EcyktSession.defaultAreacode
        let session = EcyktSession(token: token, syscustid: sys, custid: root["custInfo"]?["custid"]?.text,
                                   cardUnionID: root["custInfo"]?["custunionid"]?.text, areacode: areacode, userAgent: EcyktSession.defaultUserAgent,
                                   obtainedAt: now())
        let started = personGeneration
        let start = try Self.storedCredentials(vault)
        let before = Self.signedInPerson(start)
        let (card, updated) = try await liveCard(session)
        try ensureSignedIn(since: started)
        let match = SignedInPerson.match(before, cardUnionID: Self.evidence(card, updated), account: nil)
        let switched = match == .different
        // As for the form sign-in: without the new dorm, a dorm and meter that may be someone
        // else's are not kept. No dorm is read here, so that happens right here.
        let dropDorm = match == .unknown && before != nil
        let vault = vault
        var writing = false
        var switchedEpoch = false
        let old: SchoolProfile?
        do {
            old = try await Self.commitLogin(owning, vault, from: start) { () -> SchoolProfile? in
                let needsSwitch = try Self.needsNewEpoch(match: match, vault: vault)
                let newEpochID: String? = needsSwitch ? UUID().uuidString : nil
                if let newEpochID {
                    try vault.saveSessionEpoch(SessionEpoch(id: newEpochID, phase: .switching))
                }
                writing = true
                if needsSwitch { switchedEpoch = true }
                let old = (try? vault.profile()) ?? nil
                if needsSwitch { try Self.clearPreviousPerson(vault) }
                // The web page never tells us the account: a saved password stays only when the
                // card shows it is the same person (the widget keeps signing in with it).
                // Nor its portal token: a re-exchange with it would sign the previous person in again.
                try vault.saveEcyktSession(updated)
                if dropDorm && !needsSwitch { try vault.saveProfile(SchoolProfile()) }
                // Post-write read-back verification inside the same commit lock.
                guard try vault.ecyktSession() == updated else {
                    throw StorageError(operation: "verify credentials", status: -1)
                }
                if needsSwitch {
                    guard try vault.portalToken() == nil, try vault.account() == nil else {
                        throw StorageError(operation: "verify credentials", status: -1)
                    }
                }
                if let newEpochID {
                    try vault.saveSessionEpoch(SessionEpoch(id: newEpochID, phase: .activePendingClear))
                }
                return old
            }
        } catch {
            // As for the form sign-in: begun writes make the previous person's work stale.
            if writing, (match != .same || switchedEpoch) { _ = newPerson() }
            throw error
        }
        if match != .same || switchedEpoch { _ = newPerson() }
        return SignInSummary(switchedAccount: switched,
                             previousPersonUnconfirmed: before != nil && match == .unknown,
                             dormAndMeterCleared: Self.cleared(old, now: (try? vault.profile()) ?? nil))
    }

    /// Some school items could not be deleted (item names only, never values).
    public struct SignOutFailure: Error, Sendable, Equatable {
        public var items: [String]
    }

    /// Runs sign-out inside `profileLock` (failing closed without touching credentials if the
    /// lock cannot be acquired): first writes `(newID, .switching)`, deletes all school items,
    /// and only when every deletion succeeds advances to `(newID, .signedOutPendingClear)`.
    /// If any deletion fails, stays in `(newID, .switching)` so `finishPendingClear()` retries
    /// cleanup and lands in `.signedOut`.
    public func signOut() async throws {
        let vault = vault
        let newID = UUID().uuidString
        let failed: [String]
        do {
            failed = try await profileLock.lockedWhenFree { () throws -> [String] in
                do {
                    try vault.saveSessionEpoch(SessionEpoch(id: newID, phase: .switching))
                } catch {
                    throw SignOutFailure(items: ["sessionEpoch"])
                }
                var failed: [String] = []
                let steps: [(String, () throws -> Void)] = [
                    ("account", { try vault.saveAccount(nil) }),
                    ("portalToken", { try vault.savePortalToken(nil) }),
                    ("ecyktSession", { try vault.saveEcyktSession(nil) }),
                    ("profile", { try vault.saveProfile(nil) }),
                    ("loginDevice", { try vault.saveLoginDeviceID(nil) }),
                ]
                for (name, step) in steps {
                    do { try step() } catch { failed.append(name) }
                }
                if !failed.isEmpty {
                    // Stay in `(newID, .switching)` so `finishPendingClear` retries cleanup.
                    return failed
                }
                do {
                    try vault.saveSessionEpoch(SessionEpoch(id: newID, phase: .signedOutPendingClear))
                } catch {
                    return ["sessionEpoch"]
                }
                return []
            }
        } catch let error as SignOutFailure {
            throw error
        } catch {
            // Fail closed when the commit lock cannot be acquired: do not touch credentials.
            throw SignOutFailure(items: ["sessionEpoch"])
        }
        signOutGeneration += 1
        personGeneration += 1
        loggedExpiries = []
        if !failed.isEmpty { throw SignOutFailure(items: failed) }
    }
}
