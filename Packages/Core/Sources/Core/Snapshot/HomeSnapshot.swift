//
//  HomeSnapshot.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// One home-screen value with its own freshness. A failed refresh keeps the old value and
/// its `fetchedAt`, and records the error next to it.
public struct Tile<Value: Sendable & Codable & Equatable>: Sendable, Codable, Equatable {
    public var value: Value?
    public var fetchedAt: Date?
    public var error: ServiceError?
    public var errorAt: Date?
    /// The service answered successfully with "nothing here" (e.g. no meter for the node).
    public var notFound: Bool

    public init(value: Value? = nil, fetchedAt: Date? = nil, error: ServiceError? = nil,
                errorAt: Date? = nil, notFound: Bool = false) {
        self.value = value; self.fetchedAt = fetchedAt; self.error = error; self.errorAt = errorAt; self.notFound = notFound
    }

    public mutating func succeed(_ v: Value?, at date: Date) {
        value = v; fetchedAt = date; error = nil; errorAt = nil; notFound = (v == nil)
    }

    public mutating func fail(_ e: ServiceError, at date: Date) {
        error = e; errorAt = date
    }
}

/// What the home screen and the widget show. Shared with the widget through the Keychain
/// access group; contains no credentials.
public struct HomeSnapshot: Sendable, Codable, Equatable {
    public var card: Tile<Money>
    public var power: Tile<Meter>
    /// The card's recent records (最近, 昨天花了).
    public var activity: Tile<CardActivity>
    public var roomLabel: String?
    /// The ecykt session failed the liveness check: show "需重新登录" next to old values.
    public var needsLogin: Bool
    public var checkedAt: Date?
    /// The `SessionEpoch.id` this snapshot was written for (`nil` for legacy 0.11.5 snapshots or `.empty`).
    public var epochID: String?

    public init(card: Tile<Money> = Tile(), power: Tile<Meter> = Tile(), activity: Tile<CardActivity> = Tile(),
                roomLabel: String? = nil, needsLogin: Bool = false, checkedAt: Date? = nil,
                epochID: String? = nil) {
        self.card = card; self.power = power; self.activity = activity; self.roomLabel = roomLabel
        self.needsLogin = needsLogin; self.checkedAt = checkedAt; self.epochID = epochID
    }

    private enum CodingKeys: String, CodingKey { case card, power, activity, roomLabel, needsLogin, checkedAt, epochID }

    /// A snapshot stored before the records or epoch were added has no `activity` / `epochID`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        card = try c.decode(Tile<Money>.self, forKey: .card)
        power = try c.decode(Tile<Meter>.self, forKey: .power)
        activity = try c.decodeIfPresent(Tile<CardActivity>.self, forKey: .activity) ?? Tile()
        roomLabel = try c.decodeIfPresent(String.self, forKey: .roomLabel)
        needsLogin = try c.decode(Bool.self, forKey: .needsLogin)
        checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt)
        epochID = try c.decodeIfPresent(String.self, forKey: .epochID)
    }

    /// True when the snapshot carries no readings, errors, login flag, or check time (ignoring `epochID`).
    public var isEmpty: Bool {
        card == Tile() && power == Tile() && activity == Tile() && roomLabel == nil && !needsLogin && checkedAt == nil
    }

    public static let empty = HomeSnapshot()
    public static let maxEncodedBytes = 64 * 1024
}

public enum SchoolSnapshotEvent: Sendable, Equatable {
    /// `getSysBindCustInfo` succeeded.
    case livenessOK(at: Date)
    /// The liveness check (or re-exchange) says the login is dead.
    case sessionExpired(ServiceError, at: Date)
    /// The liveness check failed for another reason (offline, …): nothing is known about the session.
    case livenessFailed(ServiceError, at: Date)
    case balance(Result<Money, ServiceError>, at: Date)
    /// `.success(nil)` = no meter at the saved node ("没找到电表").
    case meter(Result<Meter?, ServiceError>, at: Date)
    case activity(Result<CardActivity, ServiceError>, at: Date)
    case roomLabel(String?)
    /// No meter is bound any more: its reading and room are forgotten.
    case meterUnbound
    case signedOut
}

/// Pure reducer for the school part of the home snapshot.
public enum SchoolSnapshotReducer {
    public static func reduce(_ s: HomeSnapshot, _ event: SchoolSnapshotEvent) -> HomeSnapshot {
        var s = s
        switch event {
        case .livenessOK(let at):
            s.needsLogin = false
            s.checkedAt = at
        case .sessionExpired(let e, let at):
            // Values stay with their own fetchedAt; every school tile says "re-login".
            s.needsLogin = true
            s.checkedAt = at
            s.card.fail(e, at: at)
            s.power.fail(e, at: at)
            s.activity.fail(e, at: at)
        case .livenessFailed(let e, let at):
            s.checkedAt = at
            s.card.fail(e, at: at)
            s.power.fail(e, at: at)
            s.activity.fail(e, at: at)
        case .balance(.success(let m), let at):
            s.card.succeed(m, at: at)
        case .balance(.failure(let e), let at):
            s.card.fail(e, at: at)
        case .meter(.success(let m), let at):
            s.power.succeed(m, at: at)
        case .meter(.failure(let e), let at):
            s.power.fail(e, at: at)
        case .activity(.success(let a), let at):
            s.activity.succeed(a, at: at)
        case .activity(.failure(let e), let at):
            s.activity.fail(e, at: at)
        case .roomLabel(let label):
            s.roomLabel = label
        case .meterUnbound:
            s.power = Tile()
            s.roomLabel = nil
        case .signedOut:
            s = .empty
        }
        return s
    }
}
