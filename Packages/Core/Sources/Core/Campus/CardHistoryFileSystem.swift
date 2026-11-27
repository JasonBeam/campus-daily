//
//  CardHistoryFileSystem.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/27.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Persistence boundary used by `CardRecordsLoader` for loading, saving, invalidating,
/// and sweeping the app-private campus card history disk cache.
public protocol CardHistoryCaching: Sendable {
    func load(now: Date, calendar: Calendar, samePerson: @Sendable () async -> Bool) async -> CachedCardHistory?
    func save(_ history: CardHistory, savedAt: Date, latestReadAt: Date, samePerson: @Sendable () async -> Bool) async
    func invalidateAndClear() async
    func invalidateStaleSession() async
    func sweepOrphans() async
}

public extension CardHistoryCaching {
    func save(_ history: CardHistory, savedAt: Date, samePerson: @Sendable () async -> Bool) async {
        await save(history, savedAt: savedAt, latestReadAt: savedAt, samePerson: samePerson)
    }
}

/// File-system abstraction for `CardHistoryDiskCoordinator`, allowing production code to enforce
/// `NSFileProtectionComplete` and `isExcludedFromBackup = true` after atomic replacement, while
/// tests inject lock-screen (`EPERM`/`EACCES`) and delete failures deterministically.
public protocol CardHistoryFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int64
    func createDirectory(at url: URL) throws
    func listDirectory(at url: URL) throws -> [URL]
    func readFile(at url: URL) throws -> Data
    func writeProtectedFile(_ data: Data, to url: URL) throws
    func removeItem(at url: URL) throws
    func isPermissionError(_ error: Error) -> Bool
    func isNotFoundError(_ error: Error) -> Bool
}

public struct LocalCardHistoryFileSystem: CardHistoryFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        }
        return size.int64Value
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try excludeFromBackup(url)
    }

    public func listDirectory(at url: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeProtectedFile(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        // APFS atomic replacement swaps the target inode; explicitly re-apply both
        // `isExcludedFromBackup` and `NSFileProtectionComplete` on the resulting file.
        // If either fails, delete the file so an unprotected or backup-eligible copy never stays.
        do {
            try excludeFromBackup(url)
            #if os(iOS) || os(tvOS) || os(watchOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            #endif
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    public func removeItem(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlying)
        }
        return false
    }

    public func isNotFoundError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isNotFoundError(underlying)
        }
        return false
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }
}
