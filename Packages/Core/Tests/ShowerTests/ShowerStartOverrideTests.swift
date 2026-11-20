import XCTest
import CryptoKit
@testable import Core

/// The phrase that allows a start below zero on this phone: compared by its digest only, after
/// removing every whitespace and ignoring case (no other normalization). Only a made-up phrase
/// and its digest appear here.
final class ShowerStartOverrideTests: XCTestCase {
    /// A made-up phrase, not the real one.
    static let fakePhrase = "ABC12"
    static func hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static var fakeDigest: String { hex(fakePhrase) }

    func testNormalizeRemovesEveryWhitespaceAndUpperCases() {
        XCTAssertEqual(ShowerStartOverride.normalize(" ab c\u{3000}1 2 "), "ABC12")
        XCTAssertEqual(ShowerStartOverride.normalize("a\tb\nc12"), "ABC12")
        XCTAssertEqual(ShowerStartOverride.normalize("abc12"), "ABC12")
    }

    /// Full-width letters are not folded: only whitespace and case.
    func testNormalizeDoesNotFoldFullWidth() {
        XCTAssertEqual(ShowerStartOverride.normalize("ＡＢＣ１２"), "ＡＢＣ１２")
    }

    func testTheFakePhraseMatchesAnyCaseAndSpacing() {
        for input in ["ABC12", "abc12", " A B C 1 2 ", "abc 12", "Abc\u{3000}12"] {
            XCTAssertTrue(ShowerStartOverride.matches(input, digest: Self.fakeDigest), input)
        }
    }

    func testAnythingElseDoesNotMatch() {
        for input in ["ABC1", "ABC123", "", " ", "ＡＢＣ１２", "ABC-12", "XYZ12"] {
            XCTAssertFalse(ShowerStartOverride.matches(input, digest: Self.fakeDigest), input)
        }
    }

    /// The shipped digest is a real SHA-256 in lowercase hex (its phrase is not in the repo).
    func testTheShippedDigestIsAHash() {
        let digest = ShowerStartOverride.digest
        XCTAssertEqual(digest.count, 64)
        XCTAssertTrue(digest.allSatisfy { "0123456789abcdef".contains($0) }, "lowercase hex")
        XCTAssertNotEqual(digest, Self.hex(""), "not the empty phrase")
        XCTAssertNotEqual(digest, Self.fakeDigest)
        XCTAssertFalse(ShowerStartOverride.matches("", digest: digest))
    }
}
