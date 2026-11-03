import Foundation

/// The card session: liveness, writing it back, and the steps that run on it (the hot-water
/// hand-off, recharge, the card records).
extension SchoolSession {
    /// False only when the card session was read and is not there. Async like the
    /// `SchoolReader` requirement, so this is what the refresher calls (not the protocol's default).
    public func hasCardSession() async -> Bool { vault.cardSessionStored() ?? true }

    enum WriteBack { case written, kept, signedOut, lostLease }

    /// Writes the live session back (latest ciphertexts, `lastAliveAt`) only while the stored
    /// session is still `base` (same token and syscustid). Signed out in another process: nothing is written. A newer
    /// session stored by the other process stays; this read used a live one all the same.
    /// Written only while the lease is still held.
    func writeBack(_ session: EcyktSession, over base: EcyktSession, owning: LeaseOwnership) -> WriteBack {
        let vault = vault
        func compare() -> WriteBack? {
            let current: EcyktSession?
            do { current = try vault.ecyktSession() } catch { return .kept }
            guard let current else { return .signedOut }
            // Any change to the stored one (token or the rotating syscustid) means it is newer:
            // another process or a sign-in stored it.
            guard current.token == base.token, current.syscustid == base.syscustid else { return .kept }
            return nil
        }
        if let early = compare() { return early }
        // Compared again and saved in one step with the lease check: the other process can't
        // take the lease (and store its own session) between the check and the save.
        let outcome = (try? owning.write { () -> WriteBack in
            if let changed = compare() { return changed }
            try? vault.saveEcyktSession(session)
            return .written
        }) ?? nil
        return outcome ?? .lostLease
    }

    /// Liveness check, then `getSignData` for the bound card (hot-water onboarding only). The app
    /// runs it under the refresh lease; the live session is kept only over the one it started from,
    /// and only while `owning` finds the lease still held, in the same locked step.
    public func showerHandoff(owning: LeaseOwnership) async throws -> ShowerHandoff {
        guard let stored = try vault.ecyktSession() else { throw ServiceError.sessionExpired(.ecykt) }
        let started = personGeneration
        let (card, live) = try await liveCard(stored)
        try ensureSignedIn(since: started)
        saveIfUnchanged(live, over: stored, owning: owning)
        return try await ecykt.signData(live, custid: card.custid)
    }

    /// Liveness check, then one `loginBySysId`; the fresh token goes into `logintoken`. The app
    /// runs it under the refresh lease; the live session is kept only over the one it started from,
    /// and only while `owning` finds the lease still held, in the same locked step.
    public func rechargeSession(_ kind: RechargeKind, owning: LeaseOwnership) async throws -> RechargeWebSession {
        guard let stored = try vault.ecyktSession() else { throw ServiceError.sessionExpired(.ecykt) }
        let started = personGeneration
        let (card, live) = try await liveCard(stored)
        let fresh = try await ecykt.freshLogin(live)
        var updated = live
        updated.syscustid = fresh.syscustid   // latest ciphertext, valid as input next time
        try ensureSignedIn(since: started)
        saveIfUnchanged(updated, over: stored, owning: owning)
        return try RechargeWebSessionBuilder.build(kind: kind, session: updated, fresh: fresh, card: card)
    }

    /// One page of 校园卡记录 (`card/getRecordList`), read with the stored card session as it is:
    /// a read that validates nothing, so nothing is minted or written and no lease is needed.
    /// Nobody signed in, or another person signed in since `stamp` (`personStamp()`): the
    /// records are not given (`sessionExpired`).
    public func cardHistoryPage(_ query: CardHistoryQuery, since stamp: Int) async throws -> CardRecordPage {
        try ensureSignedIn(since: stamp)
        guard let s = try vault.ecyktSession(), let custid = s.custid else { throw ServiceError.sessionExpired(.ecykt) }
        let page = try await ecykt.cardRecords(s, custid: custid, begin: query.begin, end: query.end,
                                               page: query.page, pageSize: query.pageSize)
        try ensureSignedIn(since: stamp)
        return page
    }

    /// Keeps `live` (latest ciphertexts) only while the stored session is still `base` (same
    /// token and syscustid). The other process may have stored a newer one meanwhile, which
    /// stays; this call used its own live session all the same. The compare and the save run
    /// in one step with the lease check (`owning`, from `holdingLease`): lost, nothing is written.
    private func saveIfUnchanged(_ live: EcyktSession, over base: EcyktSession, owning: LeaseOwnership) {
        let vault = vault
        _ = try? owning.write {
            guard let current = (try? vault.ecyktSession()) ?? nil,
                  current.token == base.token, current.syscustid == base.syscustid else { return }
            try? vault.saveEcyktSession(live)
        }
    }

    /// `boundCards` + pick the saved card (by stable `custunionid`) or the first one.
    /// Updates the session with the latest `custid` ciphertext.
    func liveCard(_ s: EcyktSession) async throws -> (BoundCard, EcyktSession) {
        let cards = try await ecykt.boundCards(s)
        guard let card = cards.first(where: { $0.unionID != nil && $0.unionID == s.cardUnionID }) ?? cards.first else {
            throw ServiceError.rejected(.ecykt, code: "noCard", message: "这个账号还没有绑定校园卡")
        }
        var updated = s
        updated.custid = card.custid
        updated.cardUnionID = card.unionID
        return (card, updated)
    }
}
