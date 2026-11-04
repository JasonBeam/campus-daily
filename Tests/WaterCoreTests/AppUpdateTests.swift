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
}
