import Foundation

/// The portal token: exchanging it for a card session when the card session is dead, and
/// stamping and logging the credentials' lifetimes.
extension SchoolSession {
    enum Renewal { case renewed((BoundCard, EcyktSession)), stopped(SchoolReading) }

    /// The card session is dead: the portal token, else the saved password, once each.
    func renew(_ stored: EcyktSession, firstError e: ServiceError, since started: Int,
                       mayMint: @Sendable () async -> Bool, owning: LeaseOwnership) async -> Renewal {
        var lastError = e
        var triedPortal = false
        // The portal exchange got no answer about the login; reported if the password can't go.
        var portalNoAnswer: ServiceError?
        let seenPortalToken = (try? vault.portalToken()) ?? nil
        if let portalToken = seenPortalToken, portalToken.expiresAt.map({ $0 > now() }) ?? true {
            triedPortal = true
            var exchanged = false
            do {
                let fresh = try await exchangeSession(portalToken: portalToken, userAgent: stored.userAgent, previous: stored)
                exchanged = true
                let found = try await liveCard(fresh)
                // The portal works again: a hold left by an earlier outage goes, so Settings
                // no longer shows automatic sign-in as held and the password is the way back
                // in again when this portal token dies.
                if let saved = (try? vault.account()) ?? nil, saved.unansweredAt != nil {
                    _ = updateSavedAccount(saved, since: started, owning: owning) { $0.unansweredAt = nil }
                }
                return .renewed(found)
            } catch let e2 as ServiceError where e2.isSessionExpired {
                if e2 == .sessionExpired(.portal) {
                    logExpired(.portal, obtainedAt: portalToken.obtainedAt, lastAliveAt: nil)
                }
                lastError = e2
            } catch let e2 as ServiceError where Self.isDefiniteRefusal(e2) {
                // The school turned the re-exchange down: the ecykt login is still known dead.
                return .stopped(SchoolReading(outcome: .needsLogin(e), checkedAt: now()))
            } catch let e2 as ServiceError where e2 == .offline || exchanged {
                // No network: the password would not get through either, a failed read. Or the
                // exchange worked and only the check of the new session got no answer: the next
                // refresh exchanges the same portal token again.
                return .stopped(SchoolReading(outcome: .failed(e2), checkedAt: now()))
            } catch let e2 as ServiceError {
                // A timeout, a school server error or a bare 401/403: the portal (or the exchange
                // behind it) may be down while CAS works, and its token would keep failing until
                // it expires. The saved password goes once. Its hold stays on unless that login
                // ends with a card session, so the password does not go on every refresh.
                portalNoAnswer = e2
            } catch {
                // Cancelled (the widget at its deadline): nothing is known.
                return .stopped(SchoolReading(outcome: .interrupted, checkedAt: now()))
            }
        }
        switch await signInWithSavedPassword(previous: stored, seenPortalToken: seenPortalToken?.value,
                                             since: started, mayMint: mayMint, owning: owning) {
        case .signedIn(let found): return .renewed(found)
        case .offline: return .stopped(SchoolReading(outcome: .failed(portalNoAnswer ?? .offline), checkedAt: now()))
        case .failed(let e2): return .stopped(SchoolReading(outcome: .failed(e2), checkedAt: now()))
        case .retryLater: return .stopped(SchoolReading(outcome: .interrupted, checkedAt: now()))
        case .notTried:
            // No password to send (none saved, paused, or held): after a portal exchange that got
            // no answer, its token is still the way in, so that is a failed read.
            let outcome: SchoolReading.Outcome = portalNoAnswer.map { .failed($0) } ?? .needsLogin(lastError)
            return .stopped(SchoolReading(outcome: outcome, checkedAt: now()))
        case .unavailable: return .stopped(SchoolReading(outcome: .needsLogin(lastError), checkedAt: now()))
        case .lostLease: return .stopped(SchoolReading(outcome: .leaseLost, checkedAt: now()))
        case .signedOut: return .stopped(SchoolReading(outcome: .notSignedIn, checkedAt: now()))
        }
    }

    /// A definite answer from the school about a login: the credential is dead, the request
    /// was turned down with the service's own code, or our parameters are wrong. No network, a
    /// timeout, TLS, an unreadable reply or a bare HTTP status (a gateway's 5xx, say) is no
    /// answer: trying again later may work.
    static func isDefiniteRefusal(_ e: ServiceError) -> Bool {
        switch e {
        case .sessionExpired, .badRequest: return true
        case .rejected(_, let code, _): return !code.hasPrefix("HTTP ")
        case .offline, .timedOut, .tls, .malformed, .uncertain: return false
        }
    }

    enum CredentialKind: String { case card, portal }

    /// One line per dead credential: which kind, minutes since it was obtained, and (card) minutes
    /// from obtaining it to the last time it was seen alive. Never values.
    static func expiredEvent(_ kind: CredentialKind, obtainedAt: Date?, lastAliveAt: Date?, now: Date) -> String {
        func minutes(_ from: Date?, _ to: Date) -> String {
            from.map { String(max(0, Int(to.timeIntervalSince($0) / 60))) } ?? "unknown"
        }
        var line = "school.credentialExpired kind=\(kind.rawValue) ageMinutes=\(minutes(obtainedAt, now))"
        if kind == .card { line += " aliveMinutes=" + (lastAliveAt.map { minutes(obtainedAt, $0) } ?? "unknown") }
        return line
    }

    func logExpired(_ kind: CredentialKind, obtainedAt: Date?, lastAliveAt: Date?) {
        // A credential without a stamp (saved by an older build) is logged once per process.
        let id = kind.rawValue + (obtainedAt.map { "@\($0.timeIntervalSince1970)" } ?? "@unknown")
        guard loggedExpiries.insert(id).inserted else { return }
        let line = Self.expiredEvent(kind, obtainedAt: obtainedAt, lastAliveAt: lastAliveAt, now: now())
        diagnostic(line)
    }

    /// A portal token gets its `obtainedAt` when this app first saves it.
    func stamped(_ token: PortalToken) -> PortalToken {
        var t = token
        if t.obtainedAt == nil { t.obtainedAt = now() }
        return t
    }

    /// The stored card session and portal token are still the ones a refresh started from
    /// (a read that fails counts as changed: nothing is sent on a guess).
    func credentialsUnchanged(previous: EcyktSession, seenPortalToken: String?) -> Bool {
        let session: EcyktSession?, portal: PortalToken?
        do { session = try vault.ecyktSession(); portal = try vault.portalToken() } catch { return false }
        guard let session, session.token == previous.token, session.syscustid == previous.syscustid else { return false }
        return portal?.value == seenPortalToken
    }

    func exchangeSession(portalToken: PortalToken, userAgent: String, previous: EcyktSession?) async throws -> EcyktSession {
        let url = try await portal.eCardTicketURL(portalToken)
        guard let ticket = CASTicket.extract(from: url) else { throw ServiceError.malformed(.portal, "data.pcUrl") }
        let areacode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "areacode" }?.value ?? previous?.areacode ?? EcyktSession.defaultAreacode
        let login = try await ecykt.exchange(ticket: ticket, areacode: areacode, userAgent: userAgent)
        return EcyktSession(token: login.token, syscustid: login.syscustid, custid: previous?.custid,
                            cardUnionID: previous?.cardUnionID, areacode: areacode, userAgent: userAgent, obtainedAt: now())
    }
}
