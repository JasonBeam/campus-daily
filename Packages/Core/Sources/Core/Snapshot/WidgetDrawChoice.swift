//
//  WidgetDrawChoice.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation

/// What the widget draws from one read of the Keychain (`WidgetStoredData.read`). Numbers come
/// only from a read that went through, the stale mark included; a read that could not be done
/// draws no one's numbers (not the signed-out face either) and asks again soon. Nothing drawn
/// earlier by the process stands in for it: it was checked against neither the mark nor the
/// person signed in now.
public enum WidgetDrawChoice: Sendable, Equatable {
    case draw(snapshot: HomeSnapshot?, account: SchoolAccount?)
    case noNumbers(retryAfter: TimeInterval)

    public static func choose(_ stored: WidgetStoredData?) -> WidgetDrawChoice {
        guard let stored else { return .noNumbers(retryAfter: WidgetStoredData.unreadableRetry) }
        return .draw(snapshot: stored.snapshot, account: stored.account)
    }
}
