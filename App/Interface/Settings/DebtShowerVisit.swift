import Foundation
import Core

/// This process's switch-off of the debt start setting that the Keychain didn't store (the item
/// still says on, so a relaunch could read it back). Shared by both themes' pages, so leaving
/// the page or switching theme keeps the line and its retry. Cleared only by a stored retry or
/// by turning the setting back on.
@MainActor @Observable
final class DebtShowerPending {
    static let shared = DebtShowerPending()
    /// A switch-off is waiting to be stored.
    private(set) var unstored = false

    /// The switch or the retry turning it off: `setAllowsDebt(false)`, remembering whether it was stored.
    func turnOff(_ shower: ShowerModel) {
        var stored = shower.setAllowsDebt(false)
        #if DEBUG
        if DebtShowerVisit.demoTurnOffUnstored { stored = false }
        #endif
        unstored = !stored
    }

    /// The setting is on again (the phrase or the switch): nothing left to store.
    func turnedOn() { unstored = false }
}

/// One visit of the page that holds the debt start setting (暖橙's 高级, 清爽's 设置): five taps
/// on the version open the alert; the group shows while the setting is on or a switch-off is
/// waiting to be stored, and, once switched off, until the page is left.
struct DebtShowerVisit {
    private var streak = TapStreak(count:5, gap:.seconds(1))
    /// The group is on the page.
    private(set) var rowShown = false
    /// The alert is up.
    var asking = false
    /// What is typed in the alert; empty each time it opens.
    var typed = ""
    /// Counts the right phrases (the success haptic's trigger).
    private(set) var unlocked = 0

    /// The page appeared: the group as the setting is now, or while a switch-off waits to be stored.
    mutating func appeared(on: Bool, pending: Bool) {
        rowShown = on || pending; streak.reset()
    }

    /// The group is on the page (`pending`: `DebtShowerPending.unstored`).
    func shows(pending: Bool) -> Bool { rowShown || pending }

    /// A tap on the version. Nothing in the sample or while the setting is on.
    mutating func tapVersion(at date: Date, sample: Bool, on: Bool) {
        guard !sample, !on else { streak.reset(); return }
        guard streak.register(at:date) else { return }
        typed = ""
        asking = true
    }

    /// The setting changed (the phrase, the switch, a reset): turned on, the group shows.
    mutating func changed(on: Bool) {
        guard on else { return }
        rowShown = true
    }

    /// The alert's 确定: `on` is the setting after the phrase was tried.
    mutating func confirmed(on: Bool) {
        typed = ""
        if on { unlocked += 1; changed(on:true) }
    }
}
