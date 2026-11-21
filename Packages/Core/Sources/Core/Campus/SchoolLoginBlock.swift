//
//  SchoolLoginBlock.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import Foundation

/// Why the school would not take a password login it did not call wrong, as far as the page or
/// reply it sent shows. Nothing here carries the school's words.
public enum SchoolLoginBlock: String, Sendable, Equatable, CaseIterable {
    /// The account is locked (too many wrong tries). The school's settings unlock it after a
    /// fixed time; the reply itself does not say how long, so waiting it out is the advice.
    case locked
    /// A captcha the school asks for.
    case captcha
    /// An extra check: SMS, phone or email code, a new-device check.
    case mfa
    /// A forced password change, a weak or initial password, or an account to activate first.
    case passwordChange
    /// A page or reply we don't recognise.
    case unknown

    /// The three the school's own site can clear (the app opens it in Safari).
    public var needsSchoolSite: Bool {
        switch self {
        case .captcha, .mfa, .passwordChange: return true
        case .locked, .unknown: return false
        }
    }
}
