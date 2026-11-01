import Foundation
import ActivityKit
import Core

/// Mirrors the current laundry order into one Live Activity. Read only:
/// it never requests anything from U净 and never changes the checkout record.
/// Driven from LaundryModel whenever the order or machine reading changes, and on foreground.
@MainActor final class LaundryActivityController {
    static let shared = LaundryActivityController()
    private typealias State = LaundryActivityAttributes.ContentState
    private var activity: Activity<LaundryActivityAttributes>?
    private init() {
        // Reuse a running activity from a previous launch; drop duplicates.
        let existing = Activity<LaundryActivityAttributes>.activities.filter { $0.activityState == .active }
        activity = existing.first
        for extra in existing.dropFirst() { Task { await Self.endActivity(extra.id, nil, .immediate) } }
    }

    func sync(facts: LaundryFacts, now: Date = Date()) {
        let record = facts.record
        if case .running(let end) = facts.phase(now:now), let record, let id = record.orderId {
            return startOrUpdate(orderId:id, end:end, facts:facts, now:now)
        }
        guard let current = activity else { return }
        // While in flight the live order; once cleared, the engine's last outcome.
        let status = record?.orderID == current.attributes.orderId ? record?.order?.status
            : (record?.lastOutcome?.orderID == current.attributes.orderId ? record?.lastOutcome?.status : nil)
        if let status {
            switch status.code {
            case "50": return done()
            case "51", "52", "53": return endNow()     // timed out / failed to start / cancelled
            default: break                             // 20, or a read still pending: keep as is
            }
        }
        // The order is no longer the one on screen (machine switched, account changed) and the
        // activity has long run out: don't leave it on the lock screen.
        if now > current.content.state.endsAt.addingTimeInterval(3 * 3600) { endNow() }
    }

    private func startOrUpdate(orderId: String, end: Date, facts: LaundryFacts, now: Date) {
        let minutes = max(0, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        if let current = activity, current.attributes.orderId == orderId {
            var state = current.content.state
            state.phase = .running; state.endsAt = end; state.minutesLeft = minutes
            if state.startedAt > end { state.startedAt = end }
            guard state != current.content.state else { return }
            Task { await Self.updateActivity(current.id, ActivityContent(state:state, staleDate:end)) }
            return
        }
        if activity != nil { endNow() }   // a different order: one laundry activity at a time
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let record = facts.record else { return }
        // No start time in the order: derive it from the program length, else the order's creation.
        let length = facts.recordProgram.map { TimeInterval($0.time * 60) }
        let started = length.map { end.addingTimeInterval(-$0) } ?? record.createdAt ?? now
        let attributes = LaundryActivityAttributes(orderId:orderId,
                                                   machine:facts.machine.map(LaundryFormat.machine) ?? "洗衣机",
                                                   program:record.programName)
        let state = State(phase:.running, startedAt:min(started, now), endsAt:end, minutesLeft:minutes)
        activity = try? Activity.request(attributes:attributes,
                                         content:ActivityContent(state:state, staleDate:end),
                                         pushType:nil)
    }

    /// 「衣服洗好了」 / 「3 号机」 / 「去拿衣服吧」, then the system removes it after 5 minutes.
    private func done() {
        guard let current = activity else { return }
        activity = nil
        let now = Date()
        var state = current.content.state
        state.phase = .done; state.minutesLeft = 0; state.endsAt = min(state.endsAt, now)
        if state.startedAt > state.endsAt { state.startedAt = state.endsAt }
        Task { await Self.endActivity(current.id, ActivityContent(state:state, staleDate:now), .after(now.addingTimeInterval(5 * 60))) }
    }

    /// 学校洗衣机 switched off: end any laundry activity at once.
    func endAll() {
        endNow()
        for extra in Activity<LaundryActivityAttributes>.activities where extra.activityState == .active {
            Task { await Self.endActivity(extra.id, nil, .immediate) }
        }
    }

    private func endNow() {
        guard let current = activity else { return }
        activity = nil
        Task { await Self.endActivity(current.id, nil, .immediate) }
    }

    // `Activity` isn't Sendable, so it can't be handed from the main actor to ActivityKit's async
    // calls. Pass its id instead and look it up again off the main actor; the calling task
    // still starts on the main actor, so updates keep their order.
    private nonisolated static func updateActivity(_ id: String, _ content: ActivityContent<State>) async {
        guard let activity = Activity<LaundryActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }

    private nonisolated static func endActivity(_ id: String, _ content: ActivityContent<State>?, _ policy: ActivityUIDismissalPolicy) async {
        guard let activity = Activity<LaundryActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(content, dismissalPolicy:policy)
    }

    #if DEBUG
    /// campusdaily://demo/laundry-activity/start|done|end — fake activity, no U净 data involved.
    static func handleDemo(_ url: URL) -> Bool {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "laundry-activity" else { return false }
        shared.demo(parts.count > 1 ? parts[1] : "start")
        return true
    }
    private func demo(_ action: String) {
        let now = Date()
        switch action {
        case "done":
            if activity == nil { demo("start") }
            done()
        case "end":
            endNow()
        default:
            endNow()
            let end = now.addingTimeInterval(18 * 60)
            let state = State(phase:.running, startedAt:end.addingTimeInterval(-45 * 60), endsAt:end, minutesLeft:18)
            do {
                activity = try Activity.request(attributes:.init(orderId:"demo", machine:"3 号机", program:"标准洗"),
                                                content:ActivityContent(state:state, staleDate:end),
                                                pushType:nil)
                NSLog("LaundryActivityDemo started %@", activity?.id ?? "-")
            } catch { NSLog("LaundryActivityDemo failed %@", String(describing:error)) }
        }
    }
    #endif
}

#if DEBUG
import SwiftUI

/// campusdaily://demo/laundry-activity/preview[-done] — draws the Live Activity views in the app,
/// because the simulator can't host Live Activities (ActivityKit fails to connect). Same view code
/// as the widget; the island shapes and lock-screen backdrop are approximations.
struct LaundryActivityPreview: View {
    enum Kind: String, Identifiable { case running = "preview", done = "preview-done"; var id: String { rawValue } }
    static func handle(_ url: URL) -> Kind? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "laundry-activity", parts.count > 1 else { return nil }
        return Kind(rawValue:parts[1])
    }
    let kind: Kind
    private let attributes = LaundryActivityAttributes(orderId:"demo", machine:"3 号机", program:"标准洗")
    private var state: LaundryActivityAttributes.ContentState {
        let end = Date().addingTimeInterval(18 * 60)
        return .init(phase:kind == .done ? .done : .running, startedAt:end.addingTimeInterval(-45 * 60),
                     endsAt:end, minutesLeft:kind == .done ? 0 : 18)
    }
    var body: some View {
        VStack(spacing:14) {
            // Compact island
            HStack {
                Image(systemName:LaundryActivityStyle.glyph).foregroundStyle(LaundryActivityStyle.accent)
                Spacer()
                LaundryIslandCompactTrailing(state:state)
            }
            .padding(.horizontal,16).frame(width:250, height:37).background(.black, in:Capsule())
            caption("灵动岛收起")
            // Expanded island
            VStack(spacing:6) {
                HStack { LaundryIslandLeading(attributes:attributes, state:state); Spacer(); LaundryIslandTrailing(attributes:attributes, state:state) }
                LaundryIslandBottom(state:state)
            }
            .padding(.horizontal,20).padding(.vertical,16)
            .background(.black, in:RoundedRectangle(cornerRadius:44, style:.continuous))
            .padding(.horizontal,8)
            caption("灵动岛展开")
            // Lock screen
            LaundryActivityLockView(attributes:attributes, state:state)
                .background(LaundryActivityStyle.background, in:RoundedRectangle(cornerRadius:24, style:.continuous))
                .padding(.horizontal,10)
            caption("锁屏")
            Spacer()
        }
        .padding(.top,70)
        .frame(maxWidth:.infinity, maxHeight:.infinity)
        .background(Color(red:0.68, green:0.75, blue:0.80).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size:12)).foregroundStyle(.white.opacity(0.8))
    }
}
#endif
