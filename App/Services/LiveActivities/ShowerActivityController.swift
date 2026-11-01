import Foundation
import ActivityKit
import Core

/// Mirrors `ShowerState` into a single Live Activity.
/// Driven from ShowerModel (engine updates); never talks to the water controller itself.
@MainActor final class ShowerActivityController {
    static let shared = ShowerActivityController()
    /// Short dorm label shown on the activity; set by the app from CampusModel.room.
    var dorm = ""
    private var activity: Activity<ShowerActivityAttributes>?
    private init() {
        // Reuse an activity left over from a previous launch; drop any duplicates.
        let existing = Activity<ShowerActivityAttributes>.activities.filter { $0.activityState == .active }
        activity = existing.first
        for extra in existing.dropFirst() { Task { await Self.endActivity(extra.id, nil, .immediate) } }
    }

    private var label: String {
        let value = dorm.trimmingCharacters(in:.whitespaces)
        return value.isEmpty || value == "未配置" ? "宿舍" : value
    }

    /// Called right before finish is sent to the water controller.
    func settling() {
        guard let activity else { return }
        var state = activity.content.state
        state.phase = .settling
        Task { await Self.updateActivity(activity.id, ActivityContent(state:state, staleDate:nil)) }
    }

    /// Reconcile with the engine's current state.
    func sync(state: ShowerState) { apply(ShowerActivityAction(state, now:Date())) }

    /// Carries out what Core decided for the record (`ShowerActivityAction`).
    func apply(_ action: ShowerActivityAction) {
        switch action {
        case .end:
            // Dismissed, or closed by hand after checking the official record: nothing to show.
            endNow()
        case .leave:
            break
        case .show(let started, let writeUnconfirmed):
            // Write-pending shows as 洗澡中 too (water may be running), with the unconfirmed line.
            startOrResume(started, writeUnconfirmed:writeUnconfirmed)
        case .settling(let started):
            guard var next = activity?.content.state else { return }
            next.startedAt = started; next.phase = .settling
            if let activity, activity.content.state != next {
                Task { await Self.updateActivity(activity.id, ActivityContent(state:next, staleDate:nil)) }
            }
        case .settled(let started, let minutes, let amount, let after):
            guard activity != nil else { return endNow() }
            end(.init(startedAt:started, phase:.settled, durationMinutes:minutes, amountYuan:amount),
                after:Date().addingTimeInterval(after))
        case .unconfirmed(let started, let after):
            end(.init(startedAt:started, phase:.unconfirmed), after:Date().addingTimeInterval(after))
        }
    }

    private func startOrResume(_ startedAt: Date, writeUnconfirmed: Bool = false) {
        let state = ShowerActivityAttributes.ContentState(startedAt:startedAt, phase:.active,
                                                          writeUnconfirmed:writeUnconfirmed ? true : nil)
        if let activity {
            // E.g. a failed finish that left the session active: show the button again.
            guard activity.content.state != state else { return }
            Task { await Self.updateActivity(activity.id, ActivityContent(state:state, staleDate:nil)) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes:ShowerActivityAttributes(dorm:label),
                                         content:ActivityContent(state:state, staleDate:nil), pushType:nil)
    }

    private func end(_ state: ShowerActivityAttributes.ContentState, after date: Date) {
        guard let current = activity else { return }
        activity = nil
        Task { await Self.endActivity(current.id, ActivityContent(state:state, staleDate:nil), .after(date)) }
    }

    /// Reset: end every hot-water activity at once, including any this controller lost track of.
    func endAll() {
        endNow()
        for extra in Activity<ShowerActivityAttributes>.activities where extra.activityState == .active {
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
    private typealias State = ShowerActivityAttributes.ContentState
    private nonisolated static func updateActivity(_ id: String, _ content: ActivityContent<State>) async {
        guard let activity = Activity<ShowerActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }

    private nonisolated static func endActivity(_ id: String, _ content: ActivityContent<State>?, _ policy: ActivityUIDismissalPolicy) async {
        guard let activity = Activity<ShowerActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(content, dismissalPolicy:policy)
    }
}
