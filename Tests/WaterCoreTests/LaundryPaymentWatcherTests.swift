import XCTest
@testable import WaterCore

@MainActor private final class PaymentRuntimeFixture: LaundryPaymentRuntime {
    var grants = true
    var expireImmediately = false
    var active = false
    var begins = 0
    var ends = 0
    var maximum: TimeInterval?
    var expiration: (@MainActor @Sendable () -> Void)?
    func begin(maximumDuration: TimeInterval, expiration: @escaping @MainActor @Sendable () -> Void) -> Bool {
        begins += 1; maximum = maximumDuration
        guard grants else { return false }
        active = true; self.expiration = expiration
        if expireImmediately { expiration() }
        return true
    }
    func end() { if active { ends += 1 }; active = false; expiration = nil }
    func expire() { expiration?() }
}

@MainActor final class LaundryPaymentWatcherTests: XCTestCase {
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 { if condition() { return }; await Task.yield() }
    }
    func testNoLeaseOrQueriesWhenOrderIsNotEligible() async {
        let runtime = PaymentRuntimeFixture(); let watcher = LaundryPaymentWatcher(runtime:runtime)
        var reads = 0
        XCTAssertFalse(watcher.start(shouldContinue:{false},refresh:{reads += 1}))
        await Task.yield()
        XCTAssertEqual(runtime.begins,0); XCTAssertEqual(reads,0); XCTAssertFalse(watcher.isRunning)
    }
    func testDeniedOrImmediatelyExpiredLeaseNeverQueries() async {
        for denied in [true,false] {
            let runtime = PaymentRuntimeFixture(); runtime.grants = !denied; runtime.expireImmediately = !denied
            let watcher = LaundryPaymentWatcher(runtime:runtime); var reads = 0
            XCTAssertFalse(watcher.start(shouldContinue:{true},refresh:{reads += 1}))
            await Task.yield()
            XCTAssertEqual(reads,0); XCTAssertFalse(watcher.isRunning); XCTAssertFalse(runtime.active)
        }
    }
    func testStopsAndReleasesLeaseAsSoonAsOrderRuns() async {
        let runtime = PaymentRuntimeFixture(); let watcher = LaundryPaymentWatcher(runtime:runtime)
        var pending = true; var reads = 0
        XCTAssertTrue(watcher.start(shouldContinue:{pending},refresh:{reads += 1;pending = false}))
        await settle { !watcher.isRunning }
        XCTAssertEqual(reads,1); XCTAssertEqual(runtime.ends,1); XCTAssertEqual(runtime.maximum,45)
        XCTAssertFalse(watcher.isRunning); watcher.stop(); XCTAssertEqual(runtime.ends,1)
    }
    func testExpirationCancelsInFlightReadAndNeverRenewsLease() async {
        let runtime = PaymentRuntimeFixture(); let watcher = LaundryPaymentWatcher(runtime:runtime)
        var entered = false; var cancelled = false
        watcher.start(shouldContinue:{true},refresh:{
            entered = true
            do { try await Task.sleep(for:.seconds(60)) } catch { cancelled = Task.isCancelled }
        })
        await settle { entered }; runtime.expire()
        await settle { cancelled }
        XCTAssertTrue(cancelled); XCTAssertFalse(watcher.isRunning)
        XCTAssertEqual(runtime.begins,1); XCTAssertEqual(runtime.ends,1)
    }
    func testOldCompletionCannotEndReplacementWindow() async {
        let runtime = PaymentRuntimeFixture(); let watcher = LaundryPaymentWatcher(runtime:runtime)
        var entered = false
        watcher.start(shouldContinue:{true},refresh:{
            entered = true
            try? await Task.sleep(for:.seconds(60))
        })
        await settle { entered }
        let oldExpiration = runtime.expiration
        var newEntered = false
        watcher.start(shouldContinue:{true},refresh:{newEntered = true;try? await Task.sleep(for:.seconds(60))})
        await settle { newEntered }
        oldExpiration?()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(watcher.isRunning); XCTAssertTrue(runtime.active); XCTAssertEqual(runtime.ends,1)
        watcher.stop(); XCTAssertEqual(runtime.ends,2)
    }
}
