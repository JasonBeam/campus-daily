import Foundation
import Testing
@testable import WaterCore

struct AppUpdateTests {
    private func release(_ version: String = "0.8.0", build: Int = 38, prerelease: Bool = false,
                         url: String? = nil, asset: String? = nil) throws -> AppRelease {
        let body: [String:Any] = ["tag_name":"v" + version,
            "html_url":url ?? "https://github.com/JasonBeam/campus-daily/releases/tag/v\(version)",
            "prerelease":prerelease,"draft":false,
            "assets":[["name":asset ?? "CampusDaily-\(version)-build\(build)-unsigned.ipa"]]]
        return try JSONDecoder().decode(AppRelease.self,from:JSONSerialization.data(withJSONObject:body))
    }
    @Test func doesNotOfferInstalledOrOlderBuild() throws {
        let value = try release()
        #expect(!value.isNewer(than:"0.8.0",build:38))
        #expect(!value.isNewer(than:"0.8.0",build:41))
        #expect(!value.isNewer(than:"0.9.0",build:1))
        #expect(try release(build:42).isNewer(than:"0.8.0",build:41))
    }
    @Test func comparesVersionNumbersAndRequiresIOSArtifact() throws {
        #expect(try release("0.10.0",build:1).isNewer(than:"0.9.0",build:90))
        #expect(try !release("0.9.0",build:90).isNewer(than:"0.10.0",build:1))
        #expect(try !release("0.9.0",asset:"CampusDaily-debug.apk").isNewer(than:"0.8.0",build:38))
        #expect(try !release("0.9.0-beta").isNewer(than:"0.8.0",build:38))
        #expect(try !release("0.9.0",prerelease:true).isNewer(than:"0.8.0",build:38))
    }
    @Test func refusesUnrelatedReleaseLinks() throws {
        for url in ["https://example.com/","https://github.com/Other/campus-daily/releases/tag/v0.9.0",
                    "https://user@github.com/JasonBeam/campus-daily/releases/tag/v0.9.0"] {
            #expect(try !release("0.9.0",url:url).isNewer(than:"0.8.0",build:38))
        }
    }
    @Test func rateLimitFallsBackToPublicFeedAndFindsUpdateForBuild50() async throws {
        let data = try JSONEncoder().encode(release("0.9.0",build:52))
        var calls: [URL] = []
        let found = try await AppUpdateFeed.load { url in
            calls.append(url)
            if calls.count == 1 { throw URLError(.badServerResponse) }
            return data
        }
        #expect(calls == AppUpdateFeed.sources)
        #expect(found.isNewer(than:"0.8.0",build:50))
    }
    @Test func invalidPrimaryResponseCannotHideValidFallback() async throws {
        let data = try JSONEncoder().encode(release("0.9.0",build:52))
        var count = 0
        let found = try await AppUpdateFeed.load { _ in
            count += 1
            return count == 1 ? Data("{\"message\":\"API rate limit exceeded\"}".utf8) : data
        }
        #expect(count == 2); #expect(found.iosBuild == 52)
    }
    @Test func cancellationNeverStartsAnotherNetworkRequest() async throws {
        var count = 0
        do {
            _ = try await AppUpdateFeed.load { _ in count += 1; throw CancellationError() }
            Issue.record("Cancellation must propagate")
        } catch is CancellationError { }
        #expect(count == 1)
    }
    @Test func unavailableSourcesFailWithoutInventingLatestVersion() async {
        var count = 0
        do {
            _ = try await AppUpdateFeed.load { _ in count += 1; throw URLError(.notConnectedToInternet) }
            Issue.record("Offline checks must fail")
        } catch { }
        #expect(count == 2)
    }

}
