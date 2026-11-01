import Foundation

/// An amount in fen (1/100 yuan). Integer storage, so equality and sums are exact.
public struct Money: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var fen: Int

    public init(fen: Int) { self.fen = fen }

    public static let zero = Money(fen: 0)
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Rounds half away from zero to whole fen.
    public init(yuan: Decimal) {
        var scaled = yuan * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.fen = NSDecimalNumber(decimal: rounded).intValue
    }

    /// Parses a yuan string such as "7.9", ".06", "-1.50", "213.38" (POSIX, no grouping).
    public init?(yuanString raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty,
              text.range(of: #"^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Money.posix) else { return nil }
        self.init(yuan: value)
    }

    /// A JSON number in yuan (e.g. `getUserBalance` returns `7.9`). Goes through the
    /// shortest decimal text of the double, so 7.9 is 790 fen, not 789.
    public init?(yuanNumber value: Double) {
        guard value.isFinite else { return nil }
        self.init(yuanString: String(value))
    }

    public var yuan: Decimal { Decimal(fen) / 100 }

    /// "7.90", "-0.06".
    public var yuanText: String {
        let sign = fen < 0 ? "-" : ""
        let a = abs(fen)
        return "\(sign)\(a / 100).\(String(format: "%02d", a % 100))"
    }

    public var description: String { "¥" + yuanText }

    public static func < (l: Money, r: Money) -> Bool { l.fen < r.fen }
    public static func + (l: Money, r: Money) -> Money { Money(fen: l.fen + r.fen) }
    public static func - (l: Money, r: Money) -> Money { Money(fen: l.fen - r.fen) }
}

public enum DecimalText {
    private static let posix = Locale(identifier: "en_US_POSIX")
    /// Strict POSIX decimal parsing for the string-typed numbers the school returns.
    public static func parse(_ raw: String?) -> Decimal? {
        guard let text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
              text.range(of: #"^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: text, locale: posix)
    }
}
