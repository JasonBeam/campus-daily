//
//  ShowerStartOverride.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import CryptoKit
import Foundation

/// The phrase that allows a start below zero on this phone, checked against its digest only.
public enum ShowerStartOverride {
    /// SHA-256 of the normalized phrase, lowercase hex.
    public static let digest = "06c4a8ccadd67692701e20e595ef93f0763d3431b8f743314cf151ca180a642a"

    /// Without any whitespace, upper-cased.
    public static func normalize(_ input: String) -> String {
        String(input.filter { !$0.isWhitespace }).uppercased()
    }

    /// `input` normalized hashes to `digest`.
    public static func matches(_ input: String, digest: String = Self.digest) -> Bool {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { return false }
        let hex = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return hex == digest.lowercased()
    }
}
