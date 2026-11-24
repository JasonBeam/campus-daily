//
//  FeedbackSending.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Foundation
import Core

/// The feedback form's send: 正在发送…, the slow line once it has taken `FeedbackText.slowAfter`,
/// then 发出去了 or the failure line. `cancel()` (取消 while sending) stops the request and shows
/// neither. A send still going `deadlineMargin` after its whole limit (`FeedbackSender.Limits.total`)
/// is stopped and shown as failed by a timer on the main queue, which needs no thread from Swift
/// concurrency's pool: a pool held up elsewhere can't leave the form on 正在发送….
@MainActor final class FeedbackSending: ObservableObject {
    @Published private(set) var sending = false
    /// The send has taken longer than `FeedbackText.slowAfter` and is still going.
    @Published private(set) var slow = false
    @Published private(set) var failure: String?
    @Published var sent = false

    /// How long past the send's own limit the main-queue deadline waits.
    static let deadlineMargin: TimeInterval = 2

    /// When the main-queue deadline fires: the send's whole limit plus `deadlineMargin`.
    static func deadline(withScreenshots: Bool) -> TimeInterval {
        FeedbackSender.limits(imageCount:withScreenshots ? 1 : 0).total + deadlineMargin
    }

    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var run: (id: UUID, send: Task<Void, Never>, timer: Task<Void, Never>, deadline: DispatchWorkItem)?

    /// `schedule` runs the deadline on the main queue after the given seconds; tests run it themselves.
    init(sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for:.seconds($0)) },
         schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { DispatchQueue.main.asyncAfter(deadline:.now() + $0, execute:$1) }) {
        self.sleep = sleep
        self.schedule = schedule
    }

    /// `withScreenshots` and `clear` pick the failure line.
    func start(withScreenshots: Bool, clear: Bool, _ send: @escaping @MainActor @Sendable () async throws -> Void) {
        guard run == nil else { return }
        let id = UUID()
        sending = true
        slow = false
        failure = nil
        let sleep = sleep
        let timer = Task { [weak self] in
            do { try await sleep(FeedbackText.slowAfter) } catch { return }
            guard let self, self.run?.id == id else { return }
            self.slow = true
        }
        let task = Task { [weak self] in
            let outcome: Result<Void, Error>
            do { try await send(); outcome = .success(()) } catch { outcome = .failure(error) }
            guard let self, self.run?.id == id else { return }
            self.end()
            switch outcome {
            case .success: self.sent = true
            case .failure(let error) where error is CancellationError: break
            case .failure: self.failure = FeedbackText.failure(withScreenshots:withScreenshots, clear:clear)
            }
        }
        let deadline = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let run = self.run, run.id == id else { return }
                run.send.cancel()
                self.end()
                self.failure = FeedbackText.failure(withScreenshots:withScreenshots, clear:clear)
            }
        }
        run = (id, task, timer, deadline)
        schedule(Self.deadline(withScreenshots:withScreenshots), deadline)
    }

    /// Stops the send in progress, request included. Nothing is said about it.
    func cancel() {
        run?.send.cancel()
        end()
    }

    private func end() {
        run?.timer.cancel()
        run?.deadline.cancel()
        run = nil
        sending = false
        slow = false
    }
}
