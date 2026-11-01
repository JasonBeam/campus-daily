import Foundation

/// Settings › 高级 › 重置校日常: everything this app stored, back to a fresh install.
/// Clears every Keychain item (school login and saved password, the card session's and portal
/// token's obtained/alive times stored with them, login device id, dorm and meter, hot-water
/// binding and remembered controller, shower record, U净 login and device, laundry record,
/// widget snapshot and reminder lines, the app/widget refresh lease), every preference the app set, and the files
/// the app wrote (imported hot-water file, records, diagnostics). The hot-water parameters
/// bundled with the app are read-only resources and stay.
public enum AppReset {
    /// Why reset is not offered right now.
    public enum Lock: Sendable, Equatable {
        /// Water may be flowing or a step of the shower is still running.
        case showering
        /// A settlement is waiting to be checked against the school's records.
        case unsettled
        /// A laundry order is not finished (being created, paid, running or needing attention).
        case laundry
        /// The shower or laundry record can't be read, so nobody can tell whether a charge is open.
        case recordsUnreadable
        /// A hot-water controller check is talking to the controller.
        case checkingController
    }

    /// Reset waits for the shower to end and its settlement to be checked, and for any laundry
    /// order to finish: clearing in between would lose the only record of a charge.
    /// An unreadable record locks first: what it holds is unknown. A controller check in
    /// progress locks too (it writes the binding when it ends).
    public static func lock(shower: ShowerState?, laundry: LaundryPhase? = nil, laundryBusy: Bool = false,
                            recordsUnreadable: Bool = false, checkingController: Bool = false) -> Lock? {
        if recordsUnreadable { return .recordsUnreadable }
        if let s = shower {
            if s.phase == .failed, s.failure?.needsReview == true { return .unsettled }
            if s.stateReviewRequired { return .unsettled }
            if !s.canStart { return .showering }
        }
        if laundryBusy || (laundry ?? LaundryPhase.none) != LaundryPhase.none { return .laundry }
        if checkingController { return .checkingController }
        return nil
    }

    /// What stopped a reset, and whether the school sign-out had already run: a lock found on
    /// the second check, after the sign-out, leaves the user signed out (and the saved password
    /// deleted) with everything else still there.
    public struct Stop: Sendable, Equatable {
        public var lock: Lock
        public var signedOut: Bool
        public init(_ lock: Lock, signedOut: Bool) {
            self.lock = lock
            self.signedOut = signedOut
        }
    }

    /// A reset stopped after the sign-out changed only the school side. What the shower's lock
    /// screen and reminders do then: they follow its record, so water that may be running keeps
    /// 结束并结算 and 「还没结束洗澡？」; laundry reminders and Live Activities are not touched.
    public struct Resync: Sendable, Equatable {
        /// 「还没结束洗澡？」 is (re)scheduled from this start; nil removes it.
        public var showerReminderStart: Date?
        /// What the shower Live Activity does: the same as for any record change.
        public var showerActivity: ShowerActivityAction
        /// Laundry reminders and its Live Activity are left as they are.
        public let leavesLaundry = true

        public init(shower: ShowerState, now: Date) {
            showerReminderStart = shower.mayBeFlowing ? shower.startedAt : nil
            showerActivity = ShowerActivityAction(shower, now: now)
        }
    }

    /// A shower or laundry start refused while a reset runs (what Shortcuts shows, too).
    public struct InProgress: LocalizedError, Sendable, Equatable {
        public init() {}
        public var errorDescription: String? { "正在重置" }
    }

    /// All or nothing. The marker goes first, so from then on nothing can start; then one check of
    /// the locks. A lock removes the marker and returns, with nothing signed out or cleared.
    /// Otherwise: school sign-out (local deletes happen whatever it meets), clear, reload. The
    /// marker goes with the clear. A clear that fails removes the marker too and throws: the
    /// user is told the reset did not finish and tries again, and nothing clears later on its
    /// own. Only a reset killed mid-way leaves the marker, for the next launch to finish within
    /// `ResetMarker.staleAfter` (`resume`). Returns the lock that stopped it, or nil when the
    /// stores were cleared (`Stop.signedOut` says whether the sign-out had run). A marker that can't be written stops it before anything happens
    /// (thrown).
    ///
    /// The sign-out can outlast the marker (the app suspended for minutes in the middle of it),
    /// and a shower or an order may have started once it went stale. So before the clear the
    /// marker is written again at `clock()` and the locks are checked once more; a lock then
    /// stops the reset with the sign-out done and nothing else cleared.
    ///
    /// `reload` follows a clear (it may end every Live Activity and reminder: nothing is left
    /// for them). A stop after the sign-out runs `resync` instead: the shower may be running, so
    /// its Live Activity and reminder are put back in step with the record, not removed.
    @MainActor public static func run(marker: ResetMarker, now: Date, clock: () -> Date = Date.init, lock: () -> Lock?,
                                      signOut: () async -> Void, clear: () throws -> Void,
                                      reload: () async -> Void, resync: () async -> Void = {}) async throws -> Stop? {
        try marker.begin(at: now)
        if let found = lock() {
            try? marker.end()
            return Stop(found, signedOut: false)
        }
        await signOut()
        do { try marker.begin(at: clock()) } catch {
            // Without a fresh marker a start could slip in during the clear: stop here.
            try? marker.end()
            await resync()
            throw error
        }
        if let found = lock() {
            try? marker.end()
            await resync()
            return Stop(found, signedOut: true)
        }
        var failure: Error?
        do { try clear() } catch {
            failure = error
            // Already reporting the failure; a marker that can't be deleted either goes stale and
            // is then dropped by `resume` without clearing anything.
            try? marker.end()
        }
        await reload()
        if let failure { throw failure }
        return nil
    }

    public enum Resumed: Sendable, Equatable {
        case completed
        case stopped(Stop)
        /// A stale marker was dropped and nothing cleared: the reset was left half done (signed
        /// out, perhaps, with hot water and laundry still there). The user is told once.
        case abandoned
    }

    /// At launch: a marker left by a reset the app was killed in. Only a fresh one (younger than
    /// `ResetMarker.staleAfter`) is finished, with the same steps as `run`, the lock check
    /// included: stopped, the marker goes and nothing is cleared. An older one is deleted and
    /// nothing is cleared: by then the user may have signed in and set things up again; that
    /// is `abandoned`, so the user learns the reset never finished. Nil when there is no marker.
    @MainActor public static func resume(marker: ResetMarker, now: Date, clock: () -> Date = Date.init, lock: () -> Lock?,
                                         signOut: () async -> Void, clear: () throws -> Void,
                                         reload: () async -> Void, resync: () async -> Void = {}) async throws -> Resumed? {
        guard marker.startedAt() != nil else { return nil }
        guard marker.refusesStarts(at: now) else {
            // One that can't be deleted is stale again next launch, and dropped (and told) again.
            try? marker.end()
            return .abandoned
        }
        let stopped = try await run(marker: marker, now: now, clock: clock, lock: lock, signOut: signOut, clear: clear, reload: reload,
                                  resync: resync)
        return stopped.map(Resumed.stopped) ?? .completed
    }

    /// The locks as stored, for when the models may not have loaded yet (at launch): the shower
    /// record and the laundry record, an unreadable one locking as `recordsUnreadable`.
    public static func storedLock(store: SecureStore) -> Lock? {
        let shower: ShowerState, laundry: LaundryCheckout
        do {
            shower = ShowerReducer.restore(try StoredShowerVault(store: store).showerState())
            laundry = LaundryReducer.restore(try StoredLaundryVault(store: store).checkout())
        } catch { return .recordsUnreadable }
        return lock(shower: shower, laundry: laundry.phase)
    }

    /// Every Keychain item. A new `StoreKey` is cleared without being listed here. The reset
    /// marker is the last, and only when everything before it went.
    public static var keychainItems: [StoreKey] { StoreKey.allCases.filter { $0 != .sharedResetMarker } + [.sharedResetMarker] }

    public struct Failure: LocalizedError, Sendable, Equatable {
        /// Item or file names only (never values).
        public var items: [String]
        public var errorDescription: String? { "重置没做完，有些东西没清掉。再试一次。" }
    }

    /// Deletes everything; keeps going after a failure and reports what could not be deleted.
    /// The reset marker is deleted last, only when everything else went (`run` removes it after
    /// a failure).
    /// `preferencesDomain` is the app's own preferences domain (its bundle id; a suite name in
    /// tests): the whole domain goes, so a preference added later, `xrc.`-named or not, is
    /// cleared without being listed.
    public static func clear(store: SecureStore, preferences: UserDefaults, preferencesDomain: String, files: [URL],
                             fileManager: FileManager = .default) throws {
        var failed: [String] = []
        for key in keychainItems where key != .sharedResetMarker {
            do { try store.delete(key) } catch { failed.append(key.rawValue) }
        }
        preferences.removePersistentDomain(forName: preferencesDomain)
        for url in files where fileManager.fileExists(atPath: url.path) {
            do { try fileManager.removeItem(at: url) } catch { failed.append(url.lastPathComponent) }
        }
        if !failed.isEmpty { throw Failure(items: failed) }
        do { try store.delete(.sharedResetMarker) } catch { throw Failure(items: [StoreKey.sharedResetMarker.rawValue]) }
    }
}
