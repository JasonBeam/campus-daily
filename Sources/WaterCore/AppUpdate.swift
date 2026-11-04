import Foundation

public struct AppRelease: Codable, Sendable {
    public struct Asset: Codable, Sendable { public let name: String }
    public let tag_name: String
    public let html_url: String
    public let prerelease: Bool
    public let draft: Bool
    public let assets: [Asset]
    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    public var releaseURL: URL? {
        guard let url = URL(string:html_url), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.path == "/JasonBeam/campus-daily/releases/tag/\(tag_name)" else { return nil }
        return url
    }
    public var iosBuild: Int? {
        let prefix = "CampusDaily-\(version)-build", suffix = "-unsigned.ipa"
        return assets.compactMap { asset -> Int? in
            guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(suffix) else { return nil }
            return Int(asset.name.dropFirst(prefix.count).dropLast(suffix.count))
        }.max()
    }
    public func isNewer(than currentVersion: String, build: Int) -> Bool {
        func parts(_ text: String) -> [Int]? {
            let fields = text.split(separator:".",omittingEmptySubsequences:false)
            guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
            let numbers = fields.compactMap { Int($0) }
            return numbers.count == 3 ? numbers : nil
        }
        guard !draft, !prerelease, releaseURL != nil, let remote = parts(version),
              let local = parts(currentVersion), let latestBuild = iosBuild else { return false }
        if remote != local { return local.lexicographicallyPrecedes(remote) }
        return latestBuild > build
    }
}


/// Public metadata only. No account token is sent to either update source.
public enum AppUpdateFeed {
    public static let sources = [
        URL(string:"https://api.github.com/repos/JasonBeam/campus-daily/releases/latest")!,
        URL(string:"https://jasonbeam.github.io/campus-daily/updates.json")!
    ]
    public static func load(fetch: (URL) async throws -> Data) async throws -> AppRelease {
        var failure: Error = URLError(.cannotLoadFromNetwork)
        for url in sources {
            try Task.checkCancellation()
            do {
                let data = try await fetch(url)
                guard data.count <= 524288 else { throw URLError(.dataLengthExceedsMaximum) }
                let release = try JSONDecoder().decode(AppRelease.self,from:data)
                guard !release.draft, !release.prerelease, release.releaseURL != nil,
                      release.iosBuild != nil, release.isNewer(than:"0.0.0",build:0) else { throw URLError(.cannotParseResponse) }
                return release
            } catch is CancellationError { throw CancellationError() }
              catch { failure = error }
        }
        throw failure
    }
}
