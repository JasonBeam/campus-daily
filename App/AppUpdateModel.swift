import Foundation
import Combine
import WaterCore

@MainActor final class AppUpdateModel: ObservableObject {
    static let shared = AppUpdateModel()
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled,forKey:"updates.reminders.enabled")
            if !enabled { showPrompt = false }
        }
    }
    @Published private(set) var checking = false
    @Published private(set) var available: AppRelease?
    @Published private(set) var message = "仅检查 GitHub 正式版，不会自动安装。"
    @Published var showPrompt = false
    private var lastAttempt: Date?
    private init() {
        enabled = UserDefaults.standard.object(forKey:"updates.reminders.enabled") as? Bool ?? true
    }
    func check(manual: Bool = false) async {
        guard !checking, manual || enabled else { return }
        if !manual, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 6 * 3600 { return }
        checking = true; lastAttempt = Date()
        defer { checking = false }
        do {
            var request = URLRequest(url:URL(string:"https://api.github.com/repos/JasonBeam/campus-daily/releases/latest")!)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
            request.setValue("CampusDaily",forHTTPHeaderField:"User-Agent")
            let session = URLSession(configuration:.ephemeral)
            defer { session.invalidateAndCancel() }
            let (data,response) = try await session.data(for:request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 524288 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(AppRelease.self,from:data)
            guard !release.prerelease, !release.draft, release.releaseURL != nil, release.iosBuild != nil else {
                throw URLError(.cannotParseResponse)
            }
            let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
            let build = Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "") ?? 0
            available = release.isNewer(than:version,build:build) ? release : nil
            if available != nil {
                message = "发现 \(release.version)（\(release.iosBuild ?? 0)），可查看更新说明。"
                let identity = "\(release.tag_name):\(release.iosBuild ?? 0)"
                if !manual, enabled, UserDefaults.standard.string(forKey:"updates.lastPrompt") != identity {
                    showPrompt = true
                    UserDefaults.standard.set(identity,forKey:"updates.lastPrompt")
                }
            } else { message = "当前已是最新正式版或更新的测试版本。" }
        } catch is CancellationError { }
          catch { message = "暂时无法检查更新，请稍后重试。" }
    }
}
