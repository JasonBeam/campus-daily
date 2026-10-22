import Foundation
import WaterCore

// Read-only, offline comparison. Never sends an HTTP request or opens Bluetooth.
do {
    guard CommandLine.arguments.count == 3 else {
        throw WaterError.invalidConfig
    }
    let config = try JSONDecoder().decode(WaterConfig.self,
        from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    try config.validate()
    let har = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
    let entries = (har["log"] as! [String: Any])["entries"] as! [[String: Any]]
    var matched = 0
    for entry in entries {
        guard let request = entry["request"] as? [String: Any], let url = request["url"] as? String,
              url.hasSuffix("/bathingConsumptionAuthorization") || url.hasSuffix("/analysisOfBathingConsumptionData"),
              let post = request["postData"] as? [String: Any], let text = post["text"] as? String else { continue }
        let items = URLComponents(string: "https://offline.invalid/?" + text)?.queryItems ?? []
        func value(_ name: String) -> String? {
            // URLComponents doesn't decode + as form-space.
            let raw = text.split(separator: "&").first { $0.hasPrefix(name + "=") }?
                .dropFirst(name.count + 1).replacingOccurrences(of: "+", with: " ")
            return raw?.removingPercentEncoding
        }
        guard !items.isEmpty, let code = value("wxcode"), let sign = value("sign"),
              WaterProtocol.signature(secret: config.secret, wxcode: code) == sign.lowercased() else { throw WaterError.provider }
        matched += 1
    }
    guard matched >= 2 else { throw WaterError.provider }
    print("Offline HAR signatures matched: \(matched). HTTP requests: 0. Bluetooth writes: 0.")
} catch {
    fputs("Offline evidence check failed; private inputs were not printed.\n", stderr)
    exit(1)
}
