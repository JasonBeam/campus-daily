import UIKit
import Core

/// Sends Settings › 反馈问题 to AirFeedback: the typed text, the chosen screenshots and the device
/// line (app version and build, phone model, system version, locale). Nothing from the accounts.
enum FeedbackReporter {
    /// From Info.plist (`FEEDBACK_ENDPOINT` and `FEEDBACK_APP_KEY`, set by the untracked
    /// private/distribution/Feedback.xcconfig). nil without them, and Settings shows no 反馈问题.
    static let endpoint: FeedbackEndpoint? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let key = info["FeedbackAppKey"] as? String, !key.isEmpty,
              let text = info["FeedbackEndpoint"] as? String, let url = URL(string:text),
              url.scheme == "https", url.host != nil
        else { return nil }
        return FeedbackEndpoint(url:url, appKey:key)
    }()

    /// Throws `FeedbackFailure`. `http` is the injected client (the graph's `CampusServices.feedbackHTTP`).
    /// `debugLog`: the TestFlight log's lines, only when 「附上调试记录」 is on (`DebugLogReport`).
    @MainActor
    static func send(message: String, images: [UIImage], to endpoint: FeedbackEndpoint, http: HTTPClient,
                     debugLog: [String]? = nil) async throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let metadata = FeedbackMetadata(appVersion:info["CFBundleShortVersionString"] as? String ?? "",
                                        appBuild:info["CFBundleVersion"] as? String ?? "",
                                        deviceModel:deviceModel,
                                        osVersion:"\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                                        locale:Locale.current.identifier)
        try await FeedbackSender(endpoint:endpoint, http:http)
            .send(message:message, images:images.compactMap(jpeg), metadata:metadata, debugLog:debugLog)
    }

    /// At most 2048 px on the long side, JPEG.
    private static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / max(longest, 1))
        let size = CGSize(width:image.size.width * scale, height:image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size:size, format:format).image { _ in
            image.draw(in:CGRect(origin:.zero, size:size))
        }.jpegData(compressionQuality:0.8)
    }

    /// The hardware identifier (`iPhone17,2`); `UIDevice.model` only says "iPhone".
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of:&system.machine) { buffer in
            String(decoding:buffer.prefix { $0 != 0 }, as:UTF8.self)
        }
    }
}
