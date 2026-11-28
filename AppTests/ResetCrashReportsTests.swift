//
//  ResetCrashReportsTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 重置校日常 leaves no crash report behind: the reports waiting to be sent and the per-install
/// id go with everything else.
@MainActor
final class ResetCrashReportsTests: XCTestCase {
    private let installIDKey = "AirCrashReports.installID"

    func testThePendingFolderIsTheOneTheCrashFileWrites() throws {
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        XCTAssertEqual(CrashReportsLaunch.pendingFolder(in: support).standardizedFileURL,
                       try XCTUnwrap(AirCrashReports.defaultFolder()).standardizedFileURL)
    }

    /// The crash file keeps its id in `UserDefaults.standard`: the live app's preferences, whose
    /// whole domain a reset removes.
    func testTheLiveAppResetsTheDefaultsTheInstallIDIsIn() {
        XCTAssertTrue(AppEnvironment.live.defaults === UserDefaults.standard)
    }

    func testAResetDeletesPendingReportsAndTheInstallID() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let pending = CrashReportsLaunch.pendingFolder(in: support)
        XCTAssertNotEqual(pending.standardizedFileURL, support.standardizedFileURL)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let report = pending.appendingPathComponent("\(UUID().uuidString.lowercased()).json")
        try Data(#"{"synthetic":true}"#.utf8).write(to: report)

        let http = SampleHTTPClient()
        let leaseURL = support.appendingPathComponent("refresh.lease")
        let services = CampusServices(kind: .live, secureStore: InMemorySecureStore(), defaults: SampleDefaults(),
                                      sharedPreferences: nil, schoolHTTP: http, showerHTTP: http, laundryHTTP: http,
                                      feedbackHTTP: nil, showerTransport: SampleShowerTransport(), leaseFile: LeaseFile(url: leaseURL),
                                      applicationSupport: support, sharedDidChange: {})
        services.defaults.set(UUID().uuidString.lowercased(), forKey: installIDKey)
        let graph = CampusGraph.sample(on: services, theme: .warm)

        let stopped = try await graph.resetter.reset(campus: graph.campus, shower: graph.shower,
                                                     laundry: graph.laundry, theme: graph.theme)
        XCTAssertNil(stopped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: report.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertNil(services.defaults.string(forKey: installIDKey))
    }

    func testSignOutForResetFailsClosedWhenEpochReadFailsAfterSignOut() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let store = ScriptedStore()
        store.afterWrite = { key in
            guard key == .sharedSessionEpoch else { return }
            if let epoch = try? SessionEpochStore(store: store).read(), epoch.phase == .signedOut {
                store.refusingReads = [.sharedSessionEpoch]
            }
        }
        let http = SampleHTTPClient()
        let leaseURL = support.appendingPathComponent("refresh.lease")
        let services = CampusServices(kind: .live, secureStore: store, defaults: SampleDefaults(),
                                      sharedPreferences: nil, schoolHTTP: http, showerHTTP: http, laundryHTTP: http,
                                      feedbackHTTP: nil, showerTransport: SampleShowerTransport(), leaseFile: LeaseFile(url: leaseURL),
                                      applicationSupport: support, sharedDidChange: {})
        let graph = CampusGraph.sample(on: services, theme: .warm)

        do {
            _ = try await graph.campus.signOutForReset()
            XCTFail("expected AppReset.Failure when signed-out epoch cannot be read back")
        } catch let failure as AppReset.Failure {
            XCTAssertEqual(failure.items, [StoreKey.sharedSessionEpoch.rawValue])
        }
    }
}
