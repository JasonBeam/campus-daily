import Foundation
import Core

/// The shower page's taps, run through `ShowerPageFlow` (Core) and turned into the same engine
/// calls as before: start, cancel before the authorize request, end, clear a finished record.
extension ShowerModel {
    func pageEvent(_ event: ShowerPageEvent) {
        let (next, effects) = ShowerPageFlow.reduce(page, event)
        let passed = next.checkPassed > page.checkPassed
        if next != page { page = next }
        if passed { showCheckPassed() }
        for effect in effects { perform(effect) }
    }

    /// A page event from a screen other than home (the 核对 screen), then the page brought up
    /// the way home's own buttons do.
    func pageEventShowingPage(_ events: ShowerPageEvent...) {
        for event in events { pageEvent(event) }
        pageWanted += 1
    }

    private func perform(_ effect: ShowerPageEffect) {
        switch effect {
        case .start:
            // The slot's start, once. An effect with no start behind it (a tap that did not go
            // through `tapStart`) runs nothing: the page goes back as it was.
            guard let intent = takeLaunch(.start) else {
                Task { pageEvent(.startReturned) }
                return
            }
            startTaskID = intent.id
            startTask = Task {
                _ = try? await run(intent, start:true)  // the page shows the record itself
                startEnded(intent.id, returned:.startReturned)
            }
        case .cancelStart:
            Task {
                guard let engine, await engine.cancelStart() else { pageEvent(.cancelRefused); return }
                // The authorize request can no longer leave; end the Bluetooth connect now.
                startTask?.cancel()
            }
        case .finish:
            Task {
                _ = try? await run(start:false)
                pageEvent(.endReturned)
            }
        case .dismissRecord:
            let record = page.record
            Task {
                // A cancelled start may still be winding down. Only this record is cleared: the
                // wait can outlast the next start, whose record stays.
                await untilIdle()
                await dismiss(only:record)
            }
        case .startNext:
            guard let intent = takeLaunch(.next) else {
                Task { pageEvent(.startNextReturned(failed:false)) }
                return
            }
            startTaskID = intent.id
            startTask = Task {
                let went = await startNext(intent)
                startEnded(intent.id, returned:.startNextReturned(failed:!went))
            }
        case .recheck:
            Task {
                let result = await recheckSession()
                pageEvent(.recheckReturned(result))
                // Water runs again: the timer comes up wherever the probe was tapped.
                if result == nil, page.presented { pageWanted += 1 }
            }
        case .disarmSettleRetry:
            Task {
                // Taken back once whatever runs now is done.
                await untilIdle()
                await disarmSettleRetry()
            }
        }
    }

    /// 「找到了，是你宿舍的水控。」 for a moment over the page that came up.
    private func showCheckPassed() {
        checkToastShown = true
        let shown = page.checkPassed
        Task {
            try? await Task.sleep(for:.seconds(FirstCheckText.passedSeconds))
            if page.checkPassed == shown { checkToastShown = false }
        }
    }

    #if DEBUG
    /// Demo: the page over a synthetic record, no engine involved.
    func showDemoPage(_ record: ShowerState?) {
        page = ShowerPageFlow(record:record ?? .idle, presented:record != nil)
    }
    #endif
}
