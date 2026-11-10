import XCTest

/// The check face is gone, and so is any way to resolve or settle again
/// a record whose outcome is unknown: no string the app shows says 去核对,
/// 再洗一次, 再结算一次 or anything of those faces. The product copy for the stopped page and
/// home live in one place (`ShowerAuthorText`). Scans the string literals of the app, widget,
/// shared and Core sources (comments are skipped).
final class ShowerRetiredWordsTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let retired = [
        "去核对",
        "再洗一次",
        "这次洗澡要核对一下",
        "核对上次洗澡",
        "核对上次结算",
        "水控显示已经停了，但这次还没结算上",
        "上一次的记录会留着",
        "我在学校记录里核对过了",
        "核对过了",
        "再结算一次",
        "再查一次水控",
        "不确定结算了没有",
        // The two lines under the button, and their counts: one line now, no count.
        "在水控上按停，这次就算洗完了",
        "上一次是在水控上停的",
        "次是在水控上停的",
        // The demo pages are named for the states they show.
        "sh-check",
        "sh-detail-check",
        // The first-run guide's line about a check that no longer exists.
        "上次洗澡还没核对",
        // Siri, Shortcuts and status: no check is asked for any more.
        "打开校日常核对一下",
        "上次结算还没确认",
        "结算待核对",
    ]

    /// The one file the product copy is in.
    static let wordsFile = "Packages/Core/Sources/Core/Shower/ShowerAuthorText.swift"
    /// Words only that file holds (a literal containing any of them, or equal to `exact`).
    static let oneplace = ["上一次洗好了", "在水控上按停就算洗完了", "开始下一次洗澡"]
    static let oneplaceExact = ["\"去洗澡\""]

    /// Every string literal on a source line, comments left out (`path|trimmed line` for each).
    static func literals() throws -> [(where: String, line: String, literal: String)] {
        var found: [(String, String, String)] = []
        let quoted = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        for folder in ["App", "Shared", "Widget", "Packages/Core/Sources"] {
            let base = root.appendingPathComponent(folder)
            guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.pathExtension == "swift" {
                let path = String(url.path.dropFirst(root.path.count + 1))
                for raw in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n") {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("//") { continue }
                    let range = NSRange(line.startIndex..., in: line)
                    for match in quoted.matches(in: line, range: range) {
                        found.append((path, line, String(line[Range(match.range, in: line)!])))
                    }
                }
            }
        }
        return found
    }

    func testTheSourcesAreScanned() throws {
        let all = try Self.literals()
        XCTAssertTrue(all.contains { $0.literal.contains("结束并结算") }, "the scan reaches the app's strings")
    }

    func testNoRetiredWordIsShown() throws {
        for (path, line, literal) in try Self.literals() {
            for word in Self.retired where literal.contains(word) {
                XCTFail("「\(word)」 in \(path): \(line)")
            }
        }
    }

    func testTheProductCopyIsInOnePlace() throws {
        var seen: Set<String> = []
        for (path, line, literal) in try Self.literals() {
            let words = Self.oneplace.filter { literal.contains($0) } + Self.oneplaceExact.filter { literal == $0 }
            for word in words {
                if path == Self.wordsFile { seen.insert(word) } else { XCTFail("「\(word)」 outside \(Self.wordsFile): \(path): \(line)") }
            }
        }
        XCTAssertEqual(seen, Set(Self.oneplace + Self.oneplaceExact), "all of them are there")
    }
}
