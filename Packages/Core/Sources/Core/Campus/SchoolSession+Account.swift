import Foundation

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
            guard SignedInPerson.match(before, cardUnionID: card.unionID, account: nil) == .same else {
                throw SchoolLoginFailure.differentAccount
            }
            exchanged = updated
        }
        let vault = vault, portalToken = stamped(token), saving = SchoolAccount(account: account, password: password)
        try Self.commitLogin(owning, vault, from: start) {
            if let exchanged { try vault.saveEcyktSession(exchanged) }
            try vault.savePortalToken(portalToken)
            try vault.saveAccount(saving)
        }
    }

    /// Turning 保存密码 off: the password goes; the account name stays for display. Read and
    /// written inside the lease file's lock (`RefreshLease.locked`, whoever holds the lease), so
    /// it never lands between a refresh's compare and write of the saved account: that refresh's
    /// write-back then finds another password and leaves the account alone. Never waits for the
    /// lease itself, so a refresh running elsewhere doesn't make it fail. A lease file that
    /// can't be locked (before the first unlock) throws and leaves the password stored.
    public func forgetPassword(lockingWith lease: RefreshLease?) throws {
        let vault = vault
        let forget = {
            guard let stored = try vault.account(), stored.password != nil else { return }
            try vault.saveAccount(SchoolAccount(account: stored.account))
        }
        if let lease { try lease.locked(forget) } else { try forget() }
    }

    /// The person signed in when `stored` was read, or nil when nobody was. A card session or
    /// account that is stored but no longer decodes still means someone was: a person nobody can
    /// tell (what it does tell, the other item, still counts).
    static func signedInPerson(_ stored: StoredCredentials) -> SignedInPerson? {
        guard stored.session != nil || stored.account != nil || stored.unreadablePerson else { return nil }
        return SignedInPerson(cardUnionID: stored.session?.cardUnionID, account: stored.account?.account)
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
        /// Decoded for the login's own use; nil when absent or no longer decodable.
        var session: EcyktSession?
        var account: SchoolAccount?
        static func == (a: StoredCredentials, b: StoredCredentials) -> Bool { a.bytes == b.bytes }
        /// The card session or the account is stored and doesn't decode: someone was signed in,
        /// and it can't be told who.
        var unreadablePerson: Bool {
            bytes.count == 3 && ((bytes[0] != nil && session == nil) || (bytes[2] != nil && account == nil))
        }
    }

    /// Throws only when the store can't be read (before the first unlock, say).
    static func storedCredentials(_ vault: SchoolVault) throws -> StoredCredentials {
        StoredCredentials(bytes: try vault.credentialBytes(), session: (try? vault.ecyktSession()) ?? nil,
                          account: (try? vault.account()) ?? nil)
    }

    /// A login's writes (sign-in from the form or the web page, 保存密码) in one locked step:
    /// the lease is still ours (`owning`) and the stored credentials are still the ones the login
    /// started from, then `writes` runs. Otherwise the other process took over meanwhile (this
    /// process was suspended past the lease, say) and may have stored newer credentials: nothing
    /// is written and `SchoolLoginFailure.busy` is thrown, so the user tries again.
    static func commitLogin<T>(_ owning: LeaseOwnership, _ vault: SchoolVault, from start: StoredCredentials,
                               _ writes: () throws -> T) throws -> T {
        let result = try owning.write { () throws -> T? in
            guard (try? storedCredentials(vault)) == start else { return nil }
            return try writes()
        }
        guard let done = result, let value = done else { throw SchoolLoginFailure.busy }
        return value
    }

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
        let match = SignedInPerson.match(before, cardUnionID: card.unionID, account: account)
        let vault = vault, token = stamped(portalToken)
        var writing = false
        let old: SchoolProfile?, profile: SchoolProfile
        do {
            (old, profile) = try Self.commitLogin(owning, vault, from: start) { () -> (SchoolProfile?, SchoolProfile) in
                writing = true
                let old = (try? vault.profile()) ?? nil
                if match == .different { try Self.clearPreviousPerson(vault) }
                try vault.savePortalToken(token)
                try vault.saveEcyktSession(updated)
                var profile = (try? vault.profile()) ?? SchoolProfile()
                if let residence {
                    if profile.residence?.address != residence.address { profile.meter = nil }
                    profile.residence = residence
                } else if match != .same {
                    profile = SchoolProfile()
                }
                try vault.saveProfile(profile)
                if let saving { try vault.saveAccount(saving) }
                return (old, profile)
            }
        } catch {
            // A write failed after the step began (the previous person's items may be gone
            // already): their work still in flight is stale all the same.
            if writing, match != .same { started = newPerson() }
            throw error
        }
        if match != .same { started = newPerson() }
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
        let match = SignedInPerson.match(before, cardUnionID: card.unionID, account: nil)
        let switched = match == .different
        // As for the form sign-in: without the new dorm, a dorm and meter that may be someone
        // else's are not kept. No dorm is read here, so that happens right here.
        let dropDorm = match == .unknown && before != nil
        let vault = vault
        var writing = false
        let old: SchoolProfile?
        do {
            old = try Self.commitLogin(owning, vault, from: start) { () -> SchoolProfile? in
                writing = true
                let old = (try? vault.profile()) ?? nil
                if switched { try Self.clearPreviousPerson(vault) }
                // The web page never tells us the account: a saved password stays only when the
                // card shows it is the same person (the widget keeps signing in with it).
                // Nor its portal token: a re-exchange with it would sign the previous person in again.
                if match != .same {
                    try vault.saveAccount(nil)
                    try vault.savePortalToken(nil)
                }
                try vault.saveEcyktSession(updated)
                if dropDorm { try vault.saveProfile(SchoolProfile()) }
                return old
            }
        } catch {
            // As for the form sign-in: begun writes make the previous person's work stale.
            if writing, match != .same { _ = newPerson() }
            throw error
        }
        if match != .same { _ = newPerson() }
        return SignInSummary(switchedAccount: switched,
                             previousPersonUnconfirmed: before != nil && match == .unknown,
                             dormAndMeterCleared: Self.cleared(old, now: (try? vault.profile()) ?? nil))
    }

    /// Some school items could not be deleted (item names only, never values).
    public struct SignOutFailure: Error, Sendable, Equatable {
        public var items: [String]
    }

    /// Deletes the saved password first (it sits in the shared group the widget reads), then
    /// everything else; the credentials' obtained/alive times go with their items. (The refresh
    /// lease is the refresher's: `SnapshotRefresher.clear()`.) A failed deletion doesn't stop the rest; the failures are reported
    /// together at the end.
    public func signOut() throws {
        signOutGeneration += 1
        personGeneration += 1
        loggedExpiries = []
        var failed: [String] = []
        let steps: [(String, () throws -> Void)] = [
            ("account", { try self.vault.saveAccount(nil) }),
            ("portalToken", { try self.vault.savePortalToken(nil) }),
            ("ecyktSession", { try self.vault.saveEcyktSession(nil) }),
            ("profile", { try self.vault.saveProfile(nil) }),
            ("loginDevice", { try self.vault.saveLoginDeviceID(nil) }),
        ]
        for (name, step) in steps {
            do { try step() } catch { failed.append(name) }
        }
        if !failed.isEmpty { throw SignOutFailure(items: failed) }
    }
}
