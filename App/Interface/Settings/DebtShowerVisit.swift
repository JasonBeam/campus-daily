import Foundation
import Core

/// One visit of the page that holds the debt start setting (暖橙's 高级, 清爽's 设置): five taps
/// on the version open the alert; the group shows while the setting is on and, once switched
/// off, until the page is left.
struct DebtShowerVisit {
    private var streak = TapStreak(count:5, gap:.seconds(1))
    /// The group is on the page.
    private(set) var rowShown = false
    /// The last turn-off was not stored: the footer says so, with a retry.
    private(set) var unstored = false
    /// The alert is up.
    var asking = false
    /// What is typed in the alert; empty each time it opens.
    var typed = ""
    /// Counts the right phrases (the success haptic's trigger).
    private(set) var unlocked = 0

    /// The page appeared: the group as the setting is now.
    mutating func appeared(on: Bool) {
        rowShown = on; unstored = false; streak.reset()
    }

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
        rowShown = true; unstored = false
    }

    /// The alert's 确定: `on` is the setting after the phrase was tried.
    mutating func confirmed(on: Bool) {
        typed = ""
        if on { unlocked += 1; changed(on:true) }
    }

    /// The switch (or the retry) turned it off; `stored`: what `setAllowsDebt(false)` returned.
    mutating func turnedOff(stored: Bool) {
        unstored = !stored
    }
}
