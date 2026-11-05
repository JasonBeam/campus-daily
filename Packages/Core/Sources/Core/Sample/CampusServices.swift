import Foundation

/// The stores and services one graph of the app's models runs on. The live app has one (the
/// Keychain, UserDefaults, the App Group, the network, Bluetooth, its files); each
/// 「先看看示例」 gets its own from `sample()`, built from nothing the live one holds, so a sample
/// page can't reach a real store or service whatever it calls. The models take one of these
/// and name no store or service themselves.
public final class CampusServices: @unchecked Sendable {
    // @unchecked: every stored property is a `let`; `defaults` is thread-safe.
    public enum Kind: Sendable, Equatable { case live, sample }

    /// Tells two graphs apart (the sample's pages are rebuilt for each new sample).
    public let id = UUID()
    public let kind: Kind
    /// The Keychain (school, hot-water and laundry vaults, the widget snapshot, the reset marker).
    public let secureStore: any SecureStore
    /// The app's preferences; `@AppStorage` reads and writes the same ones.
    public let defaults: UserDefaults
    /// The App Group's preferences (the theme the widget draws); nil in a build without the group.
    public let sharedPreferences: (any PreferenceStorage)?
    public let schoolHTTP: any HTTPClient
    public let showerHTTP: any HTTPClient
    public let laundryHTTP: any HTTPClient
    /// Settings › 反馈问题's; nil in a build without the feedback key.
    public let feedbackHTTP: (any HTTPClient)?
    public let showerTransport: any ShowerTransport
    /// The school refresh's lease file; nil: no lease.
    public let leaseFile: LeaseFile?
    /// Where the app keeps its files (the imported hot-water profile, the laundry cache); nil:
    /// no files, nothing read or written.
    public let applicationSupport: URL?
    /// Something shared with the widget changed (the theme, the snapshot): it draws again.
    public let sharedDidChange: @Sendable () -> Void
    /// The TestFlight debug log; `NoDebugLog` in any other install and in every sample.
    public let debugLog: any DebugLogSink
    /// `nav.open` lines on `debugLog`, for the pages of both themes.
    public let debugNav: DebugNav

    public init(kind: Kind, secureStore: any SecureStore, defaults: UserDefaults, sharedPreferences: (any PreferenceStorage)?,
                schoolHTTP: any HTTPClient, showerHTTP: any HTTPClient, laundryHTTP: any HTTPClient, feedbackHTTP: (any HTTPClient)?,
                showerTransport: any ShowerTransport, leaseFile: LeaseFile?, applicationSupport: URL?,
                sharedDidChange: @escaping @Sendable () -> Void, debugLog: any DebugLogSink = NoDebugLog()) {
        self.kind = kind; self.secureStore = secureStore; self.defaults = defaults; self.sharedPreferences = sharedPreferences
        self.schoolHTTP = schoolHTTP; self.showerHTTP = showerHTTP; self.laundryHTTP = laundryHTTP; self.feedbackHTTP = feedbackHTTP
        self.showerTransport = showerTransport; self.leaseFile = leaseFile; self.applicationSupport = applicationSupport
        self.sharedDidChange = sharedDidChange
        self.debugLog = debugLog
        self.debugNav = DebugNav(log: debugLog)
    }

    public var schoolVault: StoredSchoolVault { StoredSchoolVault(store: secureStore) }
    public var showerVault: StoredShowerVault { StoredShowerVault(store: secureStore) }
    public var laundryVault: StoredLaundryVault { StoredLaundryVault(store: secureStore) }
    public var resetMarker: ResetMarker { ResetMarker(store: secureStore) }

    /// The school session and the snapshot refresher on these services (the app's "app" role).
    public func schoolStack(role: String = "app") -> SchoolRefreshStack {
        let changed = sharedDidChange
        return SchoolRefreshStack(store: secureStore, http: schoolHTTP, role: role, leaseWait: SchoolRefreshStack.appLeaseWait,
                                  leaseFile: leaseFile, didWriteSnapshot: { changed() },
                                  debugLog: role == "widget" ? NoDebugLog() : debugLog)
    }

    /// The hot-water engine as the app builds it, on these services: their vault, Bluetooth and
    /// the platform gateway `gateway` (over `showerHTTP`).
    public func showerEngine(gateway: any ShowerGateway, bleName: String) throws -> ShowerEngine {
        try ShowerEngine(transport: showerTransport, gateway: gateway, vault: showerVault,
                         configuration: .init(bleName: bleName),
                         hooks: debugLog.isEnabled ? DebugLogShowerHooks(debugLog) : nil, resetMarker: resetMarker)
    }

    /// The hot-water platform client on `showerHTTP`.
    public func showerGateway(profile: ShowerPlatformProfile) -> any ShowerGateway {
        LxtClient(http: showerHTTP, profile: profile)
    }

    /// A new sample's: an empty in-memory Keychain and preferences, every request refused before
    /// it is sent, Bluetooth that finds nothing, no files and no widget. Takes nothing from the
    /// live services: there is nothing to pass it.
    public static func sample() -> CampusServices {
        let http = SampleHTTPClient()
        return CampusServices(kind: .sample, secureStore: InMemorySecureStore(), defaults: SampleDefaults(),
                              sharedPreferences: SampleDefaults(), schoolHTTP: http, showerHTTP: http, laundryHTTP: http,
                              feedbackHTTP: http, showerTransport: SampleShowerTransport(), leaseFile: nil,
                              applicationSupport: nil, sharedDidChange: {})
    }
}

/// The sample's network: refuses every request before anything is sent (`offline`).
public struct SampleHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw ServiceError.offline }
}

/// The sample's Bluetooth: no controller is ever found, nothing is written.
public struct SampleShowerTransport: ShowerTransport {
    public init() {}
    public func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String {
        throw ShowerDeviceError.notFound
    }
    public func exchange(_ command: Data) async throws -> Data { throw ShowerCommandNotSent(.disconnected) }
    public func disconnect() async {}
}

/// The sample's payments: nothing opens (no Alipay, no checkout page), every launch refused.
public struct SamplePaymentLauncher: PaymentLauncher {
    public init() {}
    public func open(_ launch: PayLaunch) async -> Bool { false }
}
