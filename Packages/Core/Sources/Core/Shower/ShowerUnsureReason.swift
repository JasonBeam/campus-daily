//
//  ShowerUnsureReason.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation

/// Why a shower's outcome is not known, as far as the saved record can tell (it survives a
/// relaunch: every input is stored). Nil when the record is not an unknown outcome, or when its
/// own words already say it (an authorize that never reached the controller: 「水没开」; a close
/// whose controller was then seen stopped: the kept face).
public enum ShowerUnsureReason: String, Sendable, Equatable, CaseIterable {
    /// A: the school answered the authorize with its unfinished-order refusal (4060).
    case unfinishedOrderAtStart
    /// B: the settlement may have left and no answer came back.
    case settleNoAnswer
    /// C: the close went out and no end data came back.
    case closeNoAnswer
    /// D: the controller got the authorization and did not confirm it.
    case startUnconfirmed
    /// F: the school did not accept the settlement.
    case settleRefused
    /// F': the school refused the settlement with its unfinished-order answer (4060).
    case unfinishedOrderAtSettle
    /// G: the settlement provably never left.
    case settleNotSent
    /// E: anything else the record can't tell apart.
    case other

    public static func of(_ s: ShowerState) -> ShowerUnsureReason? {
        switch s.phase {
        case .writePending:
            // D: the authorization went to the controller, which did not confirm it. Not once it
            // provably never got there, nor once the controller showed the session stopped.
            return s.authorizeSent && !s.authorizationNotWritten && !s.stateReviewRequired ? .startUnconfirmed : nil
        case .failed:
            guard let f = s.failure, f.needsReview else { return nil }
            switch f.reason {
            case .authorizeUncertain, .authorizationInvalid:
                // A; any other keeps 「水没开」 (`ShowerAuthorizeUnclearText`).
                return f.error == .officialUnfinishedOrder ? .unfinishedOrderAtStart : nil
            case .closeBusy, .closeUnconfirmed:
                // C, until a check saw the controller stopped: then the kept words.
                return s.closeStopSeen ? nil : .closeNoAnswer
            case .settleUncertain:
                return .settleNoAnswer
            case .settleUnconfirmed:
                // G when it provably never left (also a frame an older build held), else B.
                return f.settleNotSent ? .settleNotSent : .settleNoAnswer
            case .settleRefused:
                return f.error == .officialUnfinishedOrder ? .unfinishedOrderAtSettle : .settleRefused
            case .deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused:
                return .other
            }
        default:
            return nil
        }
    }
}
