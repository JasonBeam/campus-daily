//
//  FeedbackSender.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/04.
//

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
    /// Text alone is small: it gives up after this long in all, waiting and sending together.
    public static let textOnlyLimit: TimeInterval = 15

    /// How long one send may take: `request` is the wait for each request, `total` the whole send.
    public struct Limits: Equatable, Sendable {
        public var request: TimeInterval
        public var total: TimeInterval
        public init(request: TimeInterval, total: TimeInterval) { self.request = request; self.total = total }
    }

    /// Text alone ends after 15 s; with screenshots, the feedback client's own 30 s and 60 s.
    public static func limits(imageCount: Int) -> Limits {
        imageCount == 0 ? Limits(request: textOnlyLimit, total: textOnlyLimit)
                        : Limits(request: requestTimeout, total: resourceTimeout)
    }

    /// The feedback client's session configuration (`AppEnvironment.feedbackHTTP`).
    public static func configuration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let c = URLSessionHTTPClient.makeConfiguration(protocolClasses: protocolClasses)
        c.timeoutIntervalForRequest = requestTimeout
        c.timeoutIntervalForResource = resourceTimeout
        return c
    }

    private let endpoint: FeedbackEndpoint
    private let http: HTTPClient
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// `sleep` times the whole send (`Limits.total`); tests pass their own.
    public init(endpoint: FeedbackEndpoint, http: HTTPClient,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.endpoint = endpoint; self.http = http; self.sleep = sleep
    }

    /// Throws `FeedbackFailure` for a draft the service would refuse, an error, a non-2xx answer
    /// or a send past its `limits`; `CancellationError` when the calling task was cancelled
    /// (the request is cancelled with it).
    public func send(message: String, images: [Data], metadata: FeedbackMetadata) async throws {
        guard FeedbackDraft.issue(message: message, imageCount: images.count) == nil else { throw FeedbackFailure() }
        let limits = Self.limits(imageCount: images.count)
        var request = HTTPRequest.postJSON(service: .feedback, url: endpoint.url,
                                           headers: ["Authorization": "Bearer \(endpoint.appKey)"],
                                           json: body(message: message, images: images, metadata: metadata),
                                           isStateChanging: true, logName: "feedback")
        request.timeout = limits.request
        let response: HTTPResponse
        do {
            response = try await within(limits.total) { [http, request] in try await http.send(request) }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw FeedbackFailure()
        }
        guard (200 ..< 300).contains(response.status) else { throw FeedbackFailure() }
    }

    /// `work`, cancelled and `ServiceError.timedOut` once `seconds` have passed.
    private func within(_ seconds: TimeInterval,
                        _ work: @escaping @Sendable () async throws -> HTTPResponse) async throws -> HTTPResponse {
        let sleep = self.sleep
        return try await withThrowingTaskGroup(of: HTTPResponse?.self) { group in
            group.addTask { try await work() }
            group.addTask { try await sleep(seconds); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let response = first else { throw ServiceError.timedOut }
            return response
        }
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
