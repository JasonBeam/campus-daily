import Foundation

/// The phrase that allows a start below zero on this phone, checked against its digest only.
public enum ShowerStartOverride {
    /// SHA-256 of the normalized phrase, lowercase hex. Red-phase stub: empty.
    public static let digest = ""

    /// Without any whitespace, upper-cased.
    // Red-phase stub: unchanged.
    public static func normalize(_ input: String) -> String { input }

    /// `input` normalized hashes to `digest`.
    // Red-phase stub: never matches.
    public static func matches(_ input: String, digest: String = Self.digest) -> Bool { false }
}
