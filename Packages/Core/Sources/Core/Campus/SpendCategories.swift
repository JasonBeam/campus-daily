//
//  SpendCategories.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation

/// The categories the records page's stats can count (`CardRecordKind` without top-ups), and
/// which of them count unless the user changed it: all but 电费, which a dorm pays now and then
/// for everyone in it and which would swamp a person's own spending.
public enum SpendCategories {
    public static let all: [CardRecordKind] = CardRecordKind.allCases.filter { $0 != .topUp }
    public static let defaultIncluded: Set<CardRecordKind> = Set(all).subtracting([.electricity])
}

/// The categories the user counts in the stats, kept in the app's preferences as the raw values
/// of the ones left out, so a category added later counts until it is turned off.
public struct SpendCategoryStore {
    public static let key = "records.statsCategories"
    private let preferences: any PreferenceStorage

    public init(preferences: any PreferenceStorage) { self.preferences = preferences }

    /// The categories counted: `SpendCategories.defaultIncluded` when none were kept, or when
    /// what is kept is unreadable or would leave nothing counted.
    public var included: Set<CardRecordKind> {
        guard let raw = preferences.object(forKey: Self.key) as? [String] else { return SpendCategories.defaultIncluded }
        let excluded = Set(raw.compactMap(CardRecordKind.init(rawValue:)))
        let included = Set(SpendCategories.all).subtracting(excluded)
        return included.isEmpty ? SpendCategories.defaultIncluded : included
    }

    public func set(_ included: Set<CardRecordKind>) {
        let excluded = SpendCategories.all.filter { !included.contains($0) }.map(\.rawValue)
        preferences.set(excluded, forKey: Self.key)
    }

    public func clear() { preferences.set(nil, forKey: Self.key) }
}
