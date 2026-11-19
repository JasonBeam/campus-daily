import Foundation

/// What `AirCrashReports` starts with: the feedback form's public key (`FeedbackAppKey`) and the
/// crash endpoint (`FeedbackCrashEndpoint`, from `FEEDBACK_CRASH_ENDPOINT` in the untracked
/// private/distribution/Feedback.xcconfig). nil without either, and crash reports stay off.
struct CrashReportsLaunch: Equatable {
    let apiKey: String
    let endpoint: String

    init?(info: [String: Any]) {
        guard let key = info["FeedbackAppKey"] as? String, !key.isEmpty,
              let endpoint = info["FeedbackCrashEndpoint"] as? String,
              let url = URL(string:endpoint), url.scheme == "https", url.host != nil
        else { return nil }
        apiKey = key
        self.endpoint = endpoint
    }

    /// Where `AirCrashReports` keeps the reports it has not sent yet (its `defaultFolder()` on
    /// iOS), for 重置校日常.
    static func pendingFolder(in applicationSupport: URL) -> URL {
        applicationSupport.appending(path:"AirCrashReports", directoryHint:.isDirectory)
    }

    /// Calls `start` with both values, or not at all; true when it did.
    @discardableResult
    static func start(info: [String: Any], start: (_ apiKey: String, _ endpoint: String) -> Void) -> Bool {
        guard let launch = CrashReportsLaunch(info:info) else { return false }
        start(launch.apiKey, launch.endpoint)
        return true
    }
}
