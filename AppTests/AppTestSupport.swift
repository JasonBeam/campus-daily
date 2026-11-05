import SwiftUI
import UIKit
import XCTest
import Core
@testable import XiaoRiChang

/// A Keychain in memory whose shower-record reads can be made to fail: `sessionReadError` is
/// asked with the read's number (0 = the first) and throws what it returns.
final class ScriptedStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var sessionReads = 0
    var sessionReadError: @Sendable (Int) -> Error? = { _ in nil }

    func read(_ key: StoreKey) throws -> Data? {
        let (data, error): (Data?, Error?) = lock.withLock {
            if key == .showerSession {
                defer { sessionReads += 1 }
                if let error = sessionReadError(sessionReads) { return (nil, error) }
            }
            return (items[key.rawValue], nil)
        }
        if let error { throw error }
        return data
    }
    func write(_ data: Data, for key: StoreKey) throws { lock.withLock { items[key.rawValue] = data } }
    func delete(_ key: StoreKey) throws { _ = lock.withLock { items.removeValue(forKey: key.rawValue) } }
}

/// The hot-water platform with every request held until `release`; `reached` says when the
/// first one arrived, `sent` counts them. A held request ends offline (nothing confirmed).
final class HeldHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent = 0
    private var arrived = false
    private let held: AsyncStream<Void>
    private let go: AsyncStream<Void>.Continuation
    var sent: Int { lock.withLock { _sent } }

    init() { (held, go) = AsyncStream<Void>.makeStream() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _sent += 1; arrived = true }
        for await _ in held { break }
        throw ServiceError.offline
    }

    /// True once a request arrived; false after about two seconds without one (never hangs).
    func reached() async -> Bool {
        for _ in 0..<200 where !lock.withLock({ arrived }) { try? await Task.sleep(for: .milliseconds(10)) }
        return lock.withLock { arrived }
    }

    func release() { go.yield(); go.finish() }
}

enum Fixture {
    static let binding = ShowerBinding(studentId: "S-1", schoolId: "1", machineId: "11223344", roomId: "R-1", roomLabel: "99栋 991")
    static let running = ShowerState(phase: .running, machineID: "11223344", startedAt: Date(), authorizationID: "A1")
    /// Over, its settlement not confirmed (待核对): 再结算一次 may send it again (its consumption
    /// frame: the controller's 20-byte reply, 0x55 then the machine).
    static let awaitingReview = ShowerState(phase: .failed, machineID: "11223344", startedAt: Date(), authorizationID: "A1",
                                            consumption: "5511223344" + String(repeating: "00", count: 15),
                                            failure: ShowerFailure(reason: .settleUnconfirmed, needsReview: true))
    /// A synthetic platform profile (`.waterconfig`) in a new folder, as an import leaves it.
    static func supportWithProfile() throws -> URL {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        let url = ShowerProfileFiles.importedURL(in: support)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"secret":"synthetic-secret","sid":"synthetic-sid","bleName":"SYNTHETIC","typeID":1,"version":1}"#.utf8).write(to: url)
        return support
    }
}

/// The live hot-water model as the app builds it (`ShowerModel.shared`), on fake stores: its
/// own gate, shared with a `SampleMode` the way the app shares `ShowerModel.liveGate`.
@MainActor func liveShowerModel(store: SecureStore, support: URL? = nil,
                                showerHTTP: any HTTPClient = SampleHTTPClient()) -> (ShowerModel, SampleMode) {
    let services = CampusServices(kind: .live, secureStore: store, defaults: SampleDefaults(), sharedPreferences: nil,
                                  schoolHTTP: SampleHTTPClient(), showerHTTP: showerHTTP, laundryHTTP: SampleHTTPClient(),
                                  feedbackHTTP: nil, showerTransport: SampleShowerTransport(), leaseFile: nil,
                                  applicationSupport: support, sharedDidChange: {})
    let gate = LiveShowerGate()
    let model = ShowerModel(services: services, reminders: .sample(defaults: services.defaults), activities: nil, gate: gate)
    return (model, SampleMode(gate: gate))
}

/// Waits (letting the main run loop and its tasks go on) until `done` or about two seconds.
@MainActor func waitUntil(_ done: () -> Bool) async {
    for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

/// The app's scene as `XiaoRiChangApp` draws it (the sample's graph while it is on, else the
/// "live" one), in a window of its own. The live graph here is built on in-memory services
/// (`CampusServices.sample()`): nothing real is read or sent. 清爽's root tells its navigator.
@MainActor final class RootHarness {
    let sample: SampleMode
    let graph: CampusGraph
    let window: UIWindow
    private(set) var navigator: ClearNavigator?

    init(theme: AppTheme, seenSetup: Bool) {
        let services = CampusServices.sample()
        services.defaults.set(seenSetup, forKey: QuickSetupSeen.key)
        graph = CampusGraph.sample(on: services, theme: theme)
        sample = SampleMode(gate: LiveShowerGate(record: { .known(.idle) }))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let root = HarnessScene(graph: graph, sample: sample, alerts: SampleAlertStack()) { [weak self] in self?.navigator = $0 }
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
    }

    /// What is presented over the root (a sheet, or a full-screen cover such as the first-run guide).
    var presented: UIViewController? { window.rootViewController?.presentedViewController }
    var coverShown: Bool { presented.map { [.fullScreen, .overFullScreen].contains($0.modalPresentationStyle) } ?? false }
    var sheetShown: Bool { presented != nil && !coverShown }

    func link(_ text: String) -> SampleLinkOutcome { sample.open(URL(string: text)!) }

    func close() {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }
}

private struct HarnessScene: View {
    let graph: CampusGraph
    let sample: SampleMode
    let alerts: SampleAlertStack
    let navigatorShown: (ClearNavigator) -> Void

    var body: some View {
        ZStack {
            if let services = sample.services {
                SampleScene(services: services, theme: graph.theme.theme).id(services.id)
            } else {
                live
            }
        }
        .environment(sample).environment(alerts)
    }

    /// `CampusScene` + `CampusRootView`, with 清爽's root telling its navigator.
    private var live: some View {
        Group {
            switch graph.theme.theme {
            case .warm: HomeView()
            case .clear: ClearRootView(navigatorShown: navigatorShown)
            }
        }
        .environment(\.appTheme, graph.theme.theme)
        .environmentObject(graph.shower).environmentObject(graph.campus).environmentObject(graph.laundry)
        .environmentObject(graph.reminders).environmentObject(graph.resetter)
        .environment(graph.theme)
        .environment(\.campusServices, graph.services)
        .defaultAppStorage(graph.services.defaults)
    }
}
