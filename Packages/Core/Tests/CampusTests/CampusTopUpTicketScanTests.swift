import XCTest

/// WeChat's ticket links for the school's service work for one user only: the next person is told
/// the link was already used. None may come back in the app or the package's sources.
final class CampusTopUpTicketScanTests: XCTestCase {
    /// The repository root: this file is Packages/Core/Tests/CampusTests/….
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Split so this file does not match itself.
    static let tickets = ["I0xUg" + "rvZt1g", "wxmp" + "url", "dl/" + "business"]
    static let folders = ["App", "Packages/Core/Sources"]
    static let kinds: Set<String> = ["swift", "plist", "json", "xcstrings", "strings", "entitlements", "md"]

    func testNoWeChatTicketLinkIsLeft() throws {
        var scanned = 0
        for folder in Self.folders {
            let base = Self.root.appendingPathComponent(folder)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                XCTFail("missing \(folder) under \(Self.root.path)"); continue
            }
            for case let url as URL in walk where Self.kinds.contains(url.pathExtension) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                scanned += 1
                for ticket in Self.tickets {
                    XCTAssertFalse(text.contains(ticket), "\(ticket) in \(url.path)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 100, "the scan found the sources")
    }
}
