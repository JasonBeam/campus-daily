import Foundation

/// Runs the school session: liveness, silent re-exchange, refresh, electricity resolution,
/// recharge web sessions. Persists credentials through `SchoolVault`; it never writes the home
/// snapshot (that is the snapshot refresher's job).
public actor SchoolSession {
    let portal: PortalClient
    let ecykt: EcyktClient
    let vault: SchoolVault
    let passwordLogin: SchoolPasswordLogin?
    let now: @Sendable () -> Date
    /// Event names and measured ages only, never values (the credential-lifetime log).
    let diagnostic: @Sendable (String) -> Void
    /// False in the widget. Every saved password came with a login device id, so a widget that
    /// sees a password but no id is running before the app moved the id (and the portal token)
    /// out of its private group; a login then would start a second "browser" at the school and
    /// the move would keep that one. The widget leaves the login to the app instead.
    let createsLoginDeviceID: Bool
    /// Expiries already logged by this process, so a dead credential read again is logged once.
    var loggedExpiries: Set<String> = []
    /// Bumped by `signOut()`. A refresh that awaited the network checks it before writing the
    /// Keychain, so a sign-out in the middle is never undone by a late write.
    var signOutGeneration = 0
    /// Bumped by `signOut()` and by every sign-in that is not known to be the same person.
    /// Sign-in, the dorm and meter, the hot-water hand-off and recharge check it before writing,
    /// so the previous person's late answer never lands in the next person's account.
    var personGeneration = 0
    /// How long the card records may take after the numbers were handed over.
    let recordsTimeout: TimeInterval
    /// Apartments whose buildings the lookup reads to find the dorm's; more and it stops there.
    static let maxApartments = 40
    /// Rooms of the dorm's number read for a meter; more and it stops at the rooms.
    static let maxCandidateRooms = 8
    /// Each read of the automatic meter lookup after a timeout or no connection: the waits before each try again.
    public static let meterRetryDelays: [TimeInterval] = [5, 20]
    let meterRetryWait: @Sendable (TimeInterval) async -> Void

    public init(portal: PortalClient, ecykt: EcyktClient, vault: SchoolVault, passwordLogin: SchoolPasswordLogin? = nil,
                now: @escaping @Sendable () -> Date = Date.init, diagnostic: @escaping @Sendable (String) -> Void = { _ in },
                createsLoginDeviceID: Bool = true,
                recordsTimeout: TimeInterval = CardActivity.timeout,
                meterRetryWait: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.portal = portal; self.ecykt = ecykt; self.vault = vault; self.passwordLogin = passwordLogin; self.now = now
        self.diagnostic = diagnostic; self.createsLoginDeviceID = createsLoginDeviceID
        self.recordsTimeout = recordsTimeout; self.meterRetryWait = meterRetryWait
    }

    // MARK: Refresh

    /// Liveness (`getSysBindCustInfo`); when the card session is dead, the same in the app
    /// (foreground or background) and in the widget: the portal token (unless it is known to
    /// have expired), else the saved password (one login, never retried; any refusal pauses it
    /// until the user signs in again). A portal exchange that times out or gets a school server
    /// error also goes on to the saved password; one with no network stops there. Then balance + meter in parallel.
    /// Never calls `loginBySysId`.
    ///
    /// Two processes share the stored session. `mayMint` is asked before each step that mints a
    /// session (portal exchange), sends the saved password, or writes a credential back (the
    /// refresher renews its cross-process lease there; false = another process took over or a
    /// sign-out removed the lease, so this read stops without touching anything more). With the lease held, a session another process
    /// stored meanwhile is used instead of minting. The session is written back only while the
    /// stored one is still the one this read started from: a sign-out or a newer session from
    /// the other process is never overwritten.
    /// `numbers` gets the reading with the balance and the meter (no records) as soon as they
    /// are in, so they can be stored before the slower card records arrive. The returned
    /// reading has all three; the records are given up `recordsTimeout` after they were asked
    /// for, which is at the same time as the balance and the meter. The card session is written
    /// back in one locked step with the lease check (`owning`, always given: `.unchecked` only
    /// where no lease exists).
    public func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool = { true }, owning: LeaseOwnership,
                        numbers: @Sendable (SchoolReading) async -> Void = { _ in }) async -> SchoolReading {
        // A read the Keychain refuses (before the first unlock) says nothing about the login:
        // only a read that finds nothing is "not signed in". A session that no longer decodes
        // won't on the next try either: the user signs in again.
        let found: EcyktSession?
        do { found = try vault.ecyktSession() } catch { return unreadableSession(error) }
        guard let stored = found else { return SchoolReading(outcome: .notSignedIn, checkedAt: now()) }
        let started = signOutGeneration

        var base = stored
        var live: (BoundCard, EcyktSession)
        do {
            live = try await liveCard(stored)
        } catch let e as ServiceError where e.isSessionExpired {
            logExpired(.card, obtainedAt: stored.obtainedAt, lastAliveAt: stored.lastAliveAt)
            guard await mayMint() else { return SchoolReading(outcome: .leaseLost, checkedAt: now()) }
            let current: EcyktSession?
            do { current = try vault.ecyktSession() } catch { return unreadableSession(error) }
            guard let current else { return SchoolReading(outcome: .notSignedIn, checkedAt: now()) }
            // What is stored now is what a renewed session is written over (`base`), so a
            // session the other process stored meanwhile doesn't make this read discard its
            // fresh one. A new one from the other process is checked first: alive, nothing is minted.
            base = current
            var firstError = e
            var found: (BoundCard, EcyktSession)?
            if current.token != stored.token {
                do {
                    found = try await liveCard(current)
                } catch let e2 as ServiceError where e2.isSessionExpired {
                    firstError = e2
                } catch let e2 as ServiceError {
                    return SchoolReading(outcome: .failed(e2), checkedAt: now())
                } catch is CancellationError {
                    // Cancelled (the widget at its deadline): nothing is known.
                    return SchoolReading(outcome: .interrupted, checkedAt: now())
                } catch {
                    return SchoolReading(outcome: .failed(.offline), checkedAt: now())
                }
            }
            if let found {
                live = found
            } else {
                switch await renew(current, firstError: firstError, since: started, mayMint: mayMint, owning: owning) {
                case .renewed(let renewed): live = renewed
                case .stopped(let reading): return reading
                }
            }
        } catch let e as ServiceError {
            return SchoolReading(outcome: .failed(e), checkedAt: now())
        } catch is CancellationError {
            // Cancelled (the widget at its deadline): nothing is known.
            return SchoolReading(outcome: .interrupted, checkedAt: now())
        } catch {
            return SchoolReading(outcome: .failed(.offline), checkedAt: now())
        }

        let card = live.0
        guard started == signOutGeneration else { return SchoolReading(outcome: .notSignedIn, checkedAt: now()) }
        let checkedAt = now()
        var alive = live.1
        alive.lastAliveAt = checkedAt
        switch writeBack(alive, over: base, owning: owning) {
        case .signedOut: return SchoolReading(outcome: .notSignedIn, checkedAt: now())
        case .lostLease: return SchoolReading(outcome: .leaseLost, checkedAt: now())
        case .written, .kept: break
        }
        let session = alive

        let binding = ((try? vault.profile()) ?? nil)?.meter
        let range = CardActivity.range(at: now())
        let timeout = recordsTimeout
        let ecykt = self.ecykt
        // Started with the other two, but nothing waits for it before the numbers are handed over.
        let records = Task {
            await Self.within(timeout) {
                await Self.captureError {
                    let page = try await ecykt.cardRecords(session, custid: card.custid, begin: range.begin, end: range.end,
                                                           page: 1, pageSize: CardActivity.pageSize, timeout: timeout)
                    return CardActivity(page: page, begin: range.begin, end: range.end, pageSize: CardActivity.pageSize)
                }
            }
        }
        async let balanceResult = capture { try await self.ecykt.balance(session, custid: card.custid) }
        async let meterResult = readMeter(session, binding: binding)
        let (b, m) = await (balanceResult, meterResult)
        guard started == signOutGeneration else {
            records.cancel()
            return SchoolReading(outcome: .notSignedIn, checkedAt: now())
        }
        if case .success(let meter?)? = m, let binding, meter.comAddress != binding.comAddress {
            followReplacedMeter(binding, to: meter.comAddress, owning: owning)
        }
        var reading = SchoolReading(outcome: .ok, checkedAt: checkedAt, balance: b, meter: m,
                                    roomLabel: m == nil ? nil : binding?.label, readAt: now(),
                                    noMeter: binding?.nodeIsRoom != true)
        await numbers(reading)
        let a = await withTaskCancellationHandler { await records.value } onCancel: { records.cancel() }
        guard started == signOutGeneration else { return SchoolReading(outcome: .notSignedIn, checkedAt: now()) }
        reading.activity = a
        return reading
    }

    /// The stored card session could not be read: a session that no longer decodes needs a
    /// sign-in; any other read failure is an interruption.
    private func unreadableSession(_ error: Error) -> SchoolReading {
        let undecodable = (error as? StorageError)?.isUndecodable == true
        return SchoolReading(outcome: undecodable ? .needsLogin(.sessionExpired(.ecykt)) : .interrupted, checkedAt: now())
    }

    // MARK: Helpers

    /// Work that awaited the network checks this before writing: a sign-out or another person
    /// signing in meanwhile wins, and the late result is dropped as if the session had expired.
    func ensureSignedIn(since started: Int) throws {
        guard started == personGeneration else { throw ServiceError.sessionExpired(.ecykt) }
    }

    /// Who is signed in now, for work outside this actor that must not outlive the person (a
    /// hot-water binding made from `showerHandoff()`): compare it with `isSamePerson(since:)`.
    public func personStamp() -> Int { personGeneration }

    /// Nobody signed out and nobody else signed in since `stamp` was taken.
    public func isSamePerson(since stamp: Int) -> Bool { stamp == personGeneration }

    /// Runs a sign-in (`attempt`) on `session` and calls `changed` when it changed who is signed
    /// in, whether it returned or threw (one that throws after its writes began has changed it).
    public static func watchingPerson<T>(on session: SchoolSession, isolation: isolated (any Actor)? = #isolation,
                                         _ attempt: () async throws -> T, changed: () -> Void) async throws -> T {
        let before = await session.personStamp()
        do {
            let result = try await attempt()
            if await session.personStamp() != before { changed() }
            return result
        } catch {
            if await session.personStamp() != before { changed() }
            throw error
        }
    }

    /// A sign-in not known to be the same person: what was started before it is stale.
    func newPerson() -> Int {
        personGeneration += 1
        return personGeneration
    }

    /// `body`'s result, or `.timedOut` once `seconds` passed (the body is then cancelled and
    /// not waited for).
    static func within<T: Sendable>(_ seconds: TimeInterval,
                                    _ body: @escaping @Sendable () async -> Result<T, ServiceError>) async -> Result<T, ServiceError> {
        let once = FirstResult<Result<T, ServiceError>>()
        let work = Task { await once.offer(await body()) }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            await once.offer(.failure(.timedOut))
        }
        let result = await withTaskCancellationHandler {
            await once.value()
        } onCancel: {
            Task { await once.offer(.failure(.timedOut)) }
        }
        work.cancel(); timer.cancel()
        return result
    }

    nonisolated func capture<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, ServiceError> {
        await Self.captureError(body)
    }

    static func captureError<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, ServiceError> {
        do { return .success(try await body()) }
        catch let e as ServiceError { return .failure(e) }
        catch { return .failure(.offline) }
    }
}
