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
/// neither.
@MainActor final class FeedbackSending: ObservableObject {
    @Published private(set) var sending = false
    /// The send has taken longer than `FeedbackText.slowAfter` and is still going.
    @Published private(set) var slow = false
    @Published private(set) var failure: String?
    @Published var sent = false

    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var run: (id: UUID, send: Task<Void, Never>, timer: Task<Void, Never>)?

    init(sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for:.seconds($0)) }) {
        self.sleep = sleep
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
        run = (id, task, timer)
    }

    /// Stops the send in progress, request included. Nothing is said about it.
    func cancel() {
        run?.send.cancel()
        end()
    }

    private func end() {
        run?.timer.cancel()
        run = nil
        sending = false
        slow = false
    }
}
