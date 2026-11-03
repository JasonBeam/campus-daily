import SwiftUI

/// 「版本」 with the app's version and build.
struct VersionRow: View {
    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—") + "（" +
        (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—") + "）· 测试版"
    }
    var body: some View {
        LabeledContent("版本", value:version)
    }
}
