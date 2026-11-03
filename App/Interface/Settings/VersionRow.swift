import SwiftUI
import Core

/// 「版本」 with the app's version and build: 「0.8.0 Beta（48）」 on TestFlight and builds from
/// Xcode, 「0.8.0（48）」 from the App Store (`VersionText`).
struct VersionRow: View {
    private var version: String {
        let receipt = Bundle.main.appStoreReceiptURL
        return VersionText.text(version:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,
                                build:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String,
                                isBeta:VersionText.isBeta(receiptName:receipt?.lastPathComponent,
                                                          receiptExists:receipt.map { FileManager.default.fileExists(atPath:$0.path) } ?? false))
    }
    var body: some View {
        LabeledContent("版本", value:version)
    }
}
