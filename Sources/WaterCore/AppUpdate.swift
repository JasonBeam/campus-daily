import Foundation

public struct AppRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable { public let name: String }
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
