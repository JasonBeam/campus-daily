#if DEBUG
import Foundation
import Core

/// campusdaily://demo/washer/<signed-out|saved|order>: 常用洗衣机 on synthetic values; nothing
/// is sent or changed.
struct WasherSetupDemo: Equatable {
    var signedIn = false
    var mobile: String?
    var machines: [SavedWasher] = []
    var orderOpen = false

    static func handle(_ url: URL) -> WasherSetupDemo? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "washer" else { return nil }
        let machine = SavedWasher(id:"demo-washer", qrCode:"demo", name:"3 号洗衣机", savedAt:Date(timeIntervalSince1970:0))
        switch parts.count > 1 ? parts[1] : "signed-out" {
        case "saved": return WasherSetupDemo(signedIn:true, mobile:"13800000000", machines:[machine])
        case "order": return WasherSetupDemo(signedIn:true, mobile:"13800000000", machines:[machine], orderOpen:true)
        default: return WasherSetupDemo()
        }
    }
}

#endif
