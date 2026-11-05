import Foundation

/// Settings › 版本: 「0.8.0 Beta（48）」 on TestFlight and development builds, 「0.8.0（48）」 from
/// the App Store.
public enum VersionText {
    public static func text(version: String?, build: String?, isBeta: Bool) -> String {
        (version ?? "—") + (isBeta ? " Beta" : "") + "（" + (build ?? "—") + "）"
    }

    /// TestFlight installs carry `sandboxReceipt`; a build installed from Xcode has no receipt.
    public static func isBeta(receiptName: String?, receiptExists: Bool) -> Bool {
        !receiptExists || receiptName == "sandboxReceipt"
    }

    /// A TestFlight install: its receipt is there and named `sandboxReceipt`. Unlike `isBeta`,
    /// a build from Xcode (no receipt) is not one. The debug log is kept only here.
    public static func isTestFlight(receiptName: String?, receiptExists: Bool) -> Bool {
        receiptExists && receiptName == "sandboxReceipt"
    }
}
