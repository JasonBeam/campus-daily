//
//  ThemeStore.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI
import Observation
import Core

/// The theme the app draws with. Each model graph owns one (`CampusGraph`) and injects it into
/// the environment; `CampusRootView` hands its theme down as `\.appTheme`, which the tokens resolve
/// from. Observable: the pages are drawn again when the theme changes, so a switch shows at once,
/// without a restart. Written on the main actor only (`select`, `reload`). Stored in the
/// preferences it is given: the App Group's for the live app (where the widget and the Live
/// Activities read it), the sample's own in-memory ones in 「先看看示例」.
@Observable final class ThemeStore: @unchecked Sendable {
    /// What is stored, the theme shown.
    private(set) var stored: AppTheme
    @ObservationIgnored private let preference: ThemePreference
    /// The App Group's lock, which the widget and Live Activities' processes respect.
    @ObservationIgnored private let lock: any SharedLock
    /// Why the theme can't change now (a shower or laundry run going on); nil when it can.
    @ObservationIgnored private let themeLock: @MainActor () -> ThemeLock?
    /// The choice was stored: the widget draws again (nothing for a sample's).
    @ObservationIgnored private let didChange: @Sendable () -> Void
    /// A choice waiting for the shared lock (`select`); a newer choice cancels it.
    @ObservationIgnored private var pending: Task<Void, Never>?

    @MainActor init(preference: ThemePreference, lock: any SharedLock, didChange: @escaping @Sendable () -> Void,
                    themeLock: @escaping @MainActor () -> ThemeLock?) {
        self.preference = preference
        self.lock = lock
        self.didChange = didChange
        self.themeLock = themeLock
        stored = preference.theme
    }

    @MainActor var theme: AppTheme { stored }

    /// Saves the choice where the widget and the Live Activities read it, and has the widget
    /// draw again. Nothing changes while a run locks the theme (`ThemeLock`, whoever asks; 主题
    /// greys its options out too), or when the shared lock can't be taken (the container locked
    /// before the first unlock): the option stays unselected. The main thread never waits for
    /// the shared lock: taken right now (the widget's step, or one stuck there), the choice is
    /// tried again by a task whose wait suspends (`selectWhenFree`), until stored, and shows
    /// once stored.
    @MainActor func select(_ theme: AppTheme) {
        pending?.cancel()
        pending = nil
        do {
            guard try preference.selectIfFree(theme, current:stored, lock:themeLock(), under:lock) else { return }
        } catch {
            pending = Task { @MainActor [weak self] in await self?.selectWhenFree(theme) }
            return
        }
        show(theme)
    }

    /// How long a choice waiting for the shared lock pauses between its waits.
    static let retryPause: Duration = .milliseconds(500)

    /// The choice `select` could not store at once, tried until stored: a lock still held after
    /// a wait (the widget stuck in a step) is waited for again after `retryPause`, the run lock
    /// (`ThemeLock`) checked again each time. A newer choice cancels it before it writes.
    @MainActor private func selectWhenFree(_ theme: AppTheme) async {
        while !Task.isCancelled {
            do {
                guard try await preference.selectWhenFree(theme, current:stored, lock:themeLock(), under:lock) else { return }
                show(theme)
                return
            } catch is CancellationError {
                return
            } catch {
                guard (try? await Task.sleep(for:Self.retryPause)) != nil else { return }
            }
        }
    }

    /// Waits for a choice still trying for the shared lock (tests).
    @MainActor func settled() async { await pending?.value }

    @MainActor private func show(_ theme: AppTheme) {
        stored = theme
        didChange()
    }

    /// After 重置校日常 cleared the stored choice: back to what is stored (暖橙).
    @MainActor func reload() {
        let value = preference.theme
        if value != stored { stored = value }
    }
}
