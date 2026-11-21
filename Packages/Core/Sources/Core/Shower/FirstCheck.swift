//
//  FirstCheck.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import Foundation

/// Why the first 开始洗澡 on a dorm's controller stopped before anything was asked of the school
/// (the controller's number was not read, or not this dorm's). Nothing was authorized, nothing is
/// kept: 开始洗澡 can be tapped again, and the line under it says what to do, in the notice colour.
public enum FirstCheckFailure: String, Sendable, Equatable, CaseIterable {
    /// No controller in reach (also the most common: not in the dorm).
    case notFound
    /// A controller answered with another machine's number.
    case otherMachine
    /// The controller is running water: its reply has no number, so whose it is is not known.
    case inUse
    /// Bluetooth is off.
    case off
    /// The app may not use Bluetooth (denied or restricted).
    case noPermission
    /// The number could not be read (no answer, the link dropped, a reply nobody can read).
    case readFailed

    public enum Link: Sendable, Equatable { case dorm, settings }

    /// From the failure a start ended in. Nil for anything that is not a check that came to
    /// nothing before the authorize request: a cancel or a withdrawn start (`interrupted`, said
    /// by the face it returns to), and every outcome after the request (kept for the check).
    public static func of(_ failure: ShowerFailure?) -> FirstCheckFailure? {
        guard let failure, !failure.needsReview else { return nil }
        switch failure.reason {
        case .wrongDevice: return .otherMachine
        case .deviceBusy: return .inUse
        case .deviceUnavailable:
            switch failure.deviceError {
            case .notFound?: return .notFound
            case .ambiguous?: return .otherMachine
            case .bluetoothOff?: return .off
            case .unauthorized?: return .noPermission
            case .interrupted?: return nil
            case .timedOut?, .disconnected?, .malformedFrame?, .busy?, nil: return .readFailed
            }
        default: return nil
        }
    }

    public func text(clear: Bool) -> String {
        switch self {
        case .notFound: return clear ? "未找到水控；请靠近水控后重试" : "没找到水控。走到水控旁边再点开始。"
        case .otherMachine:
            return clear ? "附近水控不属于你的宿舍；请在本宿舍重试，或更改宿舍" : "附近的水控不是你宿舍的那台。到自己宿舍再试，宿舍选错了就去改。"
        case .inUse:
            return clear ? "附近水控正在使用，暂无法核对是否为本宿舍水控；请待其停止后重试"
                : "附近的水控有人在用，现在核对不了是不是你宿舍的那台。等它停了再点开始。"
        case .off: return clear ? "蓝牙未开启；请开启后重试" : "蓝牙关着，打开后再点开始。"
        case .noPermission: return clear ? "校日常未获得蓝牙权限；请在系统设置中允许后重试" : "校日常没有蓝牙权限。去设置里打开，再回来点开始。"
        case .readFailed: return clear ? "未能读取水控编号；请靠近水控后重试" : "没读到水控编号。靠近水控再点开始。"
        }
    }

    public var link: Link? {
        switch self {
        case .otherMachine: return .dorm
        case .noPermission: return .settings
        case .notFound, .inUse, .off, .readFailed: return nil
        }
    }

    public static func linkTitle(_ link: Link, clear: Bool) -> String {
        switch link {
        case .dorm: return clear ? "更改宿舍" : "改宿舍"
        case .settings: return clear ? "前往设置" : "去设置"
        }
    }
}

/// The words of the first start's check (核对水控), both themes: the explainer shown once before
/// Bluetooth is asked for, the check while it reads the number, and its short confirmation.
public enum FirstCheckText {
    public static func explainerTitle(clear: Bool) -> String { clear ? "首次洗澡前核对水控" : "先核对你宿舍的水控" }
    public static func explainerBody(clear: Bool) -> String {
        clear ? "需要通过蓝牙连接水控，请在水控旁操作；将先读取水控编号，一致后才开始出水；编号不一致时，校日常不会发起出水或结算"
            : "校日常要用蓝牙连上水控，请站在水控旁边。先看水控上的编号，对上了才开水；编号对不上，校日常就不发起开水或结算。"
    }
    public static func explainerConfirm(clear: Bool) -> String { clear ? "继续" : "好，开始" }
    public static func explainerLater(clear: Bool) -> String { clear ? "稍后" : "等会儿" }
    /// The same sheet for Settings' manual check, if it wants one.
    public static let manualTitle = "核对宿舍的水控"
    public static let manualConfirm = "开始核对"

    /// While the number is read (the first part of the first start).
    public static let checkingButton = "正在核对水控…"
    public static let checkingTitle = "正在核对水控"
    public static func checkingLine(clear: Bool) -> String { clear ? "此步仅读取水控编号，不发送出水指令" : "这一步只看编号，不发开水指令。" }
    /// The number matched: 1.5 s, then the start goes on as usual.
    public static func passed(clear: Bool) -> String { clear ? "已确认为本宿舍水控" : "找到了，是你宿舍的水控。" }
    public static let passedSeconds: Double = 1.5

    /// Siri and Shortcuts can't explain or ask for Bluetooth: the first start is the app's.
    public static func shortcutNeverAsked(clear: Bool) -> String {
        clear ? "首次洗澡需在校日常中点「开始洗澡」以核对水控" : "第一次洗澡要在校日常里点「开始洗澡」，先核对一下水控。"
    }
}
