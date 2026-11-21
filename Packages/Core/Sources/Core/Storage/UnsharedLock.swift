//
//  UnsharedLock.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import Foundation

/// `SharedLock` for state no other process reads (tests, previews): `body` just runs.
public struct UnsharedLock: SharedLock {
    public init() {}
    public func locked<T>(_ body: () throws -> T) throws -> T { try body() }
}
