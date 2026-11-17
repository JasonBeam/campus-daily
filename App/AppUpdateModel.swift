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
    @Published private(set) var failed = false
    private var lastSuccess: Date?
    private var lastFailure: Date?
    private var checkedAt: Date?
    private init() {
        enabled = UserDefaults.standard.object(forKey:"updates.reminders.enabled") as? Bool ?? true
        if let bytes = UserDefaults.standard.data(forKey:"updates.cachedRelease"),
           let cached = try? JSONDecoder().decode(AppRelease.self,from:bytes), cached.releaseURL != nil,
           !cached.draft, !cached.prerelease, cached.iosBuild != nil {
            available = newer(cached) ? cached : nil
            checkedAt = UserDefaults.standard.object(forKey:"updates.checkedAt") as? Date
            message = "上次更新信息已保留，联网检查后确认最新版本。"
        }
    }
    func check(manual: Bool = false) async {
        guard !checking, manual || enabled else { return }
        if !manual {
            if let lastSuccess, Date().timeIntervalSince(lastSuccess) < 6 * 3600 { return }
            if let lastFailure, Date().timeIntervalSince(lastFailure) < 60 { return }
        }
        checking = true; failed = false
        defer { checking = false }
        do {
            let session = URLSession(configuration:.ephemeral)
            defer { session.invalidateAndCancel() }
            let release = try await AppUpdateFeed.load { url in
                var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData)
                request.timeoutInterval = 5
                request.setValue("application/json",forHTTPHeaderField:"Accept")
                request.setValue("CampusDaily",forHTTPHeaderField:"User-Agent")
                let (data,response) = try await session.data(for:request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
                return data
            }
            lastSuccess = Date(); lastFailure = nil; checkedAt = Date()
            UserDefaults.standard.set(try JSONEncoder().encode(release),forKey:"updates.cachedRelease")
            UserDefaults.standard.set(checkedAt,forKey:"updates.checkedAt")
            available = newer(release) ? release : nil
            if available != nil {
                message = "发现 \(release.version)（\(release.iosBuild ?? 0)），可查看更新说明。"
                let identity = "\(release.tag_name):\(release.iosBuild ?? 0)"
                if !manual, enabled, UserDefaults.standard.string(forKey:"updates.lastPrompt") != identity {
                    showPrompt = true
                    UserDefaults.standard.set(identity,forKey:"updates.lastPrompt")
                }
            } else { message = "当前已是最新正式版或更新的测试版本。" }
        } catch is CancellationError { }
          catch {
              lastFailure = Date(); failed = true
              if let checkedAt {
                  message = "暂时连不上更新服务；保留上次（" + checkedAt.formatted(date:.abbreviated,time:.shortened) + "）的结果，可直接打开下载页。"
              } else { message = "暂时连不上更新服务，可直接打开下载页查看版本。" }
          }
    }
    private func newer(_ release: AppRelease) -> Bool {
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        let build = Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "") ?? 0
        return release.isNewer(than:version,build:build)
    }
}
