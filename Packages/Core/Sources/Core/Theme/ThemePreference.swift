//
//  ThemePreference.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import Foundation

/// The chosen theme, kept in the App Group's preferences so the widget and the Live Activities
/// draw with it too. Only the app writes it, compared and written in one step inside the shared
/// lock (`set(_:under:)`); the extensions only read. Nothing stored, or a value this build
/// doesn't know: 暖橙.
public struct ThemePreference {
    public static let key = PreferenceKey.theme
    private let storage: any PreferenceStorage

    public init(storage: any PreferenceStorage) { self.storage = storage }

    public var theme: AppTheme { AppTheme(stored: storage.object(forKey: Self.key) as? String) }

    /// Stores `theme` unless it is already stored, inside `lock`. A lock that can't be taken
    /// throws and nothing is written.
    public func set(_ theme: AppTheme, under lock: any SharedLock) throws {
        try lock.locked { store(theme) }
    }

    /// The compare and write `set` runs inside the lock.
    private func store(_ theme: AppTheme) {
        guard storage.object(forKey: Self.key) as? String != theme.rawValue else { return }
        storage.set(theme.rawValue, forKey: Self.key)
    }

    /// 主题's choice over `current` (the theme shown): nothing while `lock` says a shower or laundry
    /// run is going on, whoever asks, and nothing when it is already shown; otherwise stored as
    /// `set(_:under:)`. True when the theme changed.
    public func select(_ theme: AppTheme, current: AppTheme, lock themeLock: ThemeLock?,
                       under lock: any SharedLock) throws -> Bool {
        guard theme != current, themeLock == nil else { return false }
        try set(theme, under: lock)
        return true
    }

    /// `select` that never waits for `lock` (the main thread): taken right now, it throws at
    /// once (`SharedLock.lockedIfFree`) and nothing is written.
    public func selectIfFree(_ theme: AppTheme, current: AppTheme, lock themeLock: ThemeLock?,
                             under lock: any SharedLock) throws -> Bool {
        guard theme != current, themeLock == nil else { return false }
        try lock.lockedIfFree { store(theme) }
        return true
    }

    /// `select` for async callers: the wait for `lock` suspends (`SharedLock.lockedWhenFree`)
    /// and holds no thread, so it may run on the main actor.
    public func selectWhenFree(_ theme: AppTheme, current: AppTheme, lock themeLock: ThemeLock?, under lock: any SharedLock,
                               isolation: isolated (any Actor)? = #isolation) async throws -> Bool {
        guard theme != current, themeLock == nil else { return false }
        try await lock.lockedWhenFree(isolation: isolation) { store(theme) }
        return true
    }

    /// The preferences the app and its extensions share: the App Group's, or this process's own
    /// when it has no group (tests, an install re-signed without one).
    public static func sharedStorage(appGroup: String? = AppIdentity.usableAppGroup) -> any PreferenceStorage {
        appGroup.flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.standard
    }

    /// The theme the app last chose, as the widget and Live Activities read it when they draw.
    public static func shared() -> AppTheme { ThemePreference(storage: sharedStorage()).theme }
}
