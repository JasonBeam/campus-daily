import Foundation

/// The feedback service: its endpoint and public ingestion key (`workers app-key`).
public struct FeedbackEndpoint: Sendable, Equatable {
    public var url: URL
    public var appKey: String
    public init(url: URL, appKey: String) { self.url = url; self.appKey = appKey }

    /// The only host the feedback client may reach.
    public var allowedHosts: Set<String> { url.host.map { [$0.lowercased()] } ?? [] }
}

/// The device line sent with each report. Nothing about the person or their accounts.
public struct FeedbackMetadata: Sendable, Equatable {
    public var appVersion: String
    public var appBuild: String
    public var deviceModel: String
    public var osVersion: String
    public var locale: String
    public init(appVersion: String, appBuild: String, deviceModel: String, osVersion: String, locale: String) {
        self.appVersion = appVersion; self.appBuild = appBuild; self.deviceModel = deviceModel
        self.osVersion = osVersion; self.locale = locale
    }
}

/// A send that did not go through. Reads as `FeedbackText.failureText`, whatever the cause.
public struct FeedbackFailure: LocalizedError, Equatable, Sendable {
    public init() {}
    public var errorDescription: String? { FeedbackText.failureText }
}

/// Sends one report: the typed text, the chosen screenshots (JPEG) and the device line.
/// The client is passed in (the app's `AppEnvironment.feedbackHTTP`); it builds none of its own.
public struct FeedbackSender: Sendable {
    /// The feedback client's resource timeout: four screenshots take longer than the clients'
    /// usual 20 s on a slow connection.
    public static let resourceTimeout: TimeInterval = 60
    /// The feedback client's wait for each request: the first connection of an app run to the
    /// feedback host can take longer than the clients' usual 15 s to set up.
    public static let requestTimeout: TimeInterval = 30

    /// The feedback client's session configuration (`AppEnvironment.feedbackHTTP`).
    public static func configuration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let c = URLSessionHTTPClient.makeConfiguration(protocolClasses: protocolClasses)
        c.timeoutIntervalForRequest = requestTimeout
        c.timeoutIntervalForResource = resourceTimeout
        return c
    }

    private let endpoint: FeedbackEndpoint
    private let http: HTTPClient

    public init(endpoint: FeedbackEndpoint, http: HTTPClient) { self.endpoint = endpoint; self.http = http }

    /// Throws `FeedbackFailure` for a draft the service would refuse, an error or a non-2xx answer.
    public func send(message: String, images: [Data], metadata: FeedbackMetadata) async throws {
        guard FeedbackDraft.issue(message: message, imageCount: images.count) == nil else { throw FeedbackFailure() }
        let request = HTTPRequest.postJSON(service: .feedback, url: endpoint.url,
                                           headers: ["Authorization": "Bearer \(endpoint.appKey)"],
                                           json: body(message: message, images: images, metadata: metadata),
                                           isStateChanging: true, logName: "feedback")
        let response: HTTPResponse
        do { response = try await http.send(request) } catch { throw FeedbackFailure() }
        guard (200 ..< 300).contains(response.status) else { throw FeedbackFailure() }
    }

    private func body(message: String, images: [Data], metadata: FeedbackMetadata) -> [String: JSONValue] {
        [
            "message": .string(message),
            "appVersion": .string(metadata.appVersion),
            "appBuild": .string(metadata.appBuild),
            "deviceModel": .string(metadata.deviceModel),
            "osVersion": .string(metadata.osVersion),
            "locale": .string(metadata.locale),
            "images": .array(images.map { .object(["mediaType": .string("image/jpeg"), "data": .string($0.base64EncodedString())]) }),
        ]
    }
}
